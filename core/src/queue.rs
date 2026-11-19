//! What plays next: Spirc reports the queue as bare URIs, this resolves
//! them to tracks through the session (no Web API traffic) and reports the
//! result once per change.

use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use librespot_core::{Session, SpotifyUri};
use librespot_metadata::audio::AudioItem;
use librespot_playback::player::QueueTrack;
use serde::Serialize;

use crate::events::{Event, Track};

/// Enough for a page of upcoming tracks; the rest resolve as the queue moves.
const SHOWN: usize = 30;

#[derive(Debug, Serialize, PartialEq, Clone)]
pub struct QueuedTrack {
    #[serde(flatten)]
    pub track: Track,
    /// Added with "Add to Queue", rather than coming from the context.
    pub queued: bool,
}

#[derive(Clone)]
pub struct QueueResolver {
    session: Session,
    /// Tracks seen before, so a moving queue costs one lookup per new track.
    known: Arc<Mutex<HashMap<String, Track>>>,
    latest: Arc<AtomicU64>,
}

impl QueueResolver {
    pub fn new(session: Session) -> Self {
        Self {
            session,
            known: Arc::default(),
            latest: Arc::default(),
        }
    }

    /// Resolves `next` in the background and emits it, unless a newer queue
    /// arrives first.
    pub fn update(
        &self,
        context_uri: String,
        next: Vec<QueueTrack>,
        emit: impl Fn(Event) + Send + 'static,
    ) {
        let generation = self.latest.fetch_add(1, Ordering::SeqCst) + 1;
        let this = self.clone();
        tokio::spawn(async move {
            let mut tracks = Vec::new();
            for entry in next
                .into_iter()
                .filter(|t| is_playable_uri(&t.uri))
                .take(SHOWN)
            {
                if this.latest.load(Ordering::SeqCst) != generation {
                    return;
                }
                if let Some(track) = this.resolve(&entry.uri).await {
                    tracks.push(QueuedTrack {
                        track,
                        queued: entry.provider == "queue",
                    });
                }
            }
            if this.latest.load(Ordering::SeqCst) == generation {
                emit(Event::Queue {
                    context_uri,
                    tracks,
                });
            }
        });
    }

    async fn resolve(&self, uri: &str) -> Option<Track> {
        if let Some(track) = self.known.lock().ok()?.get(uri) {
            return Some(track.clone());
        }
        let item = AudioItem::get_file(&self.session, SpotifyUri::from_uri(uri).ok()?)
            .await
            .ok()?;
        let track = Track::from_item(&item);
        self.known
            .lock()
            .ok()?
            .insert(uri.to_owned(), track.clone());
        Some(track)
    }
}

/// Skips the delimiters and placeholders Spirc keeps in the list.
fn is_playable_uri(uri: &str) -> bool {
    uri.starts_with("spotify:track:") || uri.starts_with("spotify:episode:")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn queued_tracks_serialize_flat() {
        let event = Event::Queue {
            context_uri: "spotify:album:a".into(),
            tracks: vec![QueuedTrack {
                track: Track {
                    uri: "spotify:track:t".into(),
                    name: "T".into(),
                    artists: Vec::new(),
                    album: "A".into(),
                    cover_url: None,
                    duration_ms: 1,
                    explicit: false,
                },
                queued: true,
            }],
        };
        assert_eq!(
            serde_json::to_string(&event).unwrap(),
            r#"{"type":"queue","context_uri":"spotify:album:a","tracks":[{"uri":"spotify:track:t","name":"T","artists":[],"album":"A","cover_url":null,"duration_ms":1,"explicit":false,"queued":true}]}"#
        );
    }

    #[test]
    fn delimiters_are_skipped() {
        assert!(is_playable_uri("spotify:track:x"));
        assert!(!is_playable_uri("spotify:delimiter"));
    }
}
