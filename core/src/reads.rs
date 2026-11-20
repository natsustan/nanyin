//! Catalogue reads over the streaming session, for what the app's Web API
//! grant cannot read: since late 2024, Development Mode apps get no access
//! to playlists the listener does not own. The session speaks the protocol
//! Spotify's own clients use, as spotifast does.

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

#[derive(Debug, Serialize, PartialEq)]
pub struct PlaylistPage {
    pub name: String,
    /// The songs in the whole list; episodes and local files are not shown.
    pub total: usize,
    pub rows: Vec<PlaylistRow>,
    /// The offset of the next page, or none at the end.
    pub next: Option<usize>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct PlaylistRow {
    /// Position in the whole list; rows Spotify no longer has are left out.
    pub index: usize,
    pub added_at_ms: Option<i64>,
    pub track: Track,
}

/// A playlist's rows as fetched once, paged through without fetching again.
struct List {
    name: String,
    rows: Vec<(SpotifyUri, Option<i64>)>,
    songs: usize,
}

pub struct Reads {
    session: Session,
    /// Most recently read last.
    lists: Mutex<VecDeque<(String, Arc<List>)>>,
}

impl Reads {
    pub fn new(session: Session) -> Self {
        Self {
            session,
            lists: Mutex::default(),
        }
    }

    /// One page of a playlist. The first page fetches the list afresh.
    pub async fn playlist(&self, id: &str, offset: usize) -> Result<PlaylistPage, Error> {
        let list = match self.kept(id).filter(|_| offset > 0) {
            Some(list) => list,
            None => self.fetch(id).await?,
        };
        let end = (offset + PAGE).min(list.rows.len());
        let page = list.rows.get(offset..end).unwrap_or_default();
        let tracks = self.tracks(page.iter().map(|(uri, _)| uri)).await?;
        let rows = page
            .iter()
            .enumerate()
            .filter_map(|(i, (uri, added))| {
                Some(PlaylistRow {
                    index: offset + i,
                    added_at_ms: *added,
                    track: tracks.get(&uri.to_uri())?.clone(),
                })
            })
            .collect();
        Ok(PlaylistPage {
            name: list.name.clone(),
            total: list.songs,
            rows,
            next: (end < list.rows.len()).then_some(end),
        })
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
        let rows: Vec<_> = playlist
            .contents
            .items
            .iter()
            .map(|item| {
                let added = item.attributes.timestamp.as_timestamp_ms();
                (item.id.clone(), (added > 0).then_some(added))
            })
            .collect();
        let list = Arc::new(List {
            name: playlist.attributes.name.clone(),
            songs: rows
                .iter()
                .filter(|(uri, _)| matches!(uri, SpotifyUri::Track { .. }))
                .count(),
            rows,
        });
        if let Ok(mut lists) = self.lists.lock() {
            lists.retain(|(kept, _)| kept != id);
            if lists.len() >= KEPT {
                lists.pop_front();
            }
            lists.push_back((id.to_owned(), list.clone()));
        }
        Ok(list)
    }

    /// The tracks among `uris`, by URI, in one batched request. Episodes,
    /// local files and songs Spotify no longer has are absent.
    async fn tracks(
        &self,
        uris: impl Iterator<Item = &SpotifyUri>,
    ) -> Result<HashMap<String, Track>, Error> {
        let mut request = BatchedEntityRequest::new();
        for uri in uris.filter(|uri| matches!(uri, SpotifyUri::Track { .. })) {
            request.entity_request.push(EntityRequest {
                entity_uri: uri.to_uri(),
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
                    tracks.insert(data.entity_uri, Track::from_metadata(&track));
                }
            }
        }
        Ok(tracks)
    }
}
