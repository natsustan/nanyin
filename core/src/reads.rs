//! Catalogue reads over the streaming session, for what the app's Web API
//! grant cannot read: since late 2024, Development Mode apps get no access
//! to playlists the listener does not own, nor to an artist's top tracks.
//! The session speaks the protocol Spotify's own clients use, as spotifast
//! does. Also resolves the play queue's tracks, so all go through one
//! batched, cached lookup. A song's credits come the same way, as the
//! desktop client reads them.

use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
};

use http::Method;
use librespot_core::{Error, Session, SpotifyUri, spotify_id::SpotifyId};
use librespot_metadata::{
    Artist, Metadata, Playlist, Track as SessionTrack, artist::CountryTopTracks,
    playlist::attribute::PlaylistAttributes,
};
use librespot_protocol::{
    extended_metadata::{BatchedEntityRequest, EntityRequest, ExtensionQuery},
    extension_kind::ExtensionKind,
    metadata::Track as TrackMessage,
};
use protobuf::{EnumOrUnknown, Message};
use serde::{Deserialize, Serialize};

use crate::{
    events::Track,
    pathfinder::{HomeShelves, Image, Pathfinder, ReleaseAlbum},
};

/// Rows per page, as the Web API's limit.
const PAGE: usize = 50;
/// Songs on an artist's Popular list, as Spotify's own clients show.
const TOP: usize = 10;
/// Lists kept between pages of one read; past this the least recently
/// read is let go.
const KEPT: usize = 8;
/// Tracks remembered; past this the memory starts over.
const REMEMBERED: usize = 2000;

#[derive(Debug, Serialize, PartialEq)]
pub struct PlaylistPage {
    /// The songs in the whole list; episodes and local files are not shown.
    pub total: usize,
    pub rows: Vec<PlaylistRow>,
    /// The offset of the next page, or none at the end.
    pub next: Option<usize>,
    /// Header metadata from the playlist itself, sent on the first page so
    /// entries the Web API left blank still get a title, description and cover.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub images: Vec<Image>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct PlaylistRow {
    /// Position among the list's songs; a song Spotify no longer has is
    /// left out.
    pub index: usize,
    pub added_at_ms: Option<i64>,
    pub track: Track,
}

/// A song's credits as Spotify's own clients show them: roles (performers,
/// writers, producers), each with the people credited, and the labels or
/// distributors that supplied them. Read from the desktop client's
/// `track-credits-view`; anything missing reads as empty.
#[derive(Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Credits {
    #[serde(rename(deserialize = "roleCredits"))]
    pub roles: Vec<Role>,
    #[serde(rename(deserialize = "sourceNames"))]
    pub sources: Vec<String>,
}

#[derive(Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Role {
    #[serde(rename(deserialize = "roleTitle"))]
    pub title: String,
    pub artists: Vec<Credit>,
}

#[derive(Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(default)]
pub struct Credit {
    pub name: String,
    /// Empty for someone with no artist page.
    pub uri: String,
    /// "Composer", "Lyricist", "Lead Vocal"…
    pub subroles: Vec<String>,
}

/// A playlist's songs and header as fetched once, paged through without
/// fetching again.
struct KeptPlaylist {
    items: Vec<(SpotifyUri, Option<i64>)>,
    name: Option<String>,
    description: Option<String>,
    images: Vec<Image>,
}

pub struct Reads {
    session: Session,
    pathfinder: Pathfinder,
    /// Most recently read last.
    lists: Mutex<VecDeque<(String, Arc<KeptPlaylist>)>>,
    known: Mutex<HashMap<String, Track>>,
}

impl Reads {
    pub fn new(session: Session) -> Self {
        let pathfinder = Pathfinder::new(session.clone());
        Self {
            session,
            pathfinder,
            lists: Mutex::default(),
            known: Mutex::default(),
        }
    }

    pub async fn new_releases(&self, force: bool) -> Result<Vec<ReleaseAlbum>, Error> {
        self.pathfinder.new_releases(force).await
    }

    pub async fn made_for_you(&self, timezone: &str, force: bool) -> Result<HomeShelves, Error> {
        self.pathfinder.made_for_you(timezone, force).await
    }

