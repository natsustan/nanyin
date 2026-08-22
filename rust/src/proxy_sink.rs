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
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use crate::PLAYER_GENERATION;

/// FFI callback for sending audio data to Swift.
type AudioDataCallback = extern "C" fn(*const f32, usize, u64);

/// FFI callback for playback control events.
/// 0 = stop, 1 = start/resume, 2 = clear/flush
type AudioControlCallback = extern "C" fn(u8, u64);

pub const AUDIO_CONTROL_STOP: u8 = 0;
pub const AUDIO_CONTROL_START: u8 = 1;
pub const AUDIO_CONTROL_CLEAR: u8 = 2;

static AUDIO_DATA_CALLBACK: Lazy<Mutex<Option<AudioDataCallback>>> = Lazy::new(|| Mutex::new(None));
static AUDIO_CONTROL_CALLBACK: Lazy<Mutex<Option<AudioControlCallback>>> =
    Lazy::new(|| Mutex::new(None));
static PCM_WRITES: AtomicU64 = AtomicU64::new(0);

pub fn pcm_writes() -> u64 {
    PCM_WRITES.load(Ordering::Relaxed)
}

pub fn register_audio_data_callback(callback: AudioDataCallback) {
    *AUDIO_DATA_CALLBACK.lock().unwrap() = Some(callback);
}

pub fn register_audio_control_callback(callback: AudioControlCallback) {
    *AUDIO_CONTROL_CALLBACK.lock().unwrap() = Some(callback);
}

fn send_control(event: u8, generation: u64) {
    // Copy callback ref before invoking to avoid holding the lock during the call.
    let cb = { *AUDIO_CONTROL_CALLBACK.lock().unwrap() };
    if let Some(callback) = cb {
        callback(event, generation);
    }
}

/// A Sink implementation that forwards audio to Swift via FFI callbacks.
pub struct ProxySink {
    generation: u64,
}

impl ProxySink {
    pub fn new(generation: u64) -> Self {
        Self { generation }
    }

    fn is_current(&self) -> bool {
        accepts_generation(
            PLAYER_GENERATION.load(Ordering::SeqCst),
            self.generation,
        )
    }

    /// Ask the Swift side to flush buffered audio (e.g. on seek/skip).
    pub fn clear_buffer(generation: u64) {
        send_control(AUDIO_CONTROL_CLEAR, generation);
    }
}

fn accepts_generation(current: u64, sink: u64) -> bool {
    current == sink
}

impl Sink for ProxySink {
    fn start(&mut self) -> SinkResult<()> {
        if self.is_current() {
            send_control(AUDIO_CONTROL_START, self.generation);
        }
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        if self.is_current() {
            send_control(AUDIO_CONTROL_STOP, self.generation);
        }
        Ok(())
    }

    fn write(&mut self, packet: AudioPacket, converter: &mut Converter) -> SinkResult<()> {
        if !self.is_current() {
            return Ok(());
        }
        let samples = packet
            .samples()
            .map_err(|e| SinkError::OnWrite(format!("Failed to get samples: {e:?}")))?;

        let samples_f32: Vec<f32> = converter.f64_to_f32(samples).to_vec();
        if !self.is_current() {
            return Ok(());
        }
        PCM_WRITES.fetch_add(1, Ordering::Relaxed);

        // Copy callback ref before invoking — avoids holding lock during call to Swift.
        let cb = { *AUDIO_DATA_CALLBACK.lock().unwrap() };
        if let Some(callback) = cb {
            callback(
                samples_f32.as_ptr(),
                samples_f32.len(),
                self.generation,
            );
        }

        Ok(())
    }
}

pub fn mk_proxy_sink(
    _device: Option<String>,
    _format: AudioFormat,
    generation: u64,
) -> Box<dyn Sink> {
    Box::new(ProxySink::new(generation))
}

#[cfg(test)]
mod tests {
    use super::accepts_generation;

    #[test]
    fn stale_sink_is_fenced_after_player_rebuild() {
        assert!(accepts_generation(7, 7));
        assert!(!accepts_generation(8, 7));
    }
}
