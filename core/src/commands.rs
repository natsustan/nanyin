//! Commands from Swift, decoded from JSON and applied to Spirc.

use librespot_connect::{
    LoadContextOptions, LoadRequest, LoadRequestOptions, Options, PlayingTrack, Spirc,
};
use librespot_core::{Error, SpotifyUri};
use serde::Deserialize;

use crate::{engine::Engine, events::Event};

#[derive(Debug, Deserialize, PartialEq)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Command {
    Play,
    Pause,
    PlayPause,
    Next,
    Previous,
    Seek {
        position_ms: u32,
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
    AddToQueue {
        uri: String,
    },
    /// Start playing a context (playlist, album, artist, Liked Songs) or an
    /// explicit list of tracks. Large lists belong in a context: Spotify
    /// resolves it server-side instead of this device uploading every URI.
    Load(Load),
    /// Reads a page of a playlist through the session; the answer arrives
    /// as a `playlist_page` or `read_failed` event with the same `request`.
    ReadPlaylist {
        request: u64,
        id: String,
        offset: usize,
    },
}

#[derive(Debug, Deserialize, PartialEq, Default)]
#[serde(default)]
pub struct Load {
    pub context_uri: Option<String>,
    pub track_uris: Vec<String>,
    /// The track to start at, by URI (preferred) or index.
    pub start_uri: Option<String>,
    pub start_index: Option<u32>,
    pub position_ms: u32,
    pub shuffle: Option<bool>,
}

impl Load {
    fn request(self) -> LoadRequest {
        let playing_track = self
            .start_uri
            .map(PlayingTrack::Uri)
            .or(self.start_index.map(PlayingTrack::Index));
        let context_options = self.shuffle.map(|shuffle| {
            LoadContextOptions::Options(Options {
                shuffle,
                ..Options::default()
            })
        });
        let options = LoadRequestOptions {
            start_playing: true,
            seek_to: self.position_ms,
            context_options,
            playing_track,
        };
        match self.context_uri {
            Some(uri) => LoadRequest::from_context_uri(uri, options),
            None => LoadRequest::from_tracks(self.track_uris, options),
        }
    }
}

impl Command {
    pub fn apply(self, engine: &Engine) -> Result<(), Error> {
        let spirc: &Spirc = &engine.spirc;
        match self {
            Self::Play => spirc.play(),
            Self::Pause => spirc.pause(),
            Self::PlayPause => spirc.play_pause(),
            Self::Next => spirc.next(),
            Self::Previous => spirc.prev(),
            Self::Seek { position_ms } => spirc.set_position_ms(position_ms),
            Self::Volume { volume } => spirc.set_volume(volume),
            Self::Shuffle { on } => spirc.shuffle(on),
            Self::Repeat { context, track } => {
                spirc.repeat(context)?;
                spirc.repeat_track(track)
            }
            Self::AddToQueue { uri } => spirc.add_to_queue(SpotifyUri::from_uri(&uri)?),
            Self::Load(load) => {
                // Commands are ignored while this device is not the active
                // one; activating while already active is a no-op.
                spirc.activate()?;
                spirc.load(load.request())
            }
            Self::ReadPlaylist {
                request,
                id,
                offset,
            } => {
                let (reads, emit) = (engine.reads.clone(), engine.emit.clone());
                engine.runtime.spawn(async move {
                    emit(match reads.playlist(&id, offset).await {
                        Ok(page) => Event::PlaylistPage { request, page },
                        Err(error) => Event::ReadFailed {
                            request,
                            message: error.to_string(),
                        },
                    });
                });
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_commands() {
        let cmd: Command = serde_json::from_str(r#"{"cmd":"seek","position_ms":1200}"#).unwrap();
        assert_eq!(cmd, Command::Seek { position_ms: 1200 });
        let cmd: Command = serde_json::from_str(
            r#"{"cmd":"load","context_uri":"spotify:playlist:abc","start_uri":"spotify:track:x"}"#,
        )
        .unwrap();
        assert_eq!(
            cmd,
            Command::Load(Load {
                context_uri: Some("spotify:playlist:abc".into()),
                start_uri: Some("spotify:track:x".into()),
                ..Load::default()
            })
        );
        let cmd: Command =
            serde_json::from_str(r#"{"cmd":"read_playlist","request":7,"id":"abc","offset":50}"#)
                .unwrap();
        assert_eq!(
            cmd,
            Command::ReadPlaylist {
                request: 7,
                id: "abc".into(),
                offset: 50
            }
        );
    }
}