    /// One page of a playlist's songs. The first page fetches the list afresh.
    pub async fn playlist(&self, id: &str, offset: usize) -> Result<PlaylistPage, Error> {
        let kept = match self.kept(id).filter(|_| offset > 0) {
            Some(kept) => kept,
            None => self.fetch(id).await?,
        };
        let list = &kept.items;
        let end = (offset + PAGE).min(list.len());
        let page = list.get(offset..end).unwrap_or_default();
        let uris: Vec<SpotifyUri> = page.iter().map(|(uri, _)| uri.clone()).collect();
        let tracks = self.tracks(&uris).await?;
        let rows = page
            .iter()
            .zip(tracks)
            .enumerate()
            .filter_map(|(i, ((_, added), track))| {
                Some(PlaylistRow {
                    index: offset + i,
                    added_at_ms: *added,
                    track: track?,
                })
            })
            .collect();
        Ok(PlaylistPage {
            total: list.len(),
            rows,
            next: (end < list.len()).then_some(end),
            name: (offset == 0).then(|| kept.name.clone()).flatten(),
            description: (offset == 0).then(|| kept.description.clone()).flatten(),
            images: if offset == 0 {
                kept.images.clone()
            } else {
                Vec::new()
            },
        })
    }

    /// An artist's most played songs in the account's country (or
    /// worldwide when Spotify ranks none there): one artist fetch, then one
    /// batched track lookup.
    pub async fn top_tracks(&self, id: &str) -> Result<Vec<Track>, Error> {
        let uri = SpotifyUri::Artist {
            id: SpotifyId::from_base62(id)?,
        };
        let artist = Artist::get(&self.session, &uri).await?;
        let uris = top_track_uris(&artist.top_tracks, &self.session.country());
        Ok(self.tracks(&uris).await?.into_iter().flatten().collect())
    }

    /// A song's credits: one request, made when the listener asks.
    pub async fn credits(&self, id: &str) -> Result<Credits, Error> {
        let id = SpotifyId::from_base62(id)?;
        let endpoint = format!(
            "/track-credits-view/v0/experimental/{}/credits",
            id.to_base62()
        );
        let body = self
            .session
            .spclient()
            .request_as_json(&Method::GET, &endpoint, None, None)
            .await?;
        Ok(serde_json::from_slice(&body)?)
    }

    /// The tracks at `uris`, in order; none where Spotify has no song.
    /// Known tracks are not asked for again; the rest go in one request.
    pub async fn tracks(&self, uris: &[SpotifyUri]) -> Result<Vec<Option<Track>>, Error> {
        let keys: Vec<String> = uris.iter().map(SpotifyUri::to_uri).collect();
        let missing: Vec<&String> = {
            let known = self
                .known
                .lock()
                .map_err(|_| Error::aborted("track cache"))?;
            keys.iter()
                .filter(|key| !known.contains_key(*key))
                .collect()
        };
        if !missing.is_empty() {
            let found = self.look_up(&missing).await?;
            let mut known = self
                .known
                .lock()
                .map_err(|_| Error::aborted("track cache"))?;
            if known.len() + found.len() > REMEMBERED {
                known.clear();
            }
            known.extend(found);
        }
        let known = self
            .known
            .lock()
            .map_err(|_| Error::aborted("track cache"))?;
        Ok(keys.iter().map(|key| known.get(key).cloned()).collect())
    }

    fn kept(&self, id: &str) -> Option<Arc<KeptPlaylist>> {
        let mut lists = self.lists.lock().ok()?;
        let index = lists.iter().position(|(kept, _)| kept == id)?;
        let entry = lists.remove(index)?;
        let list = entry.1.clone();
        lists.push_back(entry);
        Some(list)
    }

