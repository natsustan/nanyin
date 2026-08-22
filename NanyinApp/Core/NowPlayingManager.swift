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
    private var currentArtworkURL: URL?
    private var currentArtworkImage: NSImage?

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
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: Double(durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Artwork is fetched async and merged (avoid clobbering on every tick).
        let artworkChanged = currentArtworkURL != artworkURL
        if artworkChanged {
            artworkTask?.cancel()
            artworkTask = nil
            currentArtworkURL = artworkURL
            currentArtworkImage = nil
        }
        if let artworkURL {
            if let image = currentArtworkImage
                ?? ArtworkCache.shared.cachedImage(for: artworkURL, targetSize: 640) {
                currentArtworkImage = image
                mergeArtwork(image)
            } else if artworkChanged {
                artworkTask = Task { [weak self] in
                    guard let image = await ArtworkCache.shared.image(
                        for: artworkURL,
                        targetSize: 640
                    ),
                          !Task.isCancelled,
                          self?.currentArtworkURL == artworkURL else { return }
                    self?.currentArtworkImage = image
                    self?.mergeArtwork(image)
                }
            }
        }
    }

    private func mergeArtwork(_ image: NSImage) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        current[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
    }

    func clear() {
        artworkTask?.cancel()
        currentArtworkURL = nil
        currentArtworkImage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
