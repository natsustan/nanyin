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

use futures_util::{StreamExt, stream};
use librespot_core::{Session, SpotifyUri};
use librespot_metadata::audio::AudioItem;
use librespot_playback::player::QueueTrack;

use crate::events::{Event, Track};

/// About a screenful of upcoming tracks; the rest resolve as the queue moves.
const SHOWN: usize = 20;
/// Lookups in flight at once.
const PARALLEL: usize = 4;
/// Tracks remembered; past this the memory starts over.
const REMEMBERED: usize = 500;

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
        let current = move |this: &Self| this.latest.load(Ordering::SeqCst) == generation;
        let this = self.clone();
        let uris: Vec<SpotifyUri> = next
            .iter()
            .filter_map(|track| SpotifyUri::from_uri(&track.uri).ok())
            .filter(SpotifyUri::is_playable)
            .take(SHOWN)
            .collect();
        tokio::spawn(async move {
            let tracks: Vec<Track> = stream::iter(uris)
                .map(|uri| this.resolve(uri, current))
                .buffered(PARALLEL)
                .filter_map(|track| async { track })
                .collect()
                .await;
            if current(&this) {
                emit(Event::Queue {
                    context_uri,
                    tracks,
                });
            }
        });
    }

    /// The track at `uri`, unless the queue it was asked for is already stale.
    async fn resolve(&self, uri: SpotifyUri, current: impl Fn(&Self) -> bool) -> Option<Track> {
        let key = uri.to_uri();
        if let Some(track) = self.known.lock().ok()?.get(&key) {
            return Some(track.clone());
        }
        if !current(self) {
            return None;
        }
        let track = Track::from_item(&AudioItem::get_file(&self.session, uri).await.ok()?);
        let mut known = self.known.lock().ok()?;
        if known.len() >= REMEMBERED {
            known.clear();
        }
        known.insert(key, track.clone());
        Some(track)
    }
}
