//! Catalogue reads over the streaming session, for what the app's Web API
//! grant cannot read: since late 2024, Development Mode apps get no access
//! to playlists the listener does not own. The session speaks the protocol
//! Spotify's own clients use, as spotifast does. Also resolves the play
//! queue's tracks, so both go through one batched, cached lookup.

use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
};

use librespot_core::{Error, Session, SpotifyUri, spotify_id::SpotifyId};
use librespot_metadata::{Metadata, Playlist, Track as SessionTrack};
use librespot_protocol::{
    extended_metadata::{BatchedEntityRequest, EntityRequest, ExtensionQuery},
    extension_kind::ExtensionKind,
    metadata::Track as TrackMessage,
};
use protobuf::{EnumOrUnknown, Message};
use serde::Serialize;

use crate::events::Track;

/// Rows per page, as the Web API's limit.
const PAGE: usize = 50;
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
}

#[derive(Debug, Serialize, PartialEq)]
pub struct PlaylistRow {
    /// Position among the list's songs; a song Spotify no longer has is
    /// left out.
    pub index: usize,
    pub added_at_ms: Option<i64>,
    pub track: Track,
}

/// A playlist's songs as fetched once, paged through without fetching again.
type List = Vec<(SpotifyUri, Option<i64>)>;

pub struct Reads {
    session: Session,
    /// Most recently read last.
    lists: Mutex<VecDeque<(String, Arc<List>)>>,
    known: Mutex<HashMap<String, Track>>,
}

impl Reads {
    pub fn new(session: Session) -> Self {
        Self {
            session,
            lists: Mutex::default(),
            known: Mutex::default(),
        }
    }

    /// One page of a playlist's songs. The first page fetches the list afresh.
    pub async fn playlist(&self, id: &str, offset: usize) -> Result<PlaylistPage, Error> {
        let list = match self.kept(id).filter(|_| offset > 0) {
            Some(list) => list,
            None => self.fetch(id).await?,
        };
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
        })
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

    fn kept(&self, id: &str) -> Option<Arc<List>> {
        let mut lists = self.lists.lock().ok()?;
        let index = lists.iter().position(|(kept, _)| kept == id)?;
        let entry = lists.remove(index)?;
        let list = entry.1.clone();
        lists.push_back(entry);
        Some(list)
    }

    async fn fetch(&self, id: &str) -> Result<Arc<List>, Error> {
        let uri = SpotifyUri::Playlist {
            id: SpotifyId::from_base62(id)?,
            user: None,
        };
        let playlist = Playlist::get(&self.session, &uri).await?;
        let list: Arc<List> = Arc::new(
            playlist
                .contents
                .items
                .iter()
                .filter(|item| matches!(item.id, SpotifyUri::Track { .. }))
                .map(|item| {
                    let added = item.attributes.timestamp.as_timestamp_ms();
                    (item.id.clone(), (added > 0).then_some(added))
                })
                .collect(),
        );
        if let Ok(mut lists) = self.lists.lock() {
            lists.retain(|(kept, _)| kept != id);
            if lists.len() >= KEPT {
                lists.pop_front();
            }
            lists.push_back((id.to_owned(), list.clone()));
        }
        Ok(list)
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
