//! Proxy Audio Sink
//!
//! Forwards decoded PCM audio from librespot to Swift via FFI callbacks.
//! Swift handles actual output via AVAudioEngine.
//!
//! Audio format: 44100 Hz, 2 channels (stereo), Float32, interleaved.
//!
//! Adapted from NullSpot's proxy_sink (MIT, michaelh03/NullSpot).

use librespot_playback::audio_backend::{Sink, SinkError, SinkResult};
use librespot_playback::config::AudioFormat;
use librespot_playback::convert::Converter;
use librespot_playback::decoder::AudioPacket;
use once_cell::sync::Lazy;
use std::sync::Mutex;

/// FFI callback for sending audio data to Swift.
type AudioDataCallback = extern "C" fn(*const f32, usize);

/// FFI callback for playback control events.
/// 0 = stop, 1 = start/resume, 2 = clear/flush
type AudioControlCallback = extern "C" fn(u8);

pub const AUDIO_CONTROL_STOP: u8 = 0;
pub const AUDIO_CONTROL_START: u8 = 1;
pub const AUDIO_CONTROL_CLEAR: u8 = 2;

// Reserved for seek/skip flush wiring in M2.
#[allow(dead_code)]
pub const AUDIO_CONTROL_CLEAR_REF: u8 = AUDIO_CONTROL_CLEAR;

static AUDIO_DATA_CALLBACK: Lazy<Mutex<Option<AudioDataCallback>>> = Lazy::new(|| Mutex::new(None));
static AUDIO_CONTROL_CALLBACK: Lazy<Mutex<Option<AudioControlCallback>>> =
    Lazy::new(|| Mutex::new(None));

pub fn register_audio_data_callback(callback: AudioDataCallback) {
    *AUDIO_DATA_CALLBACK.lock().unwrap() = Some(callback);
}

pub fn register_audio_control_callback(callback: AudioControlCallback) {
    *AUDIO_CONTROL_CALLBACK.lock().unwrap() = Some(callback);
}

fn send_control(event: u8) {
    // Copy callback ref before invoking to avoid holding the lock during the call.
    let cb = { *AUDIO_CONTROL_CALLBACK.lock().unwrap() };
    if let Some(callback) = cb {
        callback(event);
    }
}

/// A Sink implementation that forwards audio to Swift via FFI callbacks.
pub struct ProxySink;

#[allow(dead_code)]
impl ProxySink {
    /// Ask the Swift side to flush buffered audio (e.g. on seek/skip).
    pub fn clear_buffer() {
        send_control(AUDIO_CONTROL_CLEAR);
    }
}

impl Sink for ProxySink {
    fn start(&mut self) -> SinkResult<()> {
        send_control(AUDIO_CONTROL_START);
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        send_control(AUDIO_CONTROL_STOP);
        Ok(())
    }

    fn write(&mut self, packet: AudioPacket, converter: &mut Converter) -> SinkResult<()> {
        let samples = packet
            .samples()
            .map_err(|e| SinkError::OnWrite(format!("Failed to get samples: {e:?}")))?;

        let samples_f32: Vec<f32> = converter.f64_to_f32(samples).to_vec();

        // Copy callback ref before invoking — avoids holding lock during call to Swift.
        let cb = { *AUDIO_DATA_CALLBACK.lock().unwrap() };
        if let Some(callback) = cb {
            callback(samples_f32.as_ptr(), samples_f32.len());
        }

        Ok(())
    }
}

pub fn mk_proxy_sink(_device: Option<String>, _format: AudioFormat) -> Box<dyn Sink> {
    Box::new(ProxySink)
}