    async fn fetch(&self, id: &str) -> Result<Arc<KeptPlaylist>, Error> {
        let uri = SpotifyUri::Playlist {
            id: SpotifyId::from_base62(id)?,
            user: None,
        };
        let playlist = Playlist::get(&self.session, &uri).await?;
        let image_template = self
            .session
            .get_user_attribute("image-url")
            .unwrap_or_else(|| "https://i.scdn.co/image/{file_id}".into());
        let items = playlist
            .contents
            .items
            .iter()
            .filter(|item| matches!(item.id, SpotifyUri::Track { .. }))
            .map(|item| {
                let added = item.attributes.timestamp.as_timestamp_ms();
                (item.id.clone(), (added > 0).then_some(added))
            })
            .collect();
        let name = (!playlist.attributes.name.is_empty()).then(|| playlist.attributes.name.clone());
        let description = (!playlist.attributes.description.is_empty())
            .then(|| playlist.attributes.description.clone());
        let images = playlist_images(&playlist.attributes, &image_template);
        let kept = Arc::new(KeptPlaylist {
            items,
            name,
            description,
            images,
        });
        if let Ok(mut lists) = self.lists.lock() {
            lists.retain(|(kept, _)| kept != id);
            if lists.len() >= KEPT {
                lists.pop_front();
            }
            lists.push_back((id.to_owned(), kept.clone()));
        }
        Ok(kept)
    }

    /// Track metadata for `uris` in one batched request, by URI.
    async fn look_up(&self, uris: &[&String]) -> Result<HashMap<String, Track>, Error> {
        let mut request = BatchedEntityRequest::new();
        for uri in uris.iter().filter(|uri| uri.starts_with("spotify:track:")) {
            request.entity_request.push(EntityRequest {
                entity_uri: (*uri).clone(),
                query: vec![ExtensionQuery {
                    extension_kind: EnumOrUnknown::new(ExtensionKind::TRACK_V4),
                    ..Default::default()
                }],
                ..Default::default()
            });
        }
        if request.entity_request.is_empty() {
            return Ok(HashMap::new());
        }
        let images = self
            .session
            .get_user_attribute("image-url")
            .unwrap_or_else(|| "https://i.scdn.co/image/{file_id}".into());
        let response = self
            .session
            .spclient()
            .get_extended_metadata(request)
            .await?;
        let mut tracks = HashMap::new();
        for array in response.extended_metadata {
            for data in array.extension_data {
                let Some(any) = data.extension_data.as_ref() else {
                    continue;
                };
                let (Ok(message), Ok(uri)) = (
                    TrackMessage::parse_from_bytes(&any.value),
                    SpotifyUri::from_uri(&data.entity_uri),
                ) else {
                    continue;
                };
                if let Ok(track) = SessionTrack::parse(&message, &uri) {
                    tracks.insert(data.entity_uri, Track::from_metadata(&track, &images));
                }
            }
        }
        Ok(tracks)
    }
}

/// The cover, from the sized pictures when the list carries them, else the
/// single raw picture hash on the playlist attributes.
fn playlist_images(attributes: &PlaylistAttributes, template: &str) -> Vec<Image> {
    let sized: Vec<Image> = attributes
        .picture_sizes
        .iter()
        .filter_map(|picture| {
            Some(Image {
                url: resolve_image_url(&picture.url, template)?,
                width: match picture.target_name.as_str() {
                    "small" => Some(60),
                    "default" => Some(300),
                    "large" => Some(640),
                    _ => None,
                },
            })
        })
        .collect();
    if !sized.is_empty() {
        return sized;
    }
    if attributes.picture.is_empty() {
        return Vec::new();
    }
    let mut hex = String::with_capacity(attributes.picture.len() * 2);
    for byte in &attributes.picture {
        use std::fmt::Write;
        let _ = write!(&mut hex, "{byte:02x}");
    }
    vec![Image {
        url: template.replace("{file_id}", &hex),
        width: None,
    }]
}

fn resolve_image_url(reference: &str, template: &str) -> Option<String> {
    if reference.starts_with("https://") {
        return Some(reference.to_owned());
    }
    reference
        .strip_prefix("spotify:image:")
        .filter(|id| !id.is_empty())
        .map(|id| template.replace("{file_id}", id))
}

