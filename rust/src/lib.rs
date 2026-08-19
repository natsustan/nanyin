//! nanyin-core: librespot bridge for the nanyin macOS app.
//!
//! Swift owns OAuth and the Web API; this crate owns the Spotify session,
//! Spotify Connect (Spirc), decoding, and forwards interleaved f32 PCM
//! (44100 Hz stereo) to Swift through FFI callbacks.
//!
//! Architecture adapted from NullSpot (MIT, michaelh03/NullSpot), playback
//! credential strategy informed by cliamp (MIT, bjarneo/cliamp).

mod proxy_sink;

use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use librespot_connect::{ConnectConfig, LoadRequest, LoadRequestOptions, Spirc};
use librespot_core::authentication::Credentials;
use librespot_core::cache::Cache;
use librespot_core::config::{DeviceType, SessionConfig};
use librespot_core::session::Session;
use librespot_playback::config::{AudioFormat, Bitrate, PlayerConfig};
use librespot_playback::mixer::softmixer::SoftMixer;
use librespot_playback::mixer::{Mixer, MixerConfig};
use librespot_playback::player::Player;

use once_cell::sync::Lazy;
use serde_json::json;
use tokio::sync::mpsc;

use proxy_sink::mk_proxy_sink;

// ============================================================================
// Error codes (shared convention with Swift side)
// ============================================================================
//  0 = success
// -1 = general error
// -2 = session disconnected — Swift should refresh the token and re-init
// -3 = session not ready yet — retry when the connected callback fires

// ============================================================================
// Global state
// ============================================================================

static RUNTIME: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    // Default worker count (= CPU cores). A tiny fixed pool starves the
    // dealer websocket's pong handling under decode/crypto load, tripping
    // its 3s ping timeout and killing spirc (verified against NullSpot,
    // which uses the default pool).
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
});

static SESSION: Mutex<Option<Session>> = Mutex::new(None);
static SPIRC: Mutex<Option<Arc<Spirc>>> = Mutex::new(None);
static PLAYER: Mutex<Option<Arc<Player>>> = Mutex::new(None);
/// Serializes generation changes with publishing or clearing player slots.
static PLAYER_LIFECYCLE: Mutex<()> = Mutex::new(());
static SHUTTING_DOWN: AtomicBool = AtomicBool::new(false);
/// Invalidates completion monitors from sessions replaced by a rebuild.
static PLAYER_GENERATION: AtomicU64 = AtomicU64::new(0);
/// Coalesces Spirc and session failure signals for the active generation.
static DISCONNECT_NOTIFIED: AtomicBool = AtomicBool::new(false);

static IS_PLAYING: AtomicBool = AtomicBool::new(false);
static POSITION: Mutex<PlaybackPosition> = Mutex::new(PlaybackPosition::empty());
static DURATION_MS: AtomicU32 = AtomicU32::new(0);
static CURRENT_URI: Mutex<Option<String>> = Mutex::new(None);

static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);

fn set_last_error(msg: &str) {
    *LAST_ERROR.lock().unwrap() = Some(msg.to_string());
}

