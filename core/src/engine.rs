//! One playback engine: a librespot session, its player and its Spotify
//! Connect device. The FFI layer in `lib.rs` keeps at most one alive.

use std::{
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use librespot_connect::{ConnectConfig, PlaybackSnapshot, RestoreOutcome, Spirc};
use librespot_core::{
    Error, Session, SessionConfig, SpotifyUri, authentication::Credentials, cache::Cache,
    config::DeviceType, error::ErrorKind,
};
use librespot_playback::{
    audio_backend,
    config::{AudioFormat, Bitrate, PlayerConfig, VolumeCtrl},
    mixer::{self, Mixer, MixerConfig},
    player::{Player, PlayerEvent},
};
use serde::Deserialize;

use crate::{
    events::{Event, FailureReason, Track},
    queue::QueueResolver,
    reads::Reads,
};

pub type Emit = Arc<dyn Fn(Event) + Send + Sync>;

/// How long the access-point handshake and Connect registration may take
/// before the attempt is abandoned. Never retried here: Swift decides.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Debug, Deserialize)]
pub struct Config {
    /// Stable per install. A new id per launch registers a new Connect device
    /// every time, which piles up ghost devices on the account.
    pub device_id: String,
    pub device_name: String,
    pub initial_volume: u16,
    pub credentials: CredentialsInput,
    /// The account the Web API grant belongs to. The session must sign in as
    /// the same account, or it is closed before it plays anything.
    pub expected_username: Option<String>,
    pub audio_cache_dir: Option<PathBuf>,
    pub audio_cache_limit: Option<u64>,
    /// Optional HTTP proxy URL without credentials (e.g. `http://127.0.0.1:7890`).
    #[serde(default)]
    pub proxy: Option<String>,
    /// Audio bitrate in kbps (`96`, `160`, or `320`; defaults to `320`).
    #[serde(default)]
    pub bitrate: Option<u16>,
    /// Whether loudness normalization is enabled on the player.
    #[serde(default)]
    pub normalisation: bool,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum CredentialsInput {
    /// A fresh playback OAuth token, used once to obtain a reusable credential.
    AccessToken { token: String },
    /// librespot's reusable credential, exactly as `Event::Connected` gave it.
    Stored { json: String },
}

impl CredentialsInput {
    fn into_credentials(self) -> Result<Credentials, Error> {
        match self {
            Self::AccessToken { token } => Ok(Credentials::with_access_token(token)),
            Self::Stored { json } => {
                serde_json::from_str(&json).map_err(|e| Error::invalid_argument(e.to_string()))
            }
        }
    }
}

pub struct Engine {
    pub spirc: Spirc,
    pub session: Session,
    pub reads: Arc<Reads>,
    pub emit: Emit,
    deck: Deck,
}

/// What outlives a session: the player, still playing what it has fetched,
/// its mixer, and the loop forwarding its events. librespot's player does
/// not stop when its session drops; it stops when the last handle goes.
#[derive(Clone)]
pub struct Deck {
    player: Arc<Player>,
    mixer: Arc<dyn Mixer>,
    route: Arc<Mutex<Route>>,
    now: Arc<Mutex<Now>>,
}

/// The session the player's events are judged against, its metadata cache,
/// and the queue resolver reading through it; swapped when a new session takes over.
struct Route {
    session: Session,
    reads: Arc<Reads>,
    queue: QueueResolver,
}

/// A dropped session's playback, kept for the next session to take over:
/// the deck playing on, and librespot's snapshot of context and queue.
#[derive(Clone)]
pub struct Carried {
    deck: Deck,
    snapshot: Arc<PlaybackSnapshot>,
    username: String,
}

impl Carried {
    /// Applies what the player can do on its own while no session is up:
    /// play, pause, seek and volume. Returns false for anything else.
    pub fn command(&self, command: &crate::commands::Command) -> bool {
        use crate::commands::Command as C;
        let player = &self.deck.player;
        match *command {
            C::Play => player.play(),
            C::Pause => player.pause(),
            C::PlayPause => match self.deck.lock_now().phase {
                Phase::Paused => player.play(),
                Phase::Playing | Phase::Loading => player.pause(),
                Phase::Stopped | Phase::Ended => return false,
            },
            C::Seek { position_ms } => player.seek(position_ms),
            C::Volume { volume } => self.deck.mixer.set_volume(volume),
            _ => return false,
        }
        true
    }

    /// Stops the song; see [`Deck::retire`].
    pub fn retire(self) {
        self.deck.retire();
    }
}

#[derive(Debug)]
pub struct Failure {
    pub reason: FailureReason,
    pub message: String,
}

impl Failure {
    fn other(message: impl Into<String>) -> Self {
        Self {
            reason: FailureReason::Other,
            message: message.into(),
        }
    }
}

impl From<Failure> for Event {
    fn from(failure: Failure) -> Self {
        Event::ConnectFailed {
            reason: failure.reason,
            message: failure.message,
        }
    }
}

impl From<Error> for Failure {
    fn from(error: Error) -> Self {
        Self {
            reason: classify(&error),
            message: error.to_string(),
        }
    }
}

/// Only an access point's explicit login refusal counts as a rejected
/// credential. Other permission errors (a client-token 403, say) are not a
/// reason to throw the grant away.
fn classify(error: &Error) -> FailureReason {
    let message = error.error.to_string();
    if error.kind == ErrorKind::PermissionDenied && message.starts_with("Login failed") {
        FailureReason::AuthRejected
    } else if error.kind == ErrorKind::DeadlineExceeded {
        FailureReason::Timeout
    } else {
        FailureReason::Other
    }
}

/// Runs one engine from connecting to the end of its session.
///
/// `install` is offered the connected engine and hands it back when it has
/// been superseded meanwhile; it is then shut down without reporting
/// anything. `uninstall` runs when the session ends and
/// says whether this engine was still the current one.
///
/// `carried` is a dropped session's playback for this one to take over; the
/// caller keeps its own handle, so a failed connect leaves the song playing
/// for the next attempt. `park` keeps a session's playback when it drops,
/// or hands it back when it can no longer be kept (a newer connect or a
/// disconnect came meanwhile).
pub async fn run(
    config: Config,
    emit: impl Fn(Event) + Clone + Send + Sync + 'static,
    player_emit: Emit,
    carried: Option<Carried>,
    install: impl FnOnce(Engine) -> Option<Engine>,
    uninstall: impl FnOnce() -> Option<Engine>,
    park: impl FnOnce(Carried) -> Option<Carried>,
) {
    let started = tokio::time::timeout(
        CONNECT_TIMEOUT,
        Engine::start(config, emit.clone(), player_emit, carried),
    )
    .await
    .unwrap_or_else(|_| {
        Err(Failure {
            reason: FailureReason::Timeout,
            message: "Spotify did not answer in time".into(),
        })
    });
    let (engine, task) = match started {
        Ok(started) => started,
        Err(failure) => return emit(failure.into()),
    };
    let connected = Event::Connected {
        username: engine.session.username(),
        credentials: engine.credentials_json(),
    };
    if let Some(stale) = install(engine) {
        stale.shutdown();
        task.await;
        return;
    }
    emit(connected);
    task.await;
    let Some(engine) = uninstall() else {
        return;
    };
    // Still current, so the session ended on its own. Spirc kept a
    // snapshot if this device was playing or paused; the deck plays on
    // until the next session takes it over.
    let carried = engine
        .spirc
        .disconnected_playback()
        .map(|snapshot| Carried {
            deck: engine.deck.clone(),
            snapshot,
            username: engine.session.username(),
        });
    let resuming = match carried.map(park) {
        Some(None) => true,
        Some(Some(superseded)) => {
            superseded.retire();
            false
        }
        None => {
            engine.deck.retire();
            false
        }
    };
    log::info!("session ended; resuming: {resuming}");
    emit(Event::SessionEnded { resuming });
}

impl Engine {
    /// Connects, registers the Connect device and returns the Spirc task for
    /// the caller to run. The player is `carried`'s, taken over, or a new
    /// one whose events go to `player_emit` for as long as it lives.
    pub async fn start(
        config: Config,
        emit: impl Fn(Event) + Send + Sync + 'static,
        player_emit: Emit,
        carried: Option<Carried>,
    ) -> Result<(Self, impl Future<Output = ()> + Send + 'static), Failure> {
        let credentials = config.credentials.into_credentials()?;
        let proxy = parse_proxy(config.proxy.as_deref())?;
        let session_config = SessionConfig {
            device_id: config.device_id,
            proxy,
            ..SessionConfig::default()
        };
        // Credentials stay in memory: Swift persists them in the Keychain.
        let cache = Cache::new(
            None,
            None,
            config.audio_cache_dir.as_deref(),
            config.audio_cache_limit,
        )?
        .with_memory_credentials();
        let session = Session::new(session_config, Some(cache));

        let emit: Emit = Arc::new(emit);
        let reads = Arc::new(Reads::new(session.clone()));
        let route = || Route {
            session: session.clone(),
            reads: reads.clone(),
            queue: QueueResolver::new(reads.clone()),
        };
        let bitrate = parse_bitrate(config.bitrate);
        let deck = match &carried {
            Some(carried) => carried.deck.clone(),
            None => Deck::new(&session, route(), player_emit, bitrate, config.normalisation)?,
        };

        let connect_config = ConnectConfig {
            name: config.device_name,
            device_type: DeviceType::Computer,
            initial_volume: config.initial_volume,
            emit_set_queue_events: true,
            ..ConnectConfig::default()
        };
        let (spirc, task) = Spirc::new(
            connect_config,
            session.clone(),
            credentials,
            deck.player.clone(),
            deck.mixer.clone(),
        )
        .await?;

        if let Some(expected) = config.expected_username
            && !session.username().eq_ignore_ascii_case(&expected)
        {
            let _ = spirc.shutdown();
            task.await;
            return Err(Failure {
                reason: FailureReason::AccountMismatch,
                message: format!(
                    "playback signed in as {}, expected {expected}",
                    session.username()
                ),
            });
        }
        if let Some(carried) = carried {
            // Only now: until this session is up, the old one's drop still
            // explains the player's events.
            *deck.lock_route() = route();
            carried.take_over(&session, &spirc, emit.clone());
        }
        Ok((
            Self {
                spirc,
                session,
                reads,
                emit,
                deck,
            },
            task,
        ))
    }

    /// The reusable credential to persist, as JSON.
    pub fn credentials_json(&self) -> Option<String> {
        let credentials = self.session.cache()?.credentials()?;
        serde_json::to_string(&credentials).ok()
    }

    /// Whether `carried` is the playback this engine took over.
    pub fn took_over(&self, carried: &Carried) -> bool {
        Arc::ptr_eq(&self.deck.player, &carried.deck.player)
    }

    /// A shutdown asked for: the session and its song both stop.
    pub fn shutdown(&self) {
        let _ = self.spirc.shutdown();
        self.deck.clone().retire();
    }
}

impl Carried {
    /// Hands the deck to `session` (before its Spirc task runs, so whatever
    /// it loads comes through the new session) and restores the snapshot,
    /// once. A song the player still has is picked up where it has got to,
    /// playing or paused as it is now, without loading it again. When the
    /// restore is refused or fails, the song stops and `emit` says why.
    fn take_over(self, session: &Session, spirc: &Spirc, emit: Emit) {
        let Self {
            deck,
            snapshot,
            username,
        } = self;
        deck.player.set_session(session.clone());
        if !username.eq_ignore_ascii_case(&session.username()) {
            deck.player.stop();
            return;
        }
        let song = deck.lock_now().song();
        let snapshot = match song {
            // Still advancing: Spirc applies the restore only once its
            // dealer is up, and the position must have moved on by then.
            Some(song) if Some(&song.uri) == snapshot.track_uri().as_ref() => {
                Arc::new(if song.advancing {
                    snapshot.playing_on(song.position_ms, song.end_ms)
                } else {
                    snapshot.at_position(song.position_ms, song.playing)
                })
            }
            _ => snapshot,
        };
        log::info!(
            "restoring playback at {} ms, playing: {}",
            snapshot.position_ms(),
            snapshot.is_playing()
        );
        let outcome = match spirc.restore_playback_reporting(snapshot) {
            Ok(outcome) => outcome,
            Err(error) => return deck.resume_failed(error.to_string(), &emit),
        };
        tokio::spawn(async move {
            // No answer: the session ended first, and says so itself.
            let Ok(outcome) = outcome.await else {
                return;
            };
            match outcome {
                RestoreOutcome::Restored => log::info!("playback restored"),
                RestoreOutcome::Superseded => log::info!("playback restore superseded"),
                RestoreOutcome::ActiveElsewhere(device) => {
                    log::info!("not restoring playback: device {device} is playing now");
                    deck.player.stop();
                    emit(Event::Deactivated);
                }
                RestoreOutcome::Failed(why) => deck.resume_failed(why, &emit),
            }
        });
    }
}

impl Deck {
    fn new(
        session: &Session,
        route: Route,
        emit: Emit,
        bitrate: Bitrate,
        normalisation: bool,
    ) -> Result<Self, Failure> {
        let mixer = mixer::find(Some("softvol"))
            .ok_or_else(|| Failure::other("soft volume mixer missing"))?(
            MixerConfig {
                // librespot's default log curve puts every useful level in the
                // slider's top quarter; cubic spreads it out.
                volume_ctrl: VolumeCtrl::Cubic(VolumeCtrl::DEFAULT_DB_RANGE),
                ..MixerConfig::default()
            },
        )?;
        let backend =
            audio_backend::find(None).ok_or_else(|| Failure::other("audio backend missing"))?;
        let player = Player::new(
            PlayerConfig {
                bitrate,
                normalisation,
                ..PlayerConfig::default()
            },
            session.clone(),
            mixer.get_soft_volume(),
            move || backend(None, AudioFormat::default()),
        );
        let deck = Self {
            player,
            mixer,
            route: Arc::new(Mutex::new(route)),
            now: Arc::default(),
        };
        deck.forward_events(emit);
        Ok(deck)
    }

    /// One loop for the player's life, whichever session it serves. It ends
    /// with the player's thread, which drops the event channel.
    fn forward_events(&self, emit: Emit) {
        let mut events = self.player.get_player_event_channel();
        let route = self.route.clone();
        let now = self.now.clone();
        let relink_gen = Arc::new(AtomicU64::new(0));
        tokio::spawn(async move {
            let mut pairer = RelinkPairer::default();
            while let Some(event) = events.recv().await {
                now.lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .note(&event);
                let reads = {
                    let route = route
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner());
                    if route.session.is_invalid()
                        && matches!(
                            event,
                            PlayerEvent::SessionDisconnected { .. }
                                | PlayerEvent::Unavailable { .. }
                        )
                    {
                        // Our own connection dropped: Spirc reports it as a
                        // disconnect, and a track loading meanwhile fails for
                        // want of its key. Neither is another device taking
                        // over or a missing song; `SessionEnded` follows.
                        continue;
                    }
                    if let PlayerEvent::SetQueue {
                        context_uri,
                        next_tracks,
                        ..
                    } = event
                    {
                        let emit = emit.clone();
                        route
                            .queue
                            .update(context_uri, next_tracks, move |event| emit(event));
                        continue;
                    }
                    route.reads.clone()
                };
                match event {
                    PlayerEvent::TrackChanged { audio_item } => {
                        relink_gen.fetch_add(1, Ordering::SeqCst);
                        if let Some(track) = pairer.on_track_changed(Track::from_item(&audio_item))
                        {
                            emit(Event::TrackChanged { track });
                        }
                        continue;
                    }
                    PlayerEvent::Playing { ref track_id, .. }
                    | PlayerEvent::Paused { ref track_id, .. } => {
                        let context_uri = track_id.to_uri();
                        match pairer
                            .on_playing_or_paused(&context_uri, |uri| reads.cached_track(uri))
                        {
                            Some(PairedTrack::Ready(track)) => emit(Event::TrackChanged { track }),
                            Some(PairedTrack::NeedsLookup {
                                context_uri,
                                playable,
                                provisional,
                            }) => {
                                emit(Event::TrackChanged { track: provisional });
                                spawn_relink_lookup(
                                    reads,
                                    context_uri,
                                    playable,
                                    &relink_gen,
                                    emit.clone(),
                                );
                            }
                            None => {}
                        }
                    }
                    PlayerEvent::Loading { .. }
                    | PlayerEvent::Stopped { .. }
                    | PlayerEvent::Unavailable { .. }
                    | PlayerEvent::EndOfTrack { .. }
                    | PlayerEvent::SessionDisconnected { .. } => {
                        relink_gen.fetch_add(1, Ordering::SeqCst);
                        if let Some(track) = pairer.flush() {
                            emit(Event::TrackChanged { track });
                        }
                    }
                    _ => {}
                }
                if let Some(event) = Event::from_player(event) {
                    emit(event);
                }
            }
            if let Some(track) = pairer.flush() {
                emit(Event::TrackChanged { track });
            }
        });
    }

    fn resume_failed(&self, why: String, emit: &Emit) {
        log::warn!("unable to restore playback: {why}");
        self.player.stop();
        emit(Event::ResumeFailed);
    }

    fn lock_now(&self) -> std::sync::MutexGuard<'_, Now> {
        self.now
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn lock_route(&self) -> std::sync::MutexGuard<'_, Route> {
        self.route
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Stops the song and lets this handle go. The player's thread ends
    /// with its last handle; joining it may block, so not here.
    fn retire(self) {
        self.player.stop();
        crate::RUNTIME.spawn_blocking(move || drop(self));
    }
}

/// Pairs `PlayerEvent::TrackChanged { audio_item }` with the immediately
/// following `Playing { track_id }` or `Paused { track_id }` emitted by
/// librespot's `start_playback`, so relinked tracks (`track_id != audio_item.uri`)
/// keep the requested/context track's identity and display metadata.
#[derive(Default)]
struct RelinkPairer {
    pending: Option<Track>,
}

#[derive(Debug, PartialEq)]
enum PairedTrack {
    Ready(Track),
    NeedsLookup {
        context_uri: String,
        playable: Track,
        provisional: Track,
    },
}

impl RelinkPairer {
    fn on_track_changed(&mut self, track: Track) -> Option<Track> {
        self.pending.replace(track)
    }

    fn on_playing_or_paused(
        &mut self,
        track_uri: &str,
        cached: impl FnOnce(&str) -> Option<Track>,
    ) -> Option<PairedTrack> {
        let playable = self.pending.take()?;
        if track_uri == playable.uri {
            return Some(PairedTrack::Ready(playable));
        }
        if let Some(original) = cached(track_uri) {
            return Some(PairedTrack::Ready(Track::relinked_from(
                original, &playable,
            )));
        }
        let provisional = Track::with_context_uri(track_uri.to_owned(), &playable);
        Some(PairedTrack::NeedsLookup {
            context_uri: track_uri.to_owned(),
            playable,
            provisional,
        })
    }

    fn flush(&mut self) -> Option<Track> {
        self.pending.take()
    }
}

/// Resolves the original track metadata for a relinked song when it was not
/// already in `Reads`'s cache, guarded by `relink_gen` so a stale lookup can
/// never overwrite a newer track.
fn spawn_relink_lookup(
    reads: Arc<Reads>,
    context_uri: String,
    playable: Track,
    relink_gen: &Arc<AtomicU64>,
    emit: Emit,
) {
    let Ok(uri) = SpotifyUri::from_uri(&context_uri) else {
        return;
    };
    if !matches!(uri, SpotifyUri::Track { .. }) {
        return;
    }
    let generation = relink_gen.fetch_add(1, Ordering::SeqCst) + 1;
    let relink_gen = relink_gen.clone();
    tokio::spawn(async move {
        let Ok(mut found) = reads.tracks(&[uri]).await else {
            return;
        };
        if relink_gen.load(Ordering::SeqCst) == generation
            && let Some(Some(original)) = found.pop()
        {
            emit(Event::TrackChanged {
                track: Track::relinked_from(original, &playable),
            });
        }
    });
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Phase {
    #[default]
    Stopped,
    Loading,
    Playing,
    Paused,
    /// Played to its end, with no session to move on.
    Ended,
}

/// Where the player is, followed from its events: what a snapshot restored
/// on the next session should pick up.
#[derive(Debug, Default)]
struct Now {
    uri: String,
    phase: Phase,
    position_ms: u32,
    at: Option<Instant>,
    duration_ms: u32,
}

#[derive(Debug, PartialEq, Eq)]
struct Song {
    uri: String,
    position_ms: u32,
    /// Playing or loading, as opposed to paused.
    playing: bool,
    /// Audibly playing, so the position moves on by itself.
    advancing: bool,
    end_ms: u32,
}

impl Now {
    fn note(&mut self, event: &PlayerEvent) {
        use PlayerEvent as P;
        let (track_id, phase, position_ms) = match event {
            P::Loading {
                track_id,
                position_ms,
                ..
            } => (track_id, Some(Phase::Loading), *position_ms),
            P::Playing {
                track_id,
                position_ms,
                ..
            } => (track_id, Some(Phase::Playing), *position_ms),
            P::Paused {
                track_id,
                position_ms,
                ..
            } => (track_id, Some(Phase::Paused), *position_ms),
            P::Seeked {
                track_id,
                position_ms,
                ..
            }
            | P::PositionCorrection {
                track_id,
                position_ms,
                ..
            } => (track_id, None, *position_ms),
            P::EndOfTrack { track_id, .. } => (track_id, Some(Phase::Ended), self.duration_ms),
            P::Stopped { track_id, .. } | P::Unavailable { track_id, .. } => {
                (track_id, Some(Phase::Stopped), 0)
            }
            P::TrackChanged { audio_item } => {
                self.duration_ms = audio_item.duration_ms;
                return;
            }
            _ => return,
        };
        self.uri = track_id.to_uri();
        if let Some(phase) = phase {
            self.phase = phase;
        }
        self.position_ms = position_ms;
        self.at = Some(Instant::now());
    }

    /// The song the player holds, if any, and where it is now.
    fn song(&self) -> Option<Song> {
        let end_ms = if self.duration_ms > 0 {
            self.duration_ms
        } else {
            u32::MAX
        };
        let position_ms = match (self.phase, self.at) {
            (Phase::Stopped, _) => return None,
            (Phase::Playing, Some(at)) => {
                let played = u32::try_from(at.elapsed().as_millis()).unwrap_or(u32::MAX);
                self.position_ms.saturating_add(played).min(end_ms)
            }
            _ => self.position_ms,
        };
        Some(Song {
            uri: self.uri.clone(),
            position_ms,
            playing: self.phase != Phase::Paused,
            advancing: self.phase == Phase::Playing,
            end_ms,
        })
    }
}

fn parse_bitrate(kbps: Option<u16>) -> Bitrate {
    match kbps {
        Some(96) => Bitrate::Bitrate96,
        Some(160) => Bitrate::Bitrate160,
        _ => Bitrate::Bitrate320,
    }
}

/// Parses an optional HTTP proxy URL for librespot. librespot's tunnel only
/// speaks unauthenticated HTTP CONNECT, so anything else is rejected cleanly
/// rather than silently bypassed.
fn parse_proxy(raw: Option<&str>) -> Result<Option<url::Url>, Failure> {
    let Some(raw) = raw.map(str::trim).filter(|s| !s.is_empty()) else {
        return Ok(None);
    };
    let parsed = url::Url::parse(raw)
        .map_err(|_| Failure::other("The configured playback proxy URL is invalid."))?;
    if parsed.scheme() != "http"
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        return Err(Failure::other(
            "Playback only supports HTTP proxies without a username or password.",
        ));
    }
    Ok(Some(parsed))
}

#[cfg(test)]
mod tests {
    use super::*;
    use librespot_core::SpotifyUri;

    fn track() -> SpotifyUri {
        SpotifyUri::from_uri("spotify:track:4uLU6hMCjMI75M1A2tKUQC").unwrap()
    }

    #[test]
    fn follows_the_song_through_player_events() {
        let mut now = Now {
            duration_ms: 200_000,
            ..Now::default()
        };
        assert_eq!(now.song(), None);

        now.note(&PlayerEvent::Paused {
            play_request_id: 1,
            track_id: track(),
            position_ms: 61_000,
        });
        let song = now.song().unwrap();
        assert_eq!((song.position_ms, song.playing), (61_000, false));
        assert_eq!(song.uri, "spotify:track:4uLU6hMCjMI75M1A2tKUQC");

        // A seek while paused stays paused.
        now.note(&PlayerEvent::Seeked {
            play_request_id: 1,
            track_id: track(),
            position_ms: 90_000,
        });
        assert!(!now.song().unwrap().playing);

        now.note(&PlayerEvent::Playing {
            play_request_id: 1,
            track_id: track(),
            position_ms: 90_000,
        });
        now.at = Some(Instant::now() - Duration::from_secs(5));
        let song = now.song().unwrap();
        assert!(song.playing && song.advancing);
        assert_eq!(song.end_ms, 200_000);
        assert!((95_000..96_000).contains(&song.position_ms));

        // Played past the end: never beyond the track's length.
        now.at = Some(Instant::now() - Duration::from_secs(500));
        assert_eq!(now.song().unwrap().position_ms, 200_000);

        now.note(&PlayerEvent::EndOfTrack {
            play_request_id: 1,
            track_id: track(),
        });
        assert_eq!(now.song().unwrap().position_ms, 200_000);

        now.note(&PlayerEvent::Stopped {
            play_request_id: 1,
            track_id: track(),
        });
        assert_eq!(now.song(), None);
    }

    #[test]
    fn parses_and_validates_playback_proxy() {
        assert!(parse_proxy(None).unwrap().is_none());
        assert!(parse_proxy(Some("   ")).unwrap().is_none());
        let ok = parse_proxy(Some("http://127.0.0.1:7890"))
            .unwrap()
            .expect("parsed proxy");
        assert_eq!(ok.as_str(), "http://127.0.0.1:7890/");
        assert!(parse_proxy(Some("socks5://127.0.0.1:1080")).is_err());
        assert!(parse_proxy(Some("http://user:pass@127.0.0.1:7890")).is_err());
        assert!(parse_proxy(Some("not-a-url")).is_err());
    }

    #[test]
    fn parses_bitrate_and_config_defaults() {
        assert_eq!(parse_bitrate(None), Bitrate::Bitrate320);
        assert_eq!(parse_bitrate(Some(96)), Bitrate::Bitrate96);
        assert_eq!(parse_bitrate(Some(160)), Bitrate::Bitrate160);
        assert_eq!(parse_bitrate(Some(320)), Bitrate::Bitrate320);
        assert_eq!(parse_bitrate(Some(128)), Bitrate::Bitrate320);

        let raw = r#"{
            "device_id": "abc",
            "device_name": "Nanyin",
            "initial_volume": 32768,
            "credentials": { "type": "access_token", "token": "tok" }
        }"#;
        let cfg: Config = serde_json::from_str(raw).unwrap();
        assert_eq!(cfg.bitrate, None);
        assert!(!cfg.normalisation);
    }

    #[test]
    fn relink_pairer_resolves_cached_and_uncached_relinked_tracks() {
        let mut pairer = RelinkPairer::default();
        let playable = Track {
            uri: "spotify:track:alt".into(),
            linked_uri: None,
            name: "Wordless Groans".into(),
            artists: vec![],
            album: "王".into(),
            album_uri: Some("spotify:album:lord".into()),
            cover_url: Some("https://i.scdn.co/image/lord".into()),
            duration_ms: 298_000,
            explicit: false,
        };
        let original = Track {
            uri: "spotify:track:orig".into(),
            linked_uri: None,
            name: "我不是神，我只是平凡卻直拗愛著你的人".into(),
            artists: vec![],
            album: "我不是神，我只是平凡卻直拗愛著你的人".into(),
            album_uri: Some("spotify:album:single".into()),
            cover_url: Some("https://i.scdn.co/image/single".into()),
            duration_ms: 300_000,
            explicit: false,
        };

        // Normal track passes straight through without linked_uri.
        assert_eq!(pairer.on_track_changed(playable.clone()), None);
        assert_eq!(
            pairer.on_playing_or_paused("spotify:track:alt", |_| None),
            Some(PairedTrack::Ready(playable.clone()))
        );
        // Subsequent Playing/Paused (e.g. pause/resume) does not re-emit TrackChanged.
        assert_eq!(
            pairer.on_playing_or_paused("spotify:track:alt", |_| None),
            None
        );

        // Relinked track with cached metadata resolves immediately without network lookup.
        assert_eq!(pairer.on_track_changed(playable.clone()), None);
        let expected = Track::relinked_from(original.clone(), &playable);
        assert_eq!(
            pairer.on_playing_or_paused("spotify:track:orig", |uri| {
                (uri == "spotify:track:orig").then(|| original.clone())
            }),
            Some(PairedTrack::Ready(expected))
        );

        // Relinked track without cache emits provisional track with both URIs and requests lookup.
        assert_eq!(pairer.on_track_changed(playable.clone()), None);
        match pairer.on_playing_or_paused("spotify:track:orig", |_| None) {
            Some(PairedTrack::NeedsLookup {
                context_uri,
                playable: got_playable,
                provisional,
            }) => {
                assert_eq!(context_uri, "spotify:track:orig");
                assert_eq!(got_playable, playable);
                assert_eq!(provisional.uri, "spotify:track:orig");
                assert_eq!(provisional.linked_uri.as_deref(), Some("spotify:track:alt"));
            }
            other => panic!("expected NeedsLookup, got {other:?}"),
        }

        // Flush returns any dangling pending track when playback stops early.
        assert_eq!(pairer.on_track_changed(playable.clone()), None);
        assert_eq!(pairer.flush(), Some(playable));
        assert_eq!(pairer.flush(), None);
    }
}
