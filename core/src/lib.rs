//! C ABI for the Swift app. Commands and events are JSON strings so the
//! header stays small and Swift decodes with `Codable`.
//!
//! At most one engine exists. Each `nanyin_connect` starts a new generation
//! and every event carries the generation it belongs to; Swift drops events
//! from any generation but the one it started last. Player events carry the
//! newest generation instead: the player outlives a dropped session, and
//! what it does between sessions belongs to the one reconnecting.

mod commands;
mod engine;
mod events;
mod logging;
mod pathfinder;
mod queue;
mod reads;
mod requests;

use std::{
    ffi::{CStr, CString, c_char, c_void},
    sync::{Arc, LazyLock, Mutex, MutexGuard},
};

use tokio::runtime::Runtime;

use crate::{
    commands::Command,
    engine::{Carried, Config, Emit, Engine},
    events::Event,
    requests::Request,
};

pub type EventCallback = extern "C" fn(context: *mut c_void, generation: u64, json: *const c_char);

/// Swift's context pointer. Swift keeps it alive for the whole process and
/// accepts callbacks on any thread.
#[derive(Clone, Copy)]
struct Context(*mut c_void);
unsafe impl Send for Context {}

#[derive(Default)]
struct State {
    listener: Option<(EventCallback, Context)>,
    generation: u64,
    engine: Option<Engine>,
    /// A dropped session's playback, waiting for the next connect.
    carried: Option<Carried>,
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(Mutex::default);
pub(crate) static RUNTIME: LazyLock<Runtime> =
    LazyLock::new(|| Runtime::new().expect("unable to start the tokio runtime"));

fn state() -> MutexGuard<'static, State> {
    STATE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Delivers `event`, tagged with its generation. The callback runs without
/// the lock held, so Swift may call back in.
fn emit(generation: u64, event: &Event) {
    let Some((callback, context)) = state().listener else {
        return;
    };
    let Some(json) = serde_json::to_string(event)
        .ok()
        .and_then(|json| CString::new(json).ok())
    else {
        return;
    };
    callback(context.0, generation, json.as_ptr());
}

/// The UTF-8 text at `ptr`, a C string from Swift, or `None` for null.
fn read_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

fn read_json<T: serde::de::DeserializeOwned>(ptr: *const c_char) -> Option<T> {
    serde_json::from_str(read_str(ptr)?).ok()
}

/// Registers the event callback and starts logging, to stderr and, when
/// `log_path` is not null, to that file. Call once, before anything else.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_init(
    callback: EventCallback,
    context: *mut c_void,
    log_path: *const c_char,
) {
    logging::init(read_str(log_path).map(std::path::PathBuf::from));
    state().listener = Some((callback, Context(context)));
}

/// Starts a new engine from `config_json`, replacing any current one.
/// Returns the generation its events will carry, or 0 for invalid config.
/// The outcome arrives as a `connected` or `connect_failed` event.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_connect(config_json: *const c_char) -> u64 {
    let Some(config) = read_json::<Config>(config_json) else {
        return 0;
    };
    let (generation, carried) = {
        let mut state = state();
        if let Some(old) = state.engine.take() {
            old.shutdown();
        }
        state.generation += 1;
        // A clone: until the new session takes it over, the song still
        // answers commands from here, and plays on if connecting fails.
        (state.generation, state.carried.clone())
    };
    let player_emit: Emit = Arc::new(|event| {
        let generation = state().generation;
        emit(generation, &event);
    });
    RUNTIME.spawn(engine::run(
        config,
        move |event| emit(generation, &event),
        player_emit,
        carried,
        move |engine| {
            let mut state = state();
            if state.generation != generation {
                return Some(engine);
            }
            if let Some(carried) = state.carried.take()
                && !engine.took_over(&carried)
            {
                carried.retire();
            }
            state.engine = Some(engine);
            None
        },
        move || {
            let mut state = state();
            if state.generation == generation {
                state.engine.take()
            } else {
                None
            }
        },
        move |carried| {
            let mut state = state();
            if state.generation != generation {
                return Some(carried);
            }
            if let Some(older) = state.carried.replace(carried) {
                older.retire();
            }
            None
        },
    ));
    generation
}

/// Applies a JSON command to the current engine. Between sessions, play,
/// pause, seek and volume go to the song the dropped session left playing.
/// Returns 0 on success, -1 for an unreadable command, -2 with no engine,
/// -3 when Spirc refused it (its task has ended).
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_command(command_json: *const c_char) -> i32 {
    let Some(command) = read_json::<Command>(command_json) else {
        return -1;
    };
    let state = state();
    let Some(engine) = &state.engine else {
        let carried = state.carried.as_ref();
        return if carried.is_some_and(|carried| carried.command(&command)) {
            0
        } else {
            -2
        };
    };
    match command.apply(&engine.spirc) {
        Ok(()) => 0,
        Err(error) => {
            log::warn!("command refused: {error}");
            -3
        }
    }
}

/// Starts answering a JSON request; the answer arrives as a `reply` event
/// carrying the request's number. Returns 0 when started, -1 for an
/// unreadable request, -2 with no engine.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_request(request_json: *const c_char) -> i32 {
    let Some(Request { request, ask }) = read_json::<Request>(request_json) else {
        return -1;
    };
    let Some((reads, emit)) = state()
        .engine
        .as_ref()
        .map(|engine| (engine.reads.clone(), engine.emit.clone()))
    else {
        return -2;
    };
    RUNTIME.spawn(async move {
        let (ok, error) = match ask.answer(&reads).await {
            Ok(value) => (Some(value), None),
            Err(message) => (None, Some(message)),
        };
        emit(Event::Reply { request, ok, error });
    });
    0
}

/// Shuts the engine down and stops any song a dropped session left
/// playing. Their remaining events carry a generation Swift no longer
/// accepts.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_disconnect() {
    let mut state = state();
    state.generation += 1;
    if let Some(engine) = state.engine.take() {
        engine.shutdown();
    }
    if let Some(carried) = state.carried.take() {
        carried.retire();
    }
}
