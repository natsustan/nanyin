#ifndef NANYIN_CORE_H
#define NANYIN_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Error codes returned by most functions:
//   0  = success
//  -1  = general error
//  -2  = session disconnected
//  -3  = session not ready — retry after the connected callback
//  -4  = credentials rejected — refresh the playback token once

// === Lifecycle ===

/// Initializes session + player + Spotify Connect with an OAuth access token
/// (obtained by Swift via PKCE with the keymaster client id).
/// Initializes session + player + Spotify Connect.
/// device_id: STABLE per-install identifier (persist by the caller). A fresh
/// pid-based id every launch floods connect-state with zombie devices and
/// gets the account throttled (dealer goes silent, spirc dies at ~33s).
int32_t nanyin_init_player(
    const char* access_token,
    const char* device_id,
    uint64_t callback_generation
);

/// Shuts down Spirc and the session (call on app quit).
int32_t nanyin_shutdown(void);

// === Playback ===

/// Plays the given track URIs (JSON array: ["spotify:track:...", ...]),
/// starting playback at start_index (0-based index into the array).
/// For large contexts prefer nanyin_play_context (server-side resolution).
int32_t nanyin_play_tracks(const char* track_uris_json, uint32_t start_index);

/// Plays one track from a locally restored position.
int32_t nanyin_play_track_at(const char* track_uri, uint32_t position_ms);

/// Plays a server-resolved context URI (e.g. "spotify:playlist:...",
/// "spotify:user:<name>:collection" for Liked Songs) starting at start_index.
int32_t nanyin_play_context(const char* context_uri, uint32_t start_index);

int32_t nanyin_pause(void);
int32_t nanyin_resume(void);
int32_t nanyin_stop(void);
int32_t nanyin_next(void);
int32_t nanyin_prev(void);
int32_t nanyin_seek(uint32_t position_ms);
int32_t nanyin_set_volume(uint16_t volume);
/// Applies volume locally without publishing a Spotify Connect update.
int32_t nanyin_set_local_volume(uint16_t volume);
int32_t nanyin_shuffle(bool on);
int32_t nanyin_repeat(bool on);
int32_t nanyin_repeat_track(bool on);

/// Appends a track (spotify:track:...) to the active queue.
int32_t nanyin_add_to_queue(const char* track_uri);

/// 1 if playing, 0 otherwise.
int32_t nanyin_is_playing(void);

/// Current playback position in ms (interpolated while playing).
uint32_t nanyin_get_position_ms(void);

/// Current local mixer volume (0–65535).
uint16_t nanyin_get_volume(void);

/// Last error message from a failed call, or NULL.
/// Caller must free the returned string with nanyin_free_string.
char* nanyin_last_error(void);

/// Duration of the current track in ms (0 if unknown).
uint32_t nanyin_get_duration_ms(void);

/// Read-only monotonic progress metrics used by the local audio watchdog.
uint64_t nanyin_get_play_request_id(void);
uint64_t nanyin_get_decoder_packets(void);
uint64_t nanyin_get_pcm_writes(void);
uint64_t nanyin_get_download_waiters(void);
uint32_t nanyin_get_confirmed_position_ms(void);

// === Callbacks ===
// All callbacks fire on background threads — Swift side must be thread-safe.

/// Raw PCM from the decoder: 44100 Hz, stereo, Float32, interleaved.
typedef void (*NanyinAudioDataCallback)(
    const float* samples,
    size_t sample_count,
    uint64_t player_generation
);
void nanyin_register_audio_data_callback(NanyinAudioDataCallback callback);

/// Audio control events: 0 = stop, 1 = start/resume, 2 = clear/flush.
typedef void (*NanyinAudioControlCallback)(uint8_t event, uint64_t player_generation);
void nanyin_register_audio_control_callback(NanyinAudioControlCallback callback);

/// Playback state updates as JSON:
/// {"event":"loading|playing|paused|stopped|position|track_changed|end_of_track",
///  "track_uri":..., "position_ms":..., "duration_ms":...}
typedef void (*NanyinPlaybackStateCallback)(const char* state_json, uint64_t generation);
void nanyin_register_playback_state_callback(NanyinPlaybackStateCallback callback);

/// Fired once the session + Spirc are ready for commands.
typedef void (*NanyinSessionConnectedCallback)(uint64_t generation);
void nanyin_register_session_connected_callback(NanyinSessionConnectedCallback callback);

/// Fired when the session drops (idle timeout, network loss, revoke).
/// Swift should re-init with the current token first. Refresh only when
/// nanyin_init_player explicitly returns -4 (credentials rejected).
typedef void (*NanyinSessionDisconnectedCallback)(uint64_t generation);
void nanyin_register_session_disconnected_callback(NanyinSessionDisconnectedCallback callback);

/// Frees a C string allocated by this library.
void nanyin_free_string(char* s);

#ifdef __cplusplus
}
#endif

#endif /* NANYIN_CORE_H */
