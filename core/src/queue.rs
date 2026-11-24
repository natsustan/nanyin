//! What plays next: Spirc reports the queue as bare URIs; this resolves
//! them to tracks through the session's batched, cached lookup and reports
//! the result once per change.

use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

use librespot_core::SpotifyUri;
use librespot_playback::player::QueueTrack;

use crate::{events::Event, reads::Reads};

/// About a screenful of upcoming tracks; the rest resolve as the queue moves.
const SHOWN: usize = 20;

pub struct QueueResolver {
    reads: Arc<Reads>,
    latest: Arc<AtomicU64>,
}

impl QueueResolver {
    pub fn new(reads: Arc<Reads>) -> Self {
        Self {
            reads,
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
        let (reads, latest) = (self.reads.clone(), self.latest.clone());
        let entries: Vec<(SpotifyUri, bool)> = next
            .iter()
            .filter_map(|track| {
                let uri = SpotifyUri::from_uri(&track.uri).ok()?;
                uri.is_playable().then(|| (uri, track.provider == "queue"))
            })
            .take(SHOWN)
            .collect();
        let uris: Vec<SpotifyUri> = entries.iter().map(|(uri, _)| uri.clone()).collect();
        tokio::spawn(async move {
            let Ok(tracks) = reads.tracks(&uris).await else {
                return;
            };
            if latest.load(Ordering::SeqCst) == generation {
                let mut resolved = Vec::with_capacity(entries.len());
                let mut manual_count = 0usize;
                for ((_, is_manual), track) in entries.into_iter().zip(tracks) {
                    if let Some(track) = track {
                        if is_manual && resolved.len() == manual_count {
                            manual_count += 1;
                        }
                        resolved.push(track);
                    }
                }
                emit(Event::Queue {
                    context_uri,
                    tracks: resolved,
                    manual_count,
                });
            }
        });
    }
}
