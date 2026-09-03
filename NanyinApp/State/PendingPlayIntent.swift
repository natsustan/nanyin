import Foundation

/// A server-resolved play command that was submitted but has not yet been
/// confirmed by a Playing event.
struct PendingPlayIntent: Equatable {
    enum Call: Equatable {
        case context(uri: String, index: Int)
        case tracks(uris: [String], index: Int)
        case trackAt(uri: String, positionMs: UInt32)
        case contextAtTrack(
            uri: String,
            trackURI: String,
            positionMs: UInt32,
            shuffle: Bool,
            repeatContext: Bool,
            repeatTrack: Bool
        )
        case tracksAtTrack(
            uris: [String],
            trackURI: String,
            positionMs: UInt32,
            shuffle: Bool,
            repeatContext: Bool,
            repeatTrack: Bool
        )

        func resumingCurrentTrack(
            uri trackURI: String,
            positionMs: UInt32,
            shuffle: Bool,
            repeatContext: Bool,
            repeatTrack: Bool
        ) -> Self? {
            switch self {
            case let .context(uri, _), let .contextAtTrack(uri, _, _, _, _, _):
                .contextAtTrack(
                    uri: uri,
                    trackURI: trackURI,
                    positionMs: positionMs,
                    shuffle: shuffle,
                    repeatContext: repeatContext,
                    repeatTrack: repeatTrack
                )
            case let .tracks(uris, _), let .tracksAtTrack(uris, _, _, _, _, _):
                .tracksAtTrack(
                    uris: uris,
                    trackURI: trackURI,
                    positionMs: positionMs,
                    shuffle: shuffle,
                    repeatContext: repeatContext,
                    repeatTrack: repeatTrack
                )
            case .trackAt:
                nil
            }
        }
    }

    let call: Call
    let trackURI: String?
    let accountEpoch: Int
    let createdAt: ContinuousClock.Instant
    private(set) var previousPlayRequestID: UInt64
    private(set) var replayed: Bool

    init(
        call: Call,
        trackURI: String?,
        accountEpoch: Int,
        previousPlayRequestID: UInt64,
        createdAt: ContinuousClock.Instant = .now
    ) {
        self.call = call
        self.trackURI = trackURI
        self.accountEpoch = accountEpoch
        self.previousPlayRequestID = previousPlayRequestID
        self.createdAt = createdAt
        replayed = false
    }

    mutating func markReplayedIfEligible(
        accountEpoch: Int,
        previousPlayRequestID: UInt64,
        now: ContinuousClock.Instant = .now,
        lifetime: Duration = .seconds(60)
    ) -> Bool {
        guard !replayed,
              self.accountEpoch == accountEpoch,
              createdAt.duration(to: now) <= lifetime else { return false }
        replayed = true
        self.previousPlayRequestID = previousPlayRequestID
        return true
    }

    func isConfirmed(byPlayingURI uri: String, playRequestID: UInt64) -> Bool {
        playRequestID != CorePlaybackProgress.noPlayRequest
            && playRequestID != previousPlayRequestID
            && (trackURI == nil || trackURI == uri)
    }

    func isEventFromPreviousRequest(playRequestID: UInt64) -> Bool {
        playRequestID != CorePlaybackProgress.noPlayRequest
            && playRequestID == previousPlayRequestID
    }
}
