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
    private var artworkTask: Task<Void, Never>?

    init(player: Player) {
        self.player = player
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, (Player) -> Void)] = [
            (center.playCommand, { $0.resume() }),
            (center.pauseCommand, { $0.pause() }),
            (center.togglePlayPauseCommand, { $0.togglePlayPause() }),
            (center.nextTrackCommand, { $0.next() }),
            (center.previousTrackCommand, { $0.previous() }),
        ]
        for (command, action) in commands {
            command.addTarget { [weak self] _ in self?.run(action) ?? .commandFailed }
        }
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
        if track.coverURL != artworkURL { loadArtwork(track.coverURL) }
        let position = player.position
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: Double(track.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(position.current()) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: position.advancing ? 1.0 : 0.0,
        ]
        info[MPMediaItemPropertyArtwork] = artwork
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }

    /// Fetches the cover once per track change and adds it when it arrives.
    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        artworkURL = url
        artwork = nil
        guard let url else { return }
        artworkTask = Task {
            guard let image = await ImageLoader.shared.image(url), !Task.isCancelled else { return }
            artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }
}