/// Returns the last error message from a failed call (caller must free with
/// nanyin_free_string), or NULL.
#[no_mangle]
pub extern "C" fn nanyin_last_error() -> *mut c_char {
    let guard = LAST_ERROR.lock().unwrap();
    match guard.as_ref() {
        Some(msg) => match CString::new(msg.clone()) {
            Ok(s) => s.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

// ============================================================================
// Callbacks
// ============================================================================

type PlaybackStateCallback = extern "C" fn(*const c_char);
type SessionEventCallback = extern "C" fn();

static PLAYBACK_STATE_CB: Mutex<Option<PlaybackStateCallback>> = Mutex::new(None);
static SESSION_CONNECTED_CB: Mutex<Option<SessionEventCallback>> = Mutex::new(None);
static SESSION_DISCONNECTED_CB: Mutex<Option<SessionEventCallback>> = Mutex::new(None);

#[no_mangle]
pub extern "C" fn nanyin_register_audio_data_callback(cb: extern "C" fn(*const f32, usize)) {
    proxy_sink::register_audio_data_callback(cb);
}

#[no_mangle]
pub extern "C" fn nanyin_register_audio_control_callback(cb: extern "C" fn(u8)) {
    proxy_sink::register_audio_control_callback(cb);
}

#[no_mangle]
pub extern "C" fn nanyin_register_playback_state_callback(cb: PlaybackStateCallback) {
    *PLAYBACK_STATE_CB.lock().unwrap() = Some(cb);
}

#[no_mangle]
pub extern "C" fn nanyin_register_session_connected_callback(cb: SessionEventCallback) {
    *SESSION_CONNECTED_CB.lock().unwrap() = Some(cb);
}

#[no_mangle]
pub extern "C" fn nanyin_register_session_disconnected_callback(cb: SessionEventCallback) {
    *SESSION_DISCONNECTED_CB.lock().unwrap() = Some(cb);
}

fn emit_state(value: serde_json::Value) {
    let cb = { *PLAYBACK_STATE_CB.lock().unwrap() };
    if let Some(callback) = cb {
        if let Ok(c_str) = CString::new(value.to_string()) {
            callback(c_str.as_ptr());
        }
    }
}

fn notify_connected() {
    let cb = { *SESSION_CONNECTED_CB.lock().unwrap() };
    if let Some(callback) = cb {
        callback();
    }
}

fn notify_disconnected() {
    let cb = { *SESSION_DISCONNECTED_CB.lock().unwrap() };
    if let Some(callback) = cb {
        callback();
    }
}

// ============================================================================
// Session lifecycle
// ============================================================================

struct PlaybackPosition {
    stored_ms: u32,
    updated_at: Option<Instant>,
}

impl PlaybackPosition {
    const fn empty() -> Self {
        Self {
            stored_ms: 0,
            updated_at: None,
        }
    }

    #[cfg(test)]
    fn new(position_ms: u32, now: Instant) -> Self {
        Self {
            stored_ms: position_ms,
            updated_at: Some(now),
        }
    }

    fn update(&mut self, position_ms: u32, now: Instant) {
        self.stored_ms = position_ms;
        self.updated_at = Some(now);
    }

    fn get_at(&self, now: Instant, is_playing: bool, duration_ms: u32) -> u32 {
        let elapsed_ms = self
            .updated_at
            .map(|updated_at| now.saturating_duration_since(updated_at).as_millis())
            .unwrap_or(0)
            .min(u32::MAX as u128) as u32;
        interpolated_position_ms(self.stored_ms, elapsed_ms, is_playing, duration_ms)
    }

    fn freeze(&mut self, now: Instant, duration_ms: u32) {
        let position_ms = self.get_at(now, true, duration_ms);
        self.update(position_ms, now);
    }
}

fn update_position(position_ms: u32) {
    POSITION
        .lock()
        .unwrap()
        .update(position_ms, Instant::now());
}

/// Stops interpolation without losing elapsed time since the last player event.
fn stop_position_clock() {
    let mut position = POSITION.lock().unwrap();
    if IS_PLAYING.swap(false, Ordering::SeqCst) {
        position.freeze(Instant::now(), DURATION_MS.load(Ordering::SeqCst));
    }
}

/// Audio cache: 1 GiB LRU under ~/Library/Caches/nanyin/audio.
const AUDIO_CACHE_SIZE_LIMIT: u64 = 1_073_741_824;

/// Upper bound for the Spirc/dealer handshake inside nanyin_init_player.
/// Risk-control penalty windows drop accesspoint TLS handshakes silently —
/// observed 95s+ to connect, or never (2026-08-18). Fail fast and loud
/// instead of freezing the caller in block_on.
const PLAYER_INIT_TIMEOUT: Duration = Duration::from_secs(30);

fn audio_cache_path() -> Option<std::path::PathBuf> {
    dirs_home_cache().map(|c| c.join("audio"))
}

fn dirs_home_cache() -> Option<std::path::PathBuf> {
    std::env::var_os("HOME").map(|h| {
        std::path::PathBuf::from(h)
            .join("Library")
            .join("Caches")
            .join("nanyin")
    })
}

/// Initializes session + player + Spirc with the given OAuth access token.
/// Must be called before playback commands.
#[no_mangle]
pub extern "C" fn nanyin_init_player(access_token: *const c_char, device_id: *const c_char) -> i32 {
    let _ = env_logger::try_init();
    eprintln!("nanyin_core: init_player called");

    if access_token.is_null() {
        eprintln!("nanyin_core: init_player: token is null");
        return -1;
    }
    let token = unsafe {
        match CStr::from_ptr(access_token).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                eprintln!("nanyin_core: init_player: invalid utf8 token");
                return -1;
            }
        }
    };
    let device = unsafe {
        if device_id.is_null() {
            format!("nanyin_{}", std::process::id())
        } else {
            match CStr::from_ptr(device_id).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => format!("nanyin_{}", std::process::id()),
            }
        }
    };

    // Full rebuild when spirc died or the session went invalid (network
    // loss, idle timeout, server drop). A session that merely exists can
    // still be dead — every command would hit a closed connection while
    // init_player keeps answering "already initialized" (observed
    // 2026-08-19: reconnect loop no-oped against a ghost session).
    let (generation, stale_spirc, stale_session) = {
        let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
        let needs_init = {
            let session = SESSION.lock().unwrap();
            let spirc = SPIRC.lock().unwrap();
            session.is_none()
                || spirc.is_none()
                || session.as_ref().is_some_and(|s| s.is_invalid())
        };
        if !needs_init {
            eprintln!("nanyin_core: init_player: already initialized");
            return 0;
        }

        let generation = PLAYER_GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
        SHUTTING_DOWN.store(false, Ordering::SeqCst);
        DISCONNECT_NOTIFIED.store(false, Ordering::SeqCst);
        let spirc = SPIRC.lock().unwrap().take();
        let session = SESSION.lock().unwrap().take();
        PLAYER.lock().unwrap().take();
        (generation, spirc, session)
    };
    // Tear down stale state before rebuilding (spirc died or fresh start).
    if let Some(spirc) = stale_spirc {
        let _ = spirc.shutdown();
    }
    if let Some(session) = stale_session {
        session.shutdown();
    }

    let result = RUNTIME.block_on(init_player_async(&token, &device, generation));

    match result {
        Ok(()) => {
            eprintln!("nanyin_core: init_player OK");
            0
        }
        Err(e) => {
            eprintln!("nanyin_core: init_player FAILED: {e}");
            set_last_error(&e);
            -1
        }
    }
}

