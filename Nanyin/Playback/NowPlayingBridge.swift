import AppKit
import MediaPlayer
import Observation

/// Mirrors the player into Control Center and the lock screen, and takes
/// the media keys and headphone buttons from there.
@MainActor
final class NowPlayingBridge {
    private let player: Player
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    init(player: Player) {
        self.player = player
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.run { $0.resume() } ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.run { $0.pause() } ?? .commandFailed }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.togglePlayPause() } ?? .commandFailed }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.next() } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previous() } ?? .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.run { $0.seek(to: Int(event.positionTime * 1000)) } ?? .commandFailed
        }
        observe()
    }

    private func run(_ action: (Player) -> Void) -> MPRemoteCommandHandlerStatus {
        guard player.track != nil else { return .noActionableNowPlayingItem }
        action(player)
        return .success
    }

    /// Re-publishes whenever anything it reads changes.
    private func observe() {
        withObservationTracking {
            publish()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func publish() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = player.track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        let position = player.position
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: Double(track.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(position.current()) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: position.advancing ? 1.0 : 0.0,
        ]
        if track.coverURL == artworkURL, let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else {
            loadArtwork(track.coverURL)
        }
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL?) {
        artworkURL = url
        artwork = nil
        guard let url else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data), url == artworkURL
            else { return }
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
