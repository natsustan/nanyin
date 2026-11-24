//! Commands from Swift, decoded from JSON and applied to Spirc.

use librespot_connect::{
    LoadContextOptions, LoadRequest, LoadRequestOptions, Options, PlayingTrack, Spirc,
};
use librespot_core::{Error, SpotifyUri};
use serde::Deserialize;

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
    /// Clears manually queued tracks while keeping context tracks.
    ClearQueue,
    /// Takes over active Spotify Connect playback onto this Mac.
    Transfer,
    /// Start playing a context (playlist, album, artist, Liked Songs) or an
    /// explicit list of tracks. Large lists belong in a context: Spotify
    /// resolves it server-side instead of this device uploading every URI.
    Load(Load),
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
    pub fn apply(self, spirc: &Spirc) -> Result<(), Error> {
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
            Self::ClearQueue => spirc.clear_queue(),
            Self::Transfer => spirc.transfer(None),
            Self::Load(load) => {
                // Commands are ignored while this device is not the active
                // one; activating while already active is a no-op.
                spirc.activate()?;
                spirc.load(load.request())
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
        assert_eq!(
            serde_json::from_str::<Command>(r#"{"cmd":"clear_queue"}"#).unwrap(),
            Command::ClearQueue
        );
        assert_eq!(
            serde_json::from_str::<Command>(r#"{"cmd":"transfer"}"#).unwrap(),
            Command::Transfer
        );
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
    }
}
