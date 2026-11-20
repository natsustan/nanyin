//! C ABI for the Swift app. Commands and events are JSON strings so the
//! header stays small and Swift decodes with `Codable`.
//!
//! At most one engine exists. Each `nanyin_connect` starts a new generation
//! and every event carries the generation it belongs to; Swift drops events
//! from any generation but the one it started last.

mod commands;
mod engine;
mod events;
mod queue;
mod reads;

use std::{
    ffi::{CStr, CString, c_char, c_void},
    sync::{LazyLock, Mutex, MutexGuard},
};

use tokio::runtime::Runtime;

use crate::{
    commands::Command,
    engine::{Config, Engine},
    events::Event,
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
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(Mutex::default);
static RUNTIME: LazyLock<Runtime> =
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

fn read_json<T: serde::de::DeserializeOwned>(ptr: *const c_char) -> Option<T> {
    if ptr.is_null() {
        return None;
    }
    let text = unsafe { CStr::from_ptr(ptr) }.to_str().ok()?;
    serde_json::from_str(text).ok()
}

/// Registers the event callback and logging. Call once, before anything else.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_init(callback: EventCallback, context: *mut c_void) {
    let _ = env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("warn,librespot=info,nanyin_core=info"),
    )
    .try_init();
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
    let generation = {
        let mut state = state();
        if let Some(old) = state.engine.take() {
            old.shutdown();
        }
        state.generation += 1;
        state.generation
    };
    RUNTIME.spawn(engine::run(
        config,
        move |event| emit(generation, &event),
        move |engine| {
            let mut state = state();
            if state.generation != generation {
                return Some(engine);
            }
            state.engine = Some(engine);
            None
        },
        move || {
            let mut state = state();
            let current = state.generation == generation;
            if current {
                state.engine = None;
            }
            current
        },
    ));
    generation
}

/// Applies a JSON command to the current engine.
/// Returns 0 on success, -1 for an unreadable command, -2 with no engine,
/// -3 when Spirc refused it (its task has ended).
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_command(command_json: *const c_char) -> i32 {
    let Some(command) = read_json::<Command>(command_json) else {
        return -1;
    };
    let state = state();
    let Some(engine) = &state.engine else {
        return -2;
    };
    match command.apply(engine) {
        Ok(()) => 0,
        Err(error) => {
            log::warn!("command refused: {error}");
            -3
        }
    }
}

/// Shuts the engine down. Its remaining events carry a generation Swift no
/// longer accepts.
#[unsafe(no_mangle)]
pub extern "C" fn nanyin_disconnect() {
    let mut state = state();
    state.generation += 1;
    if let Some(engine) = state.engine.take() {
        engine.shutdown();
    }
}
