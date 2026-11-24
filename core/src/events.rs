//! Events sent to Swift as JSON, one object per callback.

use librespot_metadata::audio::{AudioItem, UniqueFields};
use librespot_playback::player::PlayerEvent;
use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Serialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    /// The session is up and this device is announced on Spotify Connect.
    /// `credentials` is librespot's reusable credential as JSON, for the app
    /// to keep in the Keychain and pass back on the next connect.
    Connected {
        username: String,
        credentials: Option<String>,
    },
    ConnectFailed {
        reason: FailureReason,
        message: String,
    },
    /// The Spirc task ended on its own: the session is gone. `resuming`:
    /// the song plays on and the next session picks it up, with its queue.
    SessionEnded {
        resuming: bool,
    },
    /// Another device took over playback.
    Deactivated,
    /// The next session could not pick up the song a dropped one left
    /// playing; it has stopped.
    ResumeFailed,
    TrackChanged {
        track: Track,
    },
    Loading {
        uri: String,
        position_ms: u32,
    },
    Playing {
        uri: String,
        position_ms: u32,
    },
    /// A seek or position correction without changing playing/paused state.
    Position {
        uri: String,
        position_ms: u32,
    },
    Paused {
        uri: String,
        position_ms: u32,
    },
    Stopped,
    Unavailable {
        uri: String,
    },
    Volume {
        volume: u16,
    },
    Shuffle {
        on: bool,
    },
    Repeat {
        context: bool,
        track: bool,
    },
    /// The tracks after the current one, in play order.
    Queue {
        context_uri: String,
        tracks: Vec<Track>,
        manual_count: usize,
    },
    /// The answer to request `request`: `ok` or `error`.
    Reply {
        request: u64,
        #[serde(skip_serializing_if = "Option::is_none")]
        ok: Option<Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<String>,
    },
}

#[derive(Debug, Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FailureReason {
    /// Spotify refused the credential itself. Only this asks for a new grant.
    AuthRejected,
    /// The session signed in as a different account than the app expected.
    AccountMismatch,
    Timeout,
    Other,
}

#[derive(Debug, Serialize, PartialEq, Clone)]
pub struct Track {
    pub uri: String,
    pub name: String,
    pub artists: Vec<Artist>,
    pub album: String,
    /// None for episodes and local files.
    pub album_uri: Option<String>,
    pub cover_url: Option<String>,
    pub duration_ms: u32,
    pub explicit: bool,
}

#[derive(Debug, Serialize, PartialEq, Clone)]
pub struct Artist {
    pub uri: String,
    pub name: String,
}

impl Track {
    pub fn from_item(item: &AudioItem) -> Self {
        let (artists, album, album_uri) = match &item.unique_fields {
            UniqueFields::Track {
                artists,
                album,
                album_id,
                ..
            } => (
                artists
                    .0
                    .iter()
                    .map(|artist| Artist {
                        uri: artist.id.to_uri(),
                        name: artist.name.clone(),
                    })
                    .collect(),
                album.clone(),
                Some(album_id.to_uri()),
            ),
            UniqueFields::Episode { show_name, .. } => (Vec::new(), show_name.clone(), None),
            UniqueFields::Local { artists, album, .. } => (
                artists
                    .iter()
                    .map(|name| Artist {
                        uri: String::new(),
                        name: name.clone(),
                    })
                    .collect(),
                album.clone().unwrap_or_default(),
                None,
            ),
        };
        let cover_url = item
            .covers
            .iter()
            .max_by_key(|cover| cover.width)
            .map(|cover| cover.url.clone());
        Self {
            uri: item.uri.clone(),
            name: item.name.clone(),
            artists,
            album,
            album_uri,
            cover_url,
            duration_ms: item.duration_ms,
            explicit: item.is_explicit,
        }
    }

    /// A track read from Spotify's metadata, outside playback. `images` is
    /// the session's image address template, with `{file_id}` to fill.
    pub fn from_metadata(track: &librespot_metadata::Track, images: &str) -> Self {
        Self {
            uri: track.id.to_uri(),
            name: track.name.clone(),
            artists: track
                .artists
                .iter()
                .map(|artist| Artist {
                    uri: artist.id.to_uri(),
                    name: artist.name.clone(),
                })
                .collect(),
            album: track.album.name.clone(),
            album_uri: Some(track.album.id.to_uri()),
            cover_url: track
                .album
                .covers
                .iter()
                .max_by_key(|cover| cover.width)
                .map(|cover| images.replace("{file_id}", &cover.id.to_base16())),
            duration_ms: u32::try_from(track.duration).unwrap_or_default(),
            explicit: track.is_explicit,
        }
    }
}

impl Event {
    /// The Swift-facing form of a player event, or `None` for events only
    /// Spirc needs.
    pub fn from_player(event: PlayerEvent) -> Option<Self> {
        use PlayerEvent as P;
        Some(match event {
            P::TrackChanged { audio_item } => Self::TrackChanged {
                track: Track::from_item(&audio_item),
            },
            P::Loading {
                track_id,
                position_ms,
                ..
            } => Self::Loading {
                uri: track_id.to_uri(),
                position_ms,
            },
            P::Playing {
                track_id,
                position_ms,
                ..
            } => Self::Playing {
                uri: track_id.to_uri(),
                position_ms,
            },
            P::Seeked {
                track_id,
                position_ms,
                ..
            }
            | P::PositionCorrection {
                track_id,
                position_ms,
                ..
            } => Self::Position {
                uri: track_id.to_uri(),
                position_ms,
            },
            P::Paused {
                track_id,
                position_ms,
                ..
            } => Self::Paused {
                uri: track_id.to_uri(),
                position_ms,
            },
            P::Stopped { .. } => Self::Stopped,
            P::Unavailable { track_id, .. } => Self::Unavailable {
                uri: track_id.to_uri(),
            },
            P::VolumeChanged { volume } => Self::Volume { volume },
            P::ShuffleChanged { shuffle } => Self::Shuffle { on: shuffle },
            P::RepeatChanged { context, track } => Self::Repeat { context, track },
            P::SessionDisconnected { .. } => Self::Deactivated,
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn events_serialize_with_a_type_tag() {
        let json = serde_json::to_string(&Event::Playing {
            uri: "spotify:track:x".into(),
            position_ms: 5,
        })
        .unwrap();
        assert_eq!(
            json,
            r#"{"type":"playing","uri":"spotify:track:x","position_ms":5}"#
        );
        let json = serde_json::to_string(&Event::Position {
            uri: "spotify:track:x".into(),
            position_ms: 42,
        })
        .unwrap();
        assert_eq!(
            json,
            r#"{"type":"position","uri":"spotify:track:x","position_ms":42}"#
        );
        let json = serde_json::to_string(&Event::ConnectFailed {
            reason: FailureReason::AuthRejected,
            message: "no".into(),
        })
        .unwrap();
        assert_eq!(
            json,
            r#"{"type":"connect_failed","reason":"auth_rejected","message":"no"}"#
        );
    }
}
