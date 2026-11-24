import Foundation
import NanyinKit
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
    enum Repeat {
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

        /// The same point in the track from now on, moving or not.
        func continued(advancing: Bool) -> Position {
            Position(ms: current(), at: .now, advancing: advancing)
        }
    }

    private(set) var track: CoreTrack?
    /// The URI asked for, shown as playing until the core confirms.
    private(set) var requestedURI: String?
    /// The Spotify context currently playing (playlist, album, artist, collection).
    private(set) var contextURI: String?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var position = Position(ms: 0, at: .now, advancing: false)
    private(set) var shuffle = false
    private(set) var repeatMode = Repeat.off
    /// What plays after the current track, as the core last reported it.
    private(set) var upNext = TrackList(rows: [])
    private(set) var volume = Player.savedVolume
    /// Set when another device took playback over.
    private(set) var playingElsewhere = false
    /// Called once per play when the listener has heard enough of the track
    /// for it to count in local play history.
    @ObservationIgnored var onTrackCounted: (CoreTrack) -> Void = { _ in }

    private let session: PlaybackSession
    /// What was playing when the session dropped, when the core could not
    /// keep it. The new session has nothing loaded and ignores Play, so the
    /// next Play loads this instead; it is never replayed on its own.
    @ObservationIgnored private var resumePoint: CoreCommand.Load?
    /// The track the core is loading; it becomes `track` only once loaded.
    @ObservationIgnored private var loadingURI: String?
    @ObservationIgnored private var volumeDrag: (lastSent: Date, pending: Task<Void, Never>?)?
    @ObservationIgnored private var listen = ListenState()

    private static let volumeKey = "PlaybackVolume"
    static var savedVolume: UInt16 {
        let saved = UserDefaults.standard.object(forKey: volumeKey) as? Int
        return UInt16(clamping: saved ?? Int(Double(UInt16.max) * 0.7))
    }

    private let notices: Notices

    init(session: PlaybackSession, notices: Notices) {
        self.notices = notices
        self.session = session
        session.onPlayerEvent = { [weak self] event in self?.handle(event) }
    }

    var playingURI: String? { requestedURI ?? track?.uri }

    // MARK: Commands

    /// Plays `row` within `list`: inside its context (a playlist, album,
    /// artist or Liked Songs, resolved by Spotify) when it has one, otherwise
    /// as the list's own short run of tracks.
    func play(_ row: TrackRow, in list: TrackList) {
        let load: CoreCommand.Load = if let context = list.contextURI {
            .init(contextURI: context, startURI: row.uri)
        } else {
            .init(trackURIs: list.rows.map(\.uri), startURI: row.uri)
        }
        start(load, uri: row.uri, contextURI: list.contextURI)
    }

    func play(contextURI: String, shuffle: Bool? = nil) {
        guard start(.init(contextURI: contextURI, shuffle: shuffle), uri: nil, contextURI: contextURI) else { return }
        if let shuffle { self.shuffle = shuffle }
    }

    func play(trackURI: String) {
        start(.init(trackURIs: [trackURI], startURI: trackURI), uri: trackURI, contextURI: nil)
    }

    /// Maximum number of tracks uploaded directly in a `Load` command;
    /// larger lists always play by Spotify context URI.
    static let maxDirectTrackLoad = 50

    /// Plays a short displayed slice (e.g. a filtered or sorted playlist).
    /// Falls back to `contextURI` when the slice exceeds `maxDirectTrackLoad`
    /// so large playlists are never uploaded as track lists.
    func play(rows: [TrackRow], start row: TrackRow? = nil, contextURI: String? = nil) {
        guard !rows.isEmpty else { return }
        if rows.count > Self.maxDirectTrackLoad, let contextURI {
            start(.init(contextURI: contextURI, startURI: row?.uri), uri: row?.uri, contextURI: contextURI)
            return
        }
        let slice = rows.count > Self.maxDirectTrackLoad ? Array(rows.prefix(Self.maxDirectTrackLoad)) : rows
        let uris = slice.map(\.uri)
        let startURI = row.flatMap { uris.contains($0.uri) ? $0.uri : nil } ?? uris[0]
        start(.init(trackURIs: uris, startURI: startURI), uri: startURI, contextURI: nil)
    }

    @discardableResult
    private func start(_ load: CoreCommand.Load, uri: String?, contextURI: String? = nil) -> Bool {
        guard send(.load(load)) else { return false }
        resumePoint = nil
        requestedURI = uri
        self.contextURI = contextURI
        isLoading = true
        playingElsewhere = false
        return true
    }

    func resume() { setPlaying(true, .play) }
    func pause() { setPlaying(false, .pause) }
    func togglePlayPause() { setPlaying(!isPlaying, .playPause) }

    private func setPlaying(_ playing: Bool, _ command: CoreCommand) {
        guard let track, playing != isPlaying else { return }
        if playing, var resume = resumePoint {
            resume.positionMs = position.current()
            start(resume, uri: track.uri)
            return
        }
        guard send(command) else { return }
        isPlaying = playing
        position = position.continued(advancing: playing)
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
        guard track != nil else { return }
        // After a drop there is nothing to seek in yet: move the resume point.
        guard resumePoint != nil || send(.seek(positionMs: ms)) else { return }
        position = Position(ms: ms, at: .now, advancing: isPlaying)
    }

    /// While a slider drags, the knob follows at once but the core hears at
    /// most every 150 ms; the final value is always sent and saved.
    func setVolume(_ value: UInt16, final: Bool) {
        volume = value
        let now = Date.now
        var drag = volumeDrag ?? (lastSent: .distantPast, pending: nil)
        drag.pending?.cancel()
        if final {
            volumeDrag = nil
            UserDefaults.standard.set(Int(value), forKey: Self.volumeKey)
            send(.volume(value))
        } else if now.timeIntervalSince(drag.lastSent) >= 0.15 {
            volumeDrag = (lastSent: now, pending: nil)
            send(.volume(value))
        } else {
            drag.pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self, self.volumeDrag != nil else { return }
                self.volumeDrag?.lastSent = .now
                self.send(.volume(self.volume))
            }
            volumeDrag = drag
        }
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

    func signOut() {
        resetListen()
        resumePoint = nil
        loadingURI = nil
        requestedURI = nil
        contextURI = nil
        track = nil
        upNext = TrackList(rows: [])
        isPlaying = false
        isLoading = false
        playingElsewhere = false
        position = Position(ms: 0, at: .now, advancing: false)
    }

    @discardableResult
    private func send(_ command: CoreCommand) -> Bool {
        guard let error = session.send(command) else { return true }
        notices.report(error)
        return false
    }

    // MARK: Events

    private func handle(_ event: CoreEvent) {
        switch event {
        case .trackChanged(let track):
            self.track = track
            if requestedURI == track.uri { requestedURI = nil }
            noteTrackChanged(track)
        case .loading(let uri, let ms):
            loadingURI = uri
            isLoading = true
            position = Position(ms: ms, at: .now, advancing: false)
            resetListen()
        case .playing(let uri, let ms):
            resumePoint = nil
            loadingURI = nil
            isPlaying = true
            isLoading = false
            playingElsewhere = false
            if requestedURI == uri { requestedURI = nil }
            position = Position(ms: ms, at: .now, advancing: true)
            notePlaying(uri: uri)
        case .position(_, let ms):
            position = Position(ms: ms, at: .now, advancing: isPlaying)
        case .paused(_, let ms):
            isPlaying = false
            isLoading = false
            position = Position(ms: ms, at: .now, advancing: false)
            noteNotPlaying()
        case .stopped:
            isPlaying = false
            isLoading = false
            requestedURI = nil
            contextURI = nil
            position = position.continued(advancing: false)
            resetListen()
        case .unavailable(let uri):
            if requestedURI == uri { requestedURI = nil }
            notices.report("This song is not available.")
        case .volume(let value):
            // The core echoes what a drag sent; the knob already shows it.
            if volumeDrag == nil {
                volume = value
                UserDefaults.standard.set(Int(value), forKey: Self.volumeKey)
            }
        case .shuffle(let on):
            shuffle = on
        case .repeat(let context, let track):
            repeatMode = track ? .track : context ? .context : .off
        case .queue(let context, let tracks):
            let resolved = context.isEmpty ? nil : context
            contextURI = resolved
            upNext = TrackList(
                rows: tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element) },
                contextURI: resolved)
        case .deactivated:
            resumePoint = nil
            contextURI = nil
            upNext = TrackList(rows: [])
            isPlaying = false
            isLoading = false
            playingElsewhere = true
            position = position.continued(advancing: false)
            noteNotPlaying()
        case .sessionEnded(resuming: true):
            // Our connection dropped and the core kept the song playing;
            // the next session takes it over. Nothing changes here.
            break
        case .sessionEnded(resuming: false):
            // Our connection dropped; another one is on its way.
            holdForNextPlay()
        case .resumeFailed:
            holdForNextPlay()
            notices.report("Couldn't pick up where playback left off. Press Play to continue.")
        case .connected, .connectFailed:
            break
        }
    }

    /// Keeps the track, its context and the position, ready for the next
    /// Play to load again. A drop during a track change leaves the next one
    /// loading: pick up there, from its start.
    private func holdForNextPlay() {
        noteNotPlaying()
        if let track {
            let start = loadingURI ?? track.uri
            resumePoint = if let context = upNext.contextURI {
                .init(contextURI: context, startURI: start, shuffle: shuffle)
            } else {
                .init(trackURIs: [start] + upNext.rows.map(\.uri).filter { $0 != start }, startURI: start)
            }
        }
        loadingURI = nil
        isPlaying = false
        isLoading = false
        requestedURI = nil
        position = position.continued(advancing: false)
    }

    // MARK: Local play counting

    private struct ListenState {
        var uri: String?
        var accumulated: TimeInterval = 0
        var startedAt: Date?
        var recorded = false
        var timer: Task<Void, Never>?
    }

    private func resetListen() {
        listen.timer?.cancel()
        listen = ListenState()
    }

    private func noteTrackChanged(_ track: CoreTrack) {
        listen.timer?.cancel()
        listen = ListenState(uri: track.uri)
        if isPlaying && !isLoading {
            listen.startedAt = .now
            scheduleCountTimer(for: track)
        }
    }

    private func notePlaying(uri: String) {
        if listen.uri != uri {
            listen.timer?.cancel()
            listen = ListenState(uri: uri)
        }
        guard !listen.recorded else { return }
        if listen.startedAt == nil {
            listen.startedAt = .now
        }
        if let track, track.uri == uri, listen.timer == nil {
            scheduleCountTimer(for: track)
        }
    }

    private func noteNotPlaying() {
        listen.timer?.cancel()
        listen.timer = nil
        if let startedAt = listen.startedAt {
            listen.accumulated += max(0, Date.now.timeIntervalSince(startedAt))
            listen.startedAt = nil
        }
    }

    private func scheduleCountTimer(for track: CoreTrack) {
        listen.timer?.cancel()
        let threshold = PlayHistoryMerger.countsAfter(durationMs: track.durationMs)
        let elapsed = listen.accumulated + (listen.startedAt.map { max(0, Date.now.timeIntervalSince($0)) } ?? 0)
        let remaining = threshold - elapsed
        if remaining <= 0 {
            recordCurrentTrack(track)
            return
        }
        let uri = track.uri
        listen.timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self,
                  self.isPlaying, self.listen.uri == uri, !self.listen.recorded,
                  let current = self.track, current.uri == uri
            else { return }
            self.recordCurrentTrack(current)
        }
    }

    private func recordCurrentTrack(_ track: CoreTrack) {
        listen.recorded = true
        listen.timer = nil
        onTrackCounted(track)
    }
}

#if DEBUG
extension Player {
    func showDemo(_ track: CoreTrack, positionMs: Int, upNext: TrackList) {
        self.track = track
        self.upNext = upNext
        isPlaying = true
        position = Position(ms: positionMs, at: .now, advancing: true)
    }
}
#endif