/// The first songs of the account's country's ranking, or of the worldwide
/// one (`ZZ`; librespot's `for_country` falls back to an empty country,
/// which Spotify does not send). An empty ranking counts as none.
fn top_track_uris(top: &CountryTopTracks, country: &str) -> Vec<SpotifyUri> {
    let ranked = |code: &str| {
        top.iter()
            .find(|ranking| ranking.country == code && !ranking.tracks.is_empty())
    };
    ranked(country)
        .or_else(|| ranked("ZZ"))
        .map(|ranking| ranking.tracks.iter().take(TOP).cloned().collect())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use librespot_metadata::{artist::TopTracks, track::Tracks};

    use super::*;

    fn ranking(country: &str, ids: &[u128]) -> TopTracks {
        TopTracks {
            country: country.into(),
            tracks: Tracks(
                ids.iter()
                    .map(|&id| SpotifyUri::Track {
                        id: SpotifyId { id },
                    })
                    .collect(),
            ),
        }
    }

    #[test]
    fn decodes_credits() {
        let credits: Credits = serde_json::from_str(
            r#"{"trackUri":"spotify:track:x","trackTitle":"Song","roleCredits":[
                {"roleTitle":"Performers","artists":[{"uri":"spotify:artist:a","name":"A",
                  "imageUri":"","subroles":["main artist"],"weight":0.9}]},
                {"roleTitle":"Writers","artists":[{"name":"W","subroles":["Composer","Lyricist"]}]}],
              "extendedCredits":[],"sourceNames":["Label"]}"#,
        )
        .unwrap();
        assert_eq!(credits.roles.len(), 2);
        assert_eq!(credits.roles[0].artists[0].uri, "spotify:artist:a");
        assert_eq!(credits.roles[1].artists[0].uri, "");
        assert_eq!(
            credits.roles[1].artists[0].subroles,
            ["Composer", "Lyricist"]
        );
        assert_eq!(credits.sources, ["Label"]);
        let json = serde_json::to_value(&credits).unwrap();
        assert_eq!(json["roles"][0]["title"], "Performers");
        assert_eq!(json["sources"][0], "Label");
    }

    #[test]
    fn top_tracks_prefer_the_country_then_worldwide() {
        let top = CountryTopTracks(vec![
            ranking("ZZ", &[1, 2]),
            ranking("SE", &[3]),
            ranking("NO", &[]),
        ]);
        assert_eq!(top_track_uris(&top, "SE").len(), 1);
        assert_eq!(top_track_uris(&top, "JP").len(), 2);
        assert_eq!(top_track_uris(&top, "NO").len(), 2);
        assert!(top_track_uris(&CountryTopTracks::default(), "JP").is_empty());
        let many = CountryTopTracks(vec![ranking("ZZ", &(0..15).collect::<Vec<_>>())]);
        assert_eq!(top_track_uris(&many, "JP").len(), TOP);
    }

    #[test]
    fn extracts_playlist_images_from_sizes_or_raw_picture() {
        use librespot_metadata::image::{PictureSize, PictureSizes};

        let template = "https://i.scdn.co/image/{file_id}";
        let mut attributes = PlaylistAttributes {
            name: String::new(),
            description: String::new(),
            picture: vec![0xab, 0xcd],
            is_collaborative: false,
            pl3_version: String::new(),
            is_deleted_by_owner: false,
            client_id: String::new(),
            format: String::new(),
            format_attributes: Default::default(),
            picture_sizes: PictureSizes(vec![
                PictureSize {
                    target_name: "small".into(),
                    url: "spotify:image:1122".into(),
                },
                PictureSize {
                    target_name: "large".into(),
                    url: "https://image-cdn.spotifycdn.com/cover".into(),
                },
            ]),
        };
        let sized = playlist_images(&attributes, template);
        assert_eq!(
            sized,
            vec![
                Image {
                    url: "https://i.scdn.co/image/1122".into(),
                    width: Some(60)
                },
                Image {
                    url: "https://image-cdn.spotifycdn.com/cover".into(),
                    width: Some(640)
                },
            ]
        );

        attributes.picture_sizes = PictureSizes::default();
        assert_eq!(
            playlist_images(&attributes, template),
            vec![Image {
                url: "https://i.scdn.co/image/abcd".into(),
                width: None
            }]
        );

        attributes.picture.clear();
        assert!(playlist_images(&attributes, template).is_empty());
    }
}
