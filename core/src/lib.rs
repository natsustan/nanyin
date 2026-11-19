//! C ABI for the Swift app. Commands and events are JSON strings so the
//! header stays small and Swift decodes with `Codable`.
//!
//! At most one engine exists. Each `nanyin_connect` starts a new generation;
//! events from an older generation are dropped, so a replaced engine can
//! never speak for the current one.

mod commands;
mod engine;
mod events;

use std::{
    ffi::{CStr, CString, c_char, c_void},
    sync::{LazyLock, Mutex, MutexGuard},
};

use tokio::runtime::Runtime;

use crate::{
    commands::Command,
    engine::{CONNECT_TIMEOUT, Config, Engine, Failure},
    events::{Event, FailureReason},
};

pub type EventCallback = extern "C" fn(context: *mut c_void, generation: u64, json: *const c_char);

struct Listener {
    callback: EventCallback,
    context: Context,
}

/// Swift's context pointer. Swift keeps it alive for the whole process and
/// accepts callbacks on any thread.
#[derive(Clone, Copy)]
struct Context(*mut c_void);
unsafe impl Send for Context {}

#[derive(Default)]
struct State {
    listener: Option<Listener>,
    generation: u64,
    engine: Option<Engine>,
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(Mutex::default);
static RUNTIME: LazyLock<Runtime> =
    LazyLock::new(|| Runtime::new().expect("unable to start the tokio runtime"));

fn state() -> MutexGuard<'static, State> {
    STATE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Delivers `event` if `generation` is still current. The callback runs
/// without the lock held, so Swift may call back in; it also receives the
/// generation and drops anything older than the engine it started last.
fn emit(generation: u64, event: &Event) {
    let (callback, context) = {
        let state = state();
        match &state.listener {
            Some(listener) if state.generation == generation => {
                (listener.callback, listener.context.0)
            }
            _ => return,
        }
    };
    let Some(json) = serde_json::to_string(event)
        .ok()
        .and_then(|json| CString::new(json).ok())
    else {
        return;
    };
    callback(context, generation, json.as_ptr());
}

fn read_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

/// Registers the event callback and logging. Call once, before anything else.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_init(callback: EventCallback, context: *mut c_void) {
    let _ = env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("warn,librespot=info,nanyin_core=info"),
    )
    .try_init();
    state().listener = Some(Listener {
        callback,
        context: Context(context),
    });
}

/// Starts a new engine from `config_json`, replacing any current one.
/// Returns the generation its events will carry, or 0 for invalid config.
/// The outcome arrives as a `connected` or `connect_failed` event.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_connect(config_json: *const c_char) -> u64 {
    let Some(config) = read_str(config_json).and_then(|s| serde_json::from_str::<Config>(s).ok())
    else {
        return 0;
    };
    let generation = {
        let mut state = state();
        if let Some(old) = state.engine.take() {
            old.shutdown();
        }
        state.generation += 1;
        state.generation
    };
    RUNTIME.spawn(async move {
        let started = tokio::time::timeout(
            CONNECT_TIMEOUT,
            Engine::start(config, move |event| emit(generation, &event)),
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
            Err(failure) => {
                emit(
                    generation,
                    &Event::ConnectFailed {
                        reason: failure.reason,
                        message: failure.message,
                    },
                );
                return;
            }
        };
        let connected = Event::Connected {
            username: engine.session.username(),
            credentials: engine.credentials_json(),
        };
        let stale = {
            let mut state = state();
            if state.generation == generation {
                state.engine = Some(engine);
                None
            } else {
                Some(engine)
            }
        };
        if let Some(engine) = stale {
            engine.shutdown();
            task.await;
            return;
        }
        emit(generation, &connected);
        task.await;
        // Clear the engine only if it is still ours, then report the end.
        let ended = {
            let mut state = state();
            let current = state.generation == generation;
            if current {
                state.engine = None;
            }
            current
        };
        if ended {
            emit(generation, &Event::SessionEnded);
        }
    });
    generation
}

/// Applies a JSON command to the current engine.
/// Returns 0 on success, -1 for an unreadable command, -2 with no engine,
/// -3 when Spirc refused it (its task has ended).
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_command(command_json: *const c_char) -> i32 {
    let Some(command) =
        read_str(command_json).and_then(|s| serde_json::from_str::<Command>(s).ok())
    else {
        return -1;
    };
    let state = state();
    let Some(engine) = &state.engine else {
        return -2;
    };
    match command.apply(&engine.spirc) {
        Ok(()) => 0,
        Err(error) => {
            log::warn!("command refused: {error}");
            -3
        }
    }
}

/// Shuts the engine down. No further events arrive for its generation.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_disconnect() {
    let mut state = state();
    state.generation += 1;
    if let Some(engine) = state.engine.take() {
        engine.shutdown();
    }
}
