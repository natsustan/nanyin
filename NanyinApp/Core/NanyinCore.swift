//
//  NanyinCore.swift
//  Nanyin
//

import Foundation
import NanyinCore

/// Swift wrapper around the Rust nanyin_core FFI.
/// Callback storage is nonisolated (Rust invokes us on background threads);
/// events hop to the MainActor via Task.
enum Core {
    /// Playback event delivered from Rust as JSON.
    enum Event {
        case loading(uri: String, positionMs: Int)
        case playing(uri: String, positionMs: Int)
        case paused(uri: String, positionMs: Int)
        case stopped(uri: String)
        case position(positionMs: Int)
        case trackChanged(
            uri: String,
            durationMs: Int,
            title: String?,
            artists: String?,
            album: String?,
            coverURL: String?
        )
        case shuffleChanged(Bool)
        case repeatChanged(context: Bool, track: Bool)
        case endOfTrack
    }

    nonisolated(unsafe) static var onEvent: (@MainActor (Event) -> Void)?
    nonisolated(unsafe) static var onConnected: (@MainActor () -> Void)?
    nonisolated(unsafe) static var onDisconnected: (@MainActor () -> Void)?
    nonisolated(unsafe) static var onAudioData: ((UnsafePointer<Float>, Int) -> Void)?
    nonisolated(unsafe) static var onAudioControl: ((UInt8) -> Void)?

    // MARK: - Callback registration

    nonisolated(unsafe) private static var registered = false

    static func installCallbacks() {
        guard !registered else { return }
        registered = true

        nanyin_register_audio_data_callback { samples, count in
            guard let samples else { return }
            if let handler = Core.onAudioData {
                handler(samples, count)
            }
        }
        nanyin_register_audio_control_callback { event in
            if let handler = Core.onAudioControl {
                handler(event)
            }
        }
        nanyin_register_playback_state_callback { json in
            guard let json = json.map(String.init(cString:)) else { return }
            Core.handleStateJSON(json)
        }
        nanyin_register_session_connected_callback {
            Task { @MainActor in Core.onConnected?() }
        }
        nanyin_register_session_disconnected_callback {
            Task { @MainActor in Core.onDisconnected?() }
        }
    }

    nonisolated private static func handleStateJSON(_ json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = object["event"] as? String
        else { return }

        let uri = object["track_uri"] as? String ?? ""
        let position = object["position_ms"] as? Int ?? 0
        let duration = object["duration_ms"] as? Int ?? 0

        let event: Event
        switch eventName {
        case "loading": event = .loading(uri: uri, positionMs: position)
        case "playing": event = .playing(uri: uri, positionMs: position)
        case "paused": event = .paused(uri: uri, positionMs: position)
        case "stopped": event = .stopped(uri: uri)
        case "position": event = .position(positionMs: position)
        case "track_changed":
            event = .trackChanged(
                uri: uri,
                durationMs: duration,
                title: object["title"] as? String,
                artists: object["artists"] as? String,
                album: object["album"] as? String,
                coverURL: object["cover_url"] as? String
            )
        case "end_of_track": event = .endOfTrack
        case "shuffle_changed": event = .shuffleChanged(object["shuffle"] as? Bool ?? false)
        case "repeat_changed":
            event = .repeatChanged(
                context: object["repeat_context"] as? Bool ?? false,
                track: object["repeat_track"] as? Bool ?? false
            )
        default: return
        }

        Task { @MainActor in
            Core.onEvent?(event)
        }
    }

    // MARK: - FFI calls

    /// Serial queue for nanyin_init_player: the call blocks for the full
    /// dealer handshake (bounded by the Rust-side PLAYER_INIT_TIMEOUT).
    /// Never run it on the main thread — a risk-control accesspoint stall
    /// (observed 95s+) would freeze the whole app. Serial, not concurrent:
    /// overlapping inits would race the core's stale-state teardown.
    private static let initQueue = DispatchQueue(
        label: "com.nanyin.core.init", qos: .userInitiated
    )

    nonisolated static func initializePlayer(accessToken: String, deviceId: String) async -> Int32 {
        await withCheckedContinuation { cont in
            initQueue.async {
                cont.resume(
                    returning: initializePlayerBlocking(
                        accessToken: accessToken, deviceId: deviceId
                    )
                )
            }
        }
    }

    nonisolated private static func initializePlayerBlocking(
        accessToken: String, deviceId: String
    ) -> Int32 {
        installCallbacks()
        return accessToken.withCString { token in
            deviceId.withCString { nanyin_init_player(token, $0) }
        }
    }

    nonisolated static func playTracks(_ uris: [String], startIndex: Int = 0) -> Int32 {
        guard let data = try? JSONSerialization.data(withJSONObject: uris),
              let json = String(data: data, encoding: .utf8)
        else { return -1 }
        return json.withCString { nanyin_play_tracks($0, UInt32(startIndex)) }
    }

    nonisolated static func playContext(_ uri: String, startIndex: Int = 0) -> Int32 {
        uri.withCString { nanyin_play_context($0, UInt32(startIndex)) }
    }

    nonisolated static func pause() -> Int32 { nanyin_pause() }
    nonisolated static func resume() -> Int32 { nanyin_resume() }
    nonisolated static func stop() -> Int32 { nanyin_stop() }
    nonisolated static func next() -> Int32 { nanyin_next() }
    nonisolated static func prev() -> Int32 { nanyin_prev() }
    nonisolated static func seek(_ positionMs: UInt32) -> Int32 { nanyin_seek(positionMs) }
    nonisolated static func setVolume(_ volume: UInt16) -> Int32 { nanyin_set_volume(volume) }
    nonisolated static func setShuffle(_ on: Bool) -> Int32 { nanyin_shuffle(on) }
    nonisolated static func setRepeat(_ on: Bool) -> Int32 { nanyin_repeat(on) }
    nonisolated static func setRepeatTrack(_ on: Bool) -> Int32 { nanyin_repeat_track(on) }
    nonisolated static func addToQueue(_ uri: String) -> Int32 {
        uri.withCString { nanyin_add_to_queue($0) }
    }

    nonisolated static var isPlaying: Bool { nanyin_is_playing() == 1 }
    nonisolated static var positionMs: UInt32 { nanyin_get_position_ms() }
    nonisolated static var durationMs: UInt32 { nanyin_get_duration_ms() }

    /// Last error message from the Rust core (nil when none). Frees the C string.
    nonisolated static func lastErrorMessage() -> String? {
        guard let ptr = nanyin_last_error() else { return nil }
        defer { nanyin_free_string(ptr) }
        return String(cString: ptr)
    }
}
