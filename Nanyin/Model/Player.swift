import Foundation
import Observation

/// What is playing on this Mac, and the controls for it.
///
/// Controls are optimistic: the interface shows the result at once and the
/// core's events confirm it. The playback position is stored as an anchor
/// (position at a moment) so nothing observable changes every second; views
/// that show the time derive it in a `TimelineView`.
@MainActor
@Observable
final class Player {
    enum Repeat: CaseIterable {
        case off, context, track

        var next: Repeat {
            switch self {
            case .off: .context
            case .context: .track
            case .track: .off
            }
        }
    }

    struct Position: Equatable {
        var ms: Int
        var at: Date
        var advancing: Bool

        func current(at now: Date = .now) -> Int {
            advancing ? ms + Int(now.timeIntervalSince(at) * 1000) : ms
        }
    }

    private(set) var track: CoreTrack?
    /// The URI asked for, shown as playing until the core confirms.
    private(set) var requestedURI: String?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var position = Position(ms: 0, at: .now, advancing: false)
    private(set) var shuffle = false
    private(set) var repeatMode = Repeat.off
    private(set) var volume: UInt16
    /// Set when another device took playback over.
    private(set) var playingElsewhere = false
    var lastError: String?

    private let session: PlaybackSession
    private let engine = PlaybackEngine.shared

    init(session: PlaybackSession) {
        self.session = session
        volume = session.volume
        session.onPlayerEvent = { [weak self] event in self?.handle(event) }
    }

    var playingURI: String? { requestedURI ?? track?.uri }

    // MARK: Commands

    /// Plays `startURI` within `contextURI` (a playlist, album, artist or the
    /// Liked Songs collection). Spotify resolves the context server-side.
    func play(contextURI: String, startURI: String? = nil) {
        load(.init(contextURI: contextURI, startURI: startURI), uri: startURI)
    }

    /// Plays a short explicit list of tracks (search results, say).
    func play(trackURIs: [String], startURI: String) {
        load(.init(trackURIs: trackURIs, startURI: startURI), uri: startURI)
    }

    private func load(_ load: CoreCommand.Load, uri: String?) {
        guard send(.load(load)) else { return }
        requestedURI = uri
        isLoading = true
        playingElsewhere = false
    }

    func togglePlayPause() {
        guard track != nil, send(.playPause) else { return }
        isPlaying.toggle()
        position = Position(ms: position.current(), at: .now, advancing: isPlaying)
    }

    func next() { send(.next) }

    /// Like every music player: restarts the track unless it just began.
    func previous() {
        if position.current() > 3000 {
            seek(to: 0)
        } else {
            send(.previous)
        }
    }

    func seek(to ms: Int) {
        guard track != nil, send(.seek(positionMs: ms)) else { return }
        position = Position(ms: ms, at: .now, advancing: isPlaying)
    }

    func setVolume(_ value: UInt16) {
        volume = value
        session.volume = value
        send(.volume(value))
    }

    func toggleShuffle() {
        guard send(.shuffle(!shuffle)) else { return }
        shuffle.toggle()
    }

    func cycleRepeat() {
        let next = repeatMode.next
        guard send(.repeat(context: next != .off, track: next == .track)) else { return }
        repeatMode = next
    }

    func addToQueue(_ uri: String) {
        send(.addToQueue(uri: uri))
    }

    @discardableResult
    private func send(_ command: CoreCommand) -> Bool {
        guard session.isReady, engine.send(command) else {
            lastError = session.isReady
                ? "Playback stopped responding."
                : "Set up playback on this Mac first."
            return false
        }
        return true
    }

    // MARK: Events

    private func handle(_ event: CoreEvent) {
        switch event {
        case .trackChanged(let track):
            self.track = track
            if requestedURI == track.uri { requestedURI = nil }
        case .loading(_, let ms):
            isLoading = true
            position = Position(ms: ms, at: .now, advancing: false)
        case .playing(let uri, let ms):
            isPlaying = true
            isLoading = false
            playingElsewhere = false
            if requestedURI == uri { requestedURI = nil }
            position = Position(ms: ms, at: .now, advancing: true)
        case .paused(_, let ms):
            isPlaying = false
            isLoading = false
            position = Position(ms: ms, at: .now, advancing: false)
        case .stopped:
            isPlaying = false
            isLoading = false
            requestedURI = nil
            position = Position(ms: position.current(), at: .now, advancing: false)
        case .unavailable(let uri):
            if requestedURI == uri { requestedURI = nil }
            lastError = "This song is not available."
        case .volume(let value):
            volume = value
            session.volume = value
        case .shuffle(let on):
            shuffle = on
        case .repeat(let context, let track):
            repeatMode = track ? .track : context ? .context : .off
        case .deactivated:
            isPlaying = false
            isLoading = false
            playingElsewhere = true
            position = Position(ms: position.current(), at: .now, advancing: false)
        default:
            break
        }
    }
}
