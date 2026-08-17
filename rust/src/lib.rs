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
use std::time::Duration;

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
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
});

static SESSION: Mutex<Option<Session>> = Mutex::new(None);
static SPIRC: Mutex<Option<Arc<Spirc>>> = Mutex::new(None);
static PLAYER: Mutex<Option<Arc<Player>>> = Mutex::new(None);
static SHUTTING_DOWN: AtomicBool = AtomicBool::new(false);

static IS_PLAYING: AtomicBool = AtomicBool::new(false);
static POSITION_MS: AtomicU32 = AtomicU32::new(0);
static POSITION_TS_MS: AtomicU64 = AtomicU64::new(0);
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

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn update_position(position_ms: u32) {
    POSITION_MS.store(position_ms, Ordering::SeqCst);
    POSITION_TS_MS.store(now_ms(), Ordering::SeqCst);
}

/// Audio cache: 1 GiB LRU under ~/Library/Caches/nanyin/audio.
const AUDIO_CACHE_SIZE_LIMIT: u64 = 1_073_741_824;

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
pub extern "C" fn nanyin_init_player(access_token: *const c_char) -> i32 {
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

    {
        let guard = SESSION.lock().unwrap();
        if guard.is_some() {
            eprintln!("nanyin_core: init_player: already initialized");
            return 0;
        }
    }

    SHUTTING_DOWN.store(false, Ordering::SeqCst);

    let result = RUNTIME.block_on(init_player_async(&token));

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

async fn init_player_async(access_token: &str) -> Result<(), String> {
    let device_id = format!("nanyin_{}", std::process::id());
    eprintln!("nanyin_core: init_player_async starting (device {device_id})");

    let session_config = SessionConfig {
        device_id: device_id.clone(),
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
            handle_player_event(event);
        }
    });

    let connect_config = ConnectConfig {
        name: "nanyin".to_string(),
        device_type: DeviceType::Computer,
        initial_volume: 0xFFFF,
        ..Default::default()
    };

    let (spirc, spirc_task) = Spirc::new(
        connect_config,
        session.clone(),
        credentials,
        player.clone(),
        mixer as Arc<dyn Mixer>,
    )
    .await
    .map_err(|e| format!("spirc init: {e:?}"))?;

    let spirc = Arc::new(spirc);
    RUNTIME.spawn(spirc_task);

    // Watch the session; when it drops (idle timeout, network loss, revoke),
    // tell Swift to re-authenticate.
    let watcher_session = session.clone();
    RUNTIME.spawn(async move {
        loop {
            if watcher_session.is_invalid() {
                break;
            }
            if SHUTTING_DOWN.load(Ordering::SeqCst) {
                return; // planned shutdown — no callback
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        log::debug!("session disconnected");
        IS_PLAYING.store(false, Ordering::SeqCst);
        notify_disconnected();
    });

    *SESSION.lock().unwrap() = Some(session);
    *SPIRC.lock().unwrap() = Some(spirc);
    *PLAYER.lock().unwrap() = Some(player);

    log::debug!("nanyin: session + spirc ready (device {device_id})");
    notify_connected();
    Ok(())
}

/// Shuts down Spirc and the session (app quit).
#[no_mangle]
pub extern "C" fn nanyin_shutdown() -> i32 {
    SHUTTING_DOWN.store(true, Ordering::SeqCst);
    IS_PLAYING.store(false, Ordering::SeqCst);

    let spirc = { SPIRC.lock().unwrap().take() };
    let session = { SESSION.lock().unwrap().take() };
    PLAYER.lock().unwrap().take();
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

    let current_uri = CURRENT_URI.lock().unwrap().clone();
    let _ = current_uri;

    match event {
        PlayerEvent::Loading { track_id, position_ms, .. } => {
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
            IS_PLAYING.store(false, Ordering::SeqCst);
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
            emit_state(json!({
                "event": "track_changed",
                "track_uri": uri,
                "duration_ms": duration,
            }));
        }
        PlayerEvent::EndOfTrack { .. } => {
            IS_PLAYING.store(false, Ordering::SeqCst);
            emit_state(json!({ "event": "end_of_track" }));
        }
        _ => {}
    }
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

/// Plays the given track URIs (JSON array, e.g. ["spotify:track:..."]).
#[no_mangle]
pub extern "C" fn nanyin_play_tracks(track_uris_json: *const c_char) -> i32 {
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
            ..Default::default()
        },
    );

    match spirc.load(request) {
        Ok(()) => 0,
        Err(e) => {
            log::debug!("nanyin_play_tracks: load failed ({e:?})");
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
            IS_PLAYING.store(false, Ordering::SeqCst);
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
pub extern "C" fn nanyin_is_playing() -> i32 {
    IS_PLAYING.load(Ordering::SeqCst) as i32
}

/// Current playback position in ms, interpolated while playing
/// (capped at 5 s without a fresh event).
#[no_mangle]
pub extern "C" fn nanyin_get_position_ms() -> u32 {
    let stored = POSITION_MS.load(Ordering::SeqCst);
    let ts = POSITION_TS_MS.load(Ordering::SeqCst);
    if ts == 0 {
        return 0;
    }
    if IS_PLAYING.load(Ordering::SeqCst) {
        let elapsed = (now_ms().saturating_sub(ts)).min(5000) as u32;
        stored.saturating_add(elapsed)
    } else {
        stored
    }
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
