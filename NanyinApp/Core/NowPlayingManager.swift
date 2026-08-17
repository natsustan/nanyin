//
//  NowPlayingManager.swift
//  Nanyin
//

import AppKit
import AVFoundation
import MediaPlayer

/// System media integration: media keys, Control Center / lock screen.
/// macOS media-key events arrive through MPRemoteCommandCenter once we
/// become the "now playing" app via MPNowPlayingInfoCenter.
@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var registered = false
    private var artworkTask: Task<Void, Never>?

    private init() {}

    func activate() {
        guard !registered else { return }
        registered = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.handler { $0.togglePlay() } == true ? .success : .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handler { $0.togglePlay() } == true ? .success : .commandFailed
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handler { $0.togglePlay() } == true ? .success : .commandFailed
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.handler { $0.next() } == true ? .success : .commandFailed
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.handler { $0.prev() } == true ? .success : .commandFailed
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent, let self else {
                return .commandFailed
            }
            return self.handler { app in
                let fraction = posEvent.positionTime / Double(max(app.durationMs, 1))
                app.seek(to: min(max(fraction, 0), 1))
            } == true ? .success : .commandFailed
        }
    }

    /// Runs the action against the AppModel on the main actor.
    private func handler(_ action: @MainActor (AppModel) -> Void) -> Bool {
        guard let app = AppDelegate.shared?.appModel else { return false }
        action(app)
        return true
    }

    // MARK: - Info center updates

    func updateNowPlaying(
        title: String,
        artist: String,
        album: String,
        durationMs: UInt32,
        positionMs: UInt32,
        isPlaying: Bool,
        artworkURL: URL?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: Double(durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Artwork is fetched async and merged (avoid clobbering on every tick).
        if let artworkURL {
            let key = artworkURL.absoluteString
            if MediaArtworkCache.shared[key] == nil {
                artworkTask?.cancel()
                artworkTask = Task { [weak self] in
                    if let image = await MediaArtworkCache.shared.fetch(key, url: artworkURL) {
                        self?.mergeArtwork(image, into: &info)
                    }
                }
            } else if let image = MediaArtworkCache.shared[key] {
                mergeArtwork(image, into: &info)
            }
        }
    }

    private func mergeArtwork(_ image: NSImage, into info: inout [String: Any]) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        current[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

/// Tiny process-lifetime image cache for now-playing artwork.
@MainActor
final class MediaArtworkCache {
    static let shared = MediaArtworkCache()
    private var cache: [String: NSImage] = [:]
    private init() {}

    subscript(key: String) -> NSImage? {
        cache[key]
    }

    func fetch(_ key: String, url: URL) async -> NSImage? {
        if let cached = cache[key] { return cached }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data)
        else { return nil }
        cache[key] = image
        return image
    }
}