async fn init_player_async(
    access_token: &str,
    device_id: &str,
    generation: u64,
) -> Result<(), String> {
    eprintln!("nanyin_core: init_player_async starting (device {device_id})");

    let session_config = SessionConfig {
        device_id: device_id.to_string(),
        ..Default::default()
    };
    let credentials = Credentials::with_access_token(access_token);

    // Audio-only disk cache; degrade gracefully to no cache on failure.
    let cache = match Cache::new(
        None::<std::path::PathBuf>,
        None,
        audio_cache_path(),
        Some(AUDIO_CACHE_SIZE_LIMIT),
    ) {
        Ok(c) => Some(c),
        Err(e) => {
            log::debug!("audio cache disabled ({e}), continuing without");
            None
        }
    };

    let session = Session::new(session_config, cache);
    // NOTE: do NOT connect here — Spirc::new() registers dealer listeners first
    // and then connects the session itself. Connecting twice yields NotConnected.

    let mixer: Arc<SoftMixer> = Arc::new(
        SoftMixer::open(MixerConfig::default()).map_err(|e| format!("mixer: {e}"))?,
    );

    let player_config = PlayerConfig {
        bitrate: Bitrate::Bitrate320,
        gapless: true,
        normalisation: true,
        ..Default::default()
    };
    let audio_format = AudioFormat::default();

    let player = Player::new(
        player_config,
        session.clone(),
        mixer.get_soft_volume(),
        move || mk_proxy_sink(None, audio_format),
    );

    // Player event listener → global state + Swift callbacks.
    let mut events: librespot_playback::player::PlayerEventChannel = player.get_player_event_channel();
    RUNTIME.spawn(async move {
        while let Some(event) = events.recv().await {
            if !with_current_player_generation(generation, || handle_player_event(event)) {
                return;
            }
        }
    });

    let connect_config = ConnectConfig {
        name: "nanyin".to_string(),
        device_type: DeviceType::Computer,
        initial_volume: 0xFFFF,
        ..Default::default()
    };

    let (spirc, spirc_task) = tokio::time::timeout(
        PLAYER_INIT_TIMEOUT,
        Spirc::new(
            connect_config,
            session.clone(),
            credentials,
            player.clone(),
            mixer as Arc<dyn Mixer>,
        ),
    )
    .await
    .map_err(|_| {
        "spirc init: timed out — Spotify accesspoints unreachable (risk-control throttling?)"
            .to_string()
    })?
    .map_err(|e| format!("spirc init: {e:?}"))?;

    let spirc = Arc::new(spirc);
    let published = {
        let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
        if PLAYER_GENERATION.load(Ordering::SeqCst) != generation
            || SHUTTING_DOWN.load(Ordering::SeqCst)
        {
            false
        } else {
            *SESSION.lock().unwrap() = Some(session.clone());
            *SPIRC.lock().unwrap() = Some(spirc.clone());
            *PLAYER.lock().unwrap() = Some(player.clone());
            true
        }
    };
    if !published {
        let _ = spirc.shutdown();
        session.shutdown();
        return Err("player initialization cancelled".to_string());
    }

    let spirc_handle = RUNTIME.spawn(spirc_task);
    let monitor_spirc = spirc.clone();
    // When the spirc task exits (dealer loss, fatal error), mark the session
    // unusable and tell Swift to re-init — otherwise every command hits a
    // closed channel forever (the "channel closed" failure mode).
    RUNTIME.spawn(async move {
        if let Err(join_err) = spirc_handle.await {
            eprintln!("nanyin_core: spirc task panicked: {join_err}");
        }
        let should_notify = {
            let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
            if PLAYER_GENERATION.load(Ordering::SeqCst) != generation {
                false
            } else {
                let mut slot = SPIRC.lock().unwrap();
                if slot
                    .as_ref()
                    .is_some_and(|current| Arc::ptr_eq(current, &monitor_spirc))
                {
                    slot.take();
                    stop_position_clock();
                    DISCONNECT_NOTIFIED
                        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
                        .is_ok()
                } else {
                    false
                }
            }
        };
        if !should_notify {
            return;
        }
        eprintln!("nanyin_core: spirc task ended — session unusable, notifying");
        notify_disconnected();
    });

    // Watch the session; when it drops (idle timeout, network loss, revoke),
    // tell Swift to re-authenticate.
    let watcher_session = session.clone();
    RUNTIME.spawn(async move {
        loop {
            if PLAYER_GENERATION.load(Ordering::SeqCst) != generation {
                return;
            }
            if watcher_session.is_invalid() {
                break;
            }
            if SHUTTING_DOWN.load(Ordering::SeqCst) {
                return; // planned shutdown — no callback
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        let should_notify = {
            let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
            if PLAYER_GENERATION.load(Ordering::SeqCst) != generation
                || SHUTTING_DOWN.load(Ordering::SeqCst)
            {
                false
            } else {
                stop_position_clock();
                DISCONNECT_NOTIFIED
                    .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
                    .is_ok()
            }
        };
        if !should_notify {
            return;
        }
        log::debug!("session disconnected");
        notify_disconnected();
    });

    log::debug!("nanyin: session + spirc ready (device {device_id})");
    notify_connected();
    Ok(())
}

/// Shuts down Spirc and the session (app quit).
#[no_mangle]
pub extern "C" fn nanyin_shutdown() -> i32 {
    let (spirc, session) = {
        let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
        SHUTTING_DOWN.store(true, Ordering::SeqCst);
        PLAYER_GENERATION.fetch_add(1, Ordering::SeqCst);
        let spirc = SPIRC.lock().unwrap().take();
        let session = SESSION.lock().unwrap().take();
        PLAYER.lock().unwrap().take();
        (spirc, session)
    };
    IS_PLAYING.store(false, Ordering::SeqCst);
    *CURRENT_URI.lock().unwrap() = None;
    DURATION_MS.store(0, Ordering::SeqCst);
    update_position(0);

    RUNTIME.block_on(async move {
        if let Some(spirc) = spirc {
            let _ = spirc.shutdown();
        }
        if let Some(session) = session {
            session.shutdown();
        }
    });

    Ok::<(), ()>(()).map_or(-1, |()| 0)
}

fn handle_player_event(event: librespot_playback::player::PlayerEvent) {
    use librespot_playback::player::PlayerEvent;

    // Compact one-line event log (AudioItem dumps were unreadable noise).
    if !matches!(event, PlayerEvent::PositionCorrection { .. }) {
        let short = match &event {
            PlayerEvent::Playing { track_id, .. } => format!("Playing {track_id}"),
            PlayerEvent::Paused { track_id, .. } => format!("Paused {track_id}"),
            PlayerEvent::Loading { track_id, .. } => format!("Loading {track_id}"),
            PlayerEvent::Stopped { track_id, .. } => format!("Stopped {track_id}"),
            PlayerEvent::TrackChanged { audio_item } => {
                format!("TrackChanged {} ({})", audio_item.track_id, audio_item.name)
            }
            PlayerEvent::EndOfTrack { .. } => "EndOfTrack".to_string(),
            PlayerEvent::Seeked { position_ms, .. } => format!("Seeked {position_ms}ms"),
            PlayerEvent::ShuffleChanged { shuffle } => format!("ShuffleChanged {shuffle}"),
            PlayerEvent::RepeatChanged { context, track } => {
                format!("RepeatChanged context={context} track={track}")
            }
            other => format!("{other:?}"),
        };
        eprintln!("nanyin_core: {short}");
    }

    match event {
        PlayerEvent::Loading { track_id, position_ms, .. } => {
            // Buffering: audio hasn't started yet. Freeze the interpolated
            // position clock — otherwise the UI keeps counting from the
            // previous track's timestamp while nothing is audible.
            IS_PLAYING.store(false, Ordering::SeqCst);
            *CURRENT_URI.lock().unwrap() = Some(track_id.to_string());
            update_position(position_ms);
            emit_state(json!({
                "event": "loading",
                "track_uri": track_id.to_string(),
                "position_ms": position_ms,
            }));
        }
        PlayerEvent::Playing { track_id, position_ms, .. } => {
            IS_PLAYING.store(true, Ordering::SeqCst);
            *CURRENT_URI.lock().unwrap() = Some(track_id.to_string());
            update_position(position_ms);
            emit_state(json!({
                "event": "playing",
                "track_uri": track_id.to_string(),
                "position_ms": position_ms,
            }));
        }
        PlayerEvent::Paused { track_id, position_ms, .. } => {
            IS_PLAYING.store(false, Ordering::SeqCst);
            update_position(position_ms);
            emit_state(json!({
                "event": "paused",
                "track_uri": track_id.to_string(),
                "position_ms": position_ms,
            }));
        }
        PlayerEvent::Stopped { track_id, .. } => {
            stop_position_clock();
            emit_state(json!({
                "event": "stopped",
                "track_uri": track_id.to_string(),
            }));
        }
        PlayerEvent::Seeked { position_ms, .. }
        | PlayerEvent::PositionCorrection { position_ms, .. } => {
            update_position(position_ms);
            emit_state(json!({
                "event": "position",
                "position_ms": position_ms,
            }));
        }
        PlayerEvent::TrackChanged { audio_item } => {
            let uri = audio_item.track_id.to_string();
            let duration = audio_item.duration_ms;
            *CURRENT_URI.lock().unwrap() = Some(uri.clone());
            DURATION_MS.store(duration, Ordering::SeqCst);
            update_position(0);

            // Full metadata comes with the event — no extra Web API round trip.
            // covers[0] is the LARGE variant (Spotify orders by size).
            let (album, artists) = match &audio_item.unique_fields {
                librespot_metadata::audio::item::UniqueFields::Track { artists, album, .. } => (
                    album.clone(),
                    artists
                        .iter()
                        .map(|a| a.name.clone())
                        .collect::<Vec<_>>()
                        .join(", "),
                ),
                _ => (String::new(), String::new()),
            };
            let title = audio_item.name.clone();
            let cover = audio_item.covers.first().map(|c| c.url.clone());

            emit_state(json!({
                "event": "track_changed",
                "track_uri": uri,
                "duration_ms": duration,
                "title": title,
                "artists": artists,
                "album": album,
                "cover_url": cover,
            }));
        }
        PlayerEvent::EndOfTrack { .. } => {
            stop_position_clock();
            emit_state(json!({ "event": "end_of_track" }));
        }
        PlayerEvent::ShuffleChanged { shuffle } => {
            emit_state(json!({ "event": "shuffle_changed", "shuffle": shuffle }));
        }
        PlayerEvent::RepeatChanged { context, track } => {
            emit_state(json!({
                "event": "repeat_changed",
                "repeat_context": context,
                "repeat_track": track,
            }));
        }
        _ => {}
    }
}

fn with_current_player_generation(generation: u64, action: impl FnOnce()) -> bool {
    let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
    if PLAYER_GENERATION.load(Ordering::SeqCst) != generation {
        return false;
    }
    action();
    true
}

// ============================================================================
// Playback commands
// ============================================================================

/// Returns 0 when Spirc is available, -2 when a re-init is needed.
fn require_spirc() -> Result<Arc<Spirc>, i32> {
    let guard = SPIRC.lock().unwrap();
    match guard.as_ref() {
        Some(spirc) => Ok(spirc.clone()),
        None => Err(-2),
    }
}

/// Plays the given track URIs (JSON array, e.g. ["spotify:track:..."]),
/// starting at start_index. Spirc becomes active first.
#[no_mangle]
pub extern "C" fn nanyin_play_tracks(track_uris_json: *const c_char, start_index: u32) -> i32 {
    if track_uris_json.is_null() {
        return -1;
    }
    let raw = unsafe {
        match CStr::from_ptr(track_uris_json).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };
    let uris: Vec<String> = match serde_json::from_str(&raw) {
        Ok(u) => u,
        Err(e) => {
            log::debug!("nanyin_play_tracks: bad JSON ({e})");
            return -1;
        }
    };
    if uris.is_empty() {
        return -1;
    }

    let spirc = match require_spirc() {
        Ok(s) => s,
        Err(code) => return code,
    };

    let request = LoadRequest::from_tracks(
        uris,
        LoadRequestOptions {
            start_playing: true,
            playing_track: Some(librespot_connect::PlayingTrack::Index(start_index)),
            ..Default::default()
        },
    );

    eprintln!("nanyin_core: play_tracks → activate + load (index {start_index})");
    // Optimistic UI guard: stop the position clock immediately so the UI
    // doesn't keep counting the previous track while this one buffers.
    IS_PLAYING.store(false, Ordering::SeqCst);
    update_position(0);
    // Claim the active-device role first — Spirc ignores commands while
    // this device is Not Active (the "ignored while Not Active" WARN).
    if let Err(e) = spirc.activate() {
        eprintln!("nanyin_core: play_tracks: activate FAILED: {e:?}");
        set_last_error(&format!("activate: {e:?}"));
        return -1;
    }
    match spirc.load(request) {
        Ok(()) => {
            eprintln!("nanyin_core: play_tracks: load command sent");
            0
        }
        Err(e) => {
            eprintln!("nanyin_core: play_tracks: load FAILED: {e:?}");
            set_last_error(&format!("load: {e:?}"));
            -1
        }
    }
}

/// Plays a server-resolved context (playlist / album / collection) starting
/// at start_index. Preferred over nanyin_play_tracks for large contexts —
/// uploading thousands of track URIs into Connect state gets rejected (429).
#[no_mangle]
pub extern "C" fn nanyin_play_context(context_uri: *const c_char, start_index: u32) -> i32 {
    if context_uri.is_null() {
        return -1;
    }
    let uri = unsafe {
        match CStr::from_ptr(context_uri).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };

    let spirc = match require_spirc() {
        Ok(s) => s,
        Err(code) => return code,
    };

    eprintln!("nanyin_core: play_context → activate + load ({uri}, index {start_index})");
    IS_PLAYING.store(false, Ordering::SeqCst);
    update_position(0);
    if let Err(e) = spirc.activate() {
        eprintln!("nanyin_core: play_context: activate FAILED: {e:?}");
        set_last_error(&format!("activate: {e:?}"));
        return -1;
    }

    let request = LoadRequest::from_context_uri(
        uri,
        LoadRequestOptions {
            start_playing: true,
            playing_track: Some(librespot_connect::PlayingTrack::Index(start_index)),
            ..Default::default()
        },
    );

    match spirc.load(request) {
        Ok(()) => {
            eprintln!("nanyin_core: play_context: load command sent");
            0
        }
        Err(e) => {
            eprintln!("nanyin_core: play_context: load FAILED: {e:?}");
            set_last_error(&format!("load: {e:?}"));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn nanyin_pause() -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.pause().map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_resume() -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.play().map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_next() -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.next().map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_prev() -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.prev().map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_stop() -> i32 {
    let spirc = match require_spirc() {
        Ok(s) => s,
        Err(code) => return code,
    };
    match spirc.disconnect(true) {
        Ok(()) => {
            stop_position_clock();
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn nanyin_seek(position_ms: u32) -> i32 {
    require_spirc().map_or_else(|c| c, |s| {
        s.set_position_ms(position_ms).map_or(-1, |_| {
            update_position(position_ms);
            0
        })
    })
}

/// Sets volume (0–65535).
#[no_mangle]
pub extern "C" fn nanyin_set_volume(volume: u16) -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.set_volume(volume).map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_shuffle(on: bool) -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.shuffle(on).map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_repeat(on: bool) -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.repeat(on).map_or(-1, |_| 0))
}

#[no_mangle]
pub extern "C" fn nanyin_repeat_track(on: bool) -> i32 {
    require_spirc().map_or_else(|c| c, |s| s.repeat_track(on).map_or(-1, |_| 0))
}

/// Appends a track to the end of the active queue.
#[no_mangle]
pub extern "C" fn nanyin_add_to_queue(track_uri: *const c_char) -> i32 {
    if track_uri.is_null() {
        return -1;
    }
    let uri = unsafe {
        match CStr::from_ptr(track_uri).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };
    let spirc = match require_spirc() {
        Ok(s) => s,
        Err(code) => return code,
    };
    match librespot_core::SpotifyUri::from_uri(&uri) {
        Ok(id) => spirc.add_to_queue(id).map_or(-1, |_| 0),
        Err(_) => {
            eprintln!("nanyin_core: add_to_queue: invalid URI {uri}");
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn nanyin_is_playing() -> i32 {
    IS_PLAYING.load(Ordering::SeqCst) as i32
}

fn interpolated_position_ms(
    stored: u32,
    elapsed_ms: u32,
    is_playing: bool,
    duration_ms: u32,
) -> u32 {
    if !is_playing {
        return stored;
    }

    let position = stored.saturating_add(elapsed_ms);
    if duration_ms > 0 {
        position.min(duration_ms)
    } else {
        position
    }
}

/// Current playback position in ms, interpolated while playing and capped at
/// the current track duration. Playing/paused/disconnected events own the
/// clock state; librespot does not emit periodic position events.
#[no_mangle]
pub extern "C" fn nanyin_get_position_ms() -> u32 {
    POSITION.lock().unwrap().get_at(
        Instant::now(),
        IS_PLAYING.load(Ordering::SeqCst),
        DURATION_MS.load(Ordering::SeqCst),
    )
}

#[no_mangle]
pub extern "C" fn nanyin_get_duration_ms() -> u32 {
    DURATION_MS.load(Ordering::SeqCst)
}

/// Frees a C string allocated by this library.
#[no_mangle]
pub extern "C" fn nanyin_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

// Silence "unused" warnings for the mpsc import kept for parity.
#[allow(unused)]
fn _unused(m: mpsc::UnboundedSender<()>) {}

#[cfg(test)]
mod tests {
    use super::{
        interpolated_position_ms, with_current_player_generation, PlaybackPosition,
        PLAYER_GENERATION, PLAYER_LIFECYCLE,
    };
    use std::sync::atomic::Ordering;
    use std::sync::mpsc;
    use std::sync::TryLockError;
    use std::thread;
    use std::time::{Duration, Instant};

    #[test]
    fn player_event_generation_check_is_atomic_with_rebuilds() {
        let generation = {
            let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
            PLAYER_GENERATION.fetch_add(1, Ordering::SeqCst) + 1
        };
        let (event_entered_tx, event_entered_rx) = mpsc::channel();
        let (release_event_tx, release_event_rx) = mpsc::channel();
        let event_thread = thread::spawn(move || {
            assert!(with_current_player_generation(generation, || {
                event_entered_tx.send(()).unwrap();
                release_event_rx.recv().unwrap();
            }));
        });
        event_entered_rx.recv().unwrap();

        let rebuild_during_event = match PLAYER_LIFECYCLE.try_lock() {
            Ok(_lifecycle) => {
                PLAYER_GENERATION.fetch_add(1, Ordering::SeqCst);
                true
            }
            Err(TryLockError::WouldBlock) => false,
            Err(TryLockError::Poisoned(_)) => panic!("player lifecycle lock was poisoned"),
        };

        release_event_tx.send(()).unwrap();
        event_thread.join().unwrap();
        if !rebuild_during_event {
            let _lifecycle = PLAYER_LIFECYCLE.lock().unwrap();
            PLAYER_GENERATION.fetch_add(1, Ordering::SeqCst);
        }

        assert!(
            !rebuild_during_event,
            "generation changed while the old player event was being handled"
        );
        assert!(!with_current_player_generation(generation, || {
            panic!("stale player event was handled after rebuild");
        }));
    }

    #[test]
    fn position_uses_only_monotonic_elapsed_time() {
        let started_at = Instant::now();
        let position = PlaybackPosition::new(0, started_at);

        assert_eq!(
            position.get_at(started_at + Duration::from_secs(10), true, 180_000),
            10_000
        );
    }

    #[test]
    fn playing_position_keeps_advancing_without_periodic_player_events() {
        assert_eq!(
            interpolated_position_ms(0, 10_000, true, 180_000),
            10_000
        );
    }

    #[test]
    fn paused_position_does_not_advance() {
        assert_eq!(
            interpolated_position_ms(7_500, 10_000, false, 180_000),
            7_500
        );
    }

    #[test]
    fn playing_position_does_not_exceed_track_duration() {
        assert_eq!(
            interpolated_position_ms(179_000, 10_000, true, 180_000),
            180_000
        );
    }

    #[test]
    fn freezing_position_preserves_accrued_playback_time() {
        let started_at = Instant::now();
        let mut position = PlaybackPosition::new(5_000, started_at);
        let stopped_at = started_at + Duration::from_secs(10);

        position.freeze(stopped_at, 180_000);

        assert_eq!(
            position.get_at(stopped_at + Duration::from_secs(5), false, 180_000),
            15_000
        );
    }
}
