import Foundation

struct LocalPlaybackSnapshot: Codable, Equatable {
    private static let restartThresholdMs: UInt32 = 5_000

    let accountID: String
    let uri: String
    let title: String
    let artist: String
    let album: String
    let albumId: String?
    let artworkURL: URL?
    let durationMs: UInt32
    let positionMs: UInt32

    var playablePositionMs: UInt32 {
        guard durationMs > 0 else { return positionMs }
        let positionMs = min(positionMs, durationMs)
        let thresholdMs = min(Self.restartThresholdMs, durationMs)
        return durationMs - positionMs <= thresholdMs ? 0 : positionMs
    }

    func withPosition(_ positionMs: UInt32) -> LocalPlaybackSnapshot {
        LocalPlaybackSnapshot(
            accountID: accountID,
            uri: uri,
            title: title,
            artist: artist,
            album: album,
            albumId: albumId,
            artworkURL: artworkURL,
            durationMs: durationMs,
            positionMs: positionMs
        )
    }
}

enum LocalPlaybackRestoreState: Equatable {
    case idle(LocalPlaybackSnapshot)
    case starting(LocalPlaybackSnapshot)

    enum PlayingDisposition: Equatable {
        case ignore
        case confirmRestore
        case discardRestore
    }

    var snapshot: LocalPlaybackSnapshot {
        switch self {
        case let .idle(snapshot), let .starting(snapshot): snapshot
        }
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    static func canApplySnapshot(
        hasNowPlaying: Bool,
        playRequestID: UInt64
    ) -> Bool {
        !hasNowPlaying && playRequestID == CorePlaybackProgress.noPlayRequest
    }

    func playingDisposition(
        isCurrentRequest: Bool,
        confirmsRestore: Bool
    ) -> PlayingDisposition {
        guard isCurrentRequest else { return .ignore }
        if isStarting, confirmsRestore { return .confirmRestore }
        return .discardRestore
    }
}

enum LocalPlaybackOwnership: Equatable {
    case current(requestID: UInt64)
    case expectingSuccessor(previousRequestID: UInt64)

    var currentRequestID: UInt64? {
        switch self {
        case let .current(requestID), let .expectingSuccessor(requestID):
            requestID
        }
    }

    func expectingSuccessor(after requestID: UInt64) -> LocalPlaybackOwnership {
        guard requestID != CorePlaybackProgress.noPlayRequest else { return self }
        switch self {
        case let .current(currentRequestID) where currentRequestID == requestID:
            return .expectingSuccessor(previousRequestID: currentRequestID)
        case let .expectingSuccessor(previousRequestID) where previousRequestID == requestID:
            return self
        default:
            return self
        }
    }

    func confirmingPlaying(requestID: UInt64) -> LocalPlaybackOwnership? {
        guard requestID != CorePlaybackProgress.noPlayRequest else { return nil }
        switch self {
        case let .current(currentRequestID):
            return currentRequestID == requestID ? self : nil
        case let .expectingSuccessor(previousRequestID):
            return previousRequestID == requestID ? nil : .current(requestID: requestID)
        }
    }
}

enum LocalPlaybackStore {
    private static let key = "localPlaybackSnapshot.v1"

    static func load(
        for accountID: String,
        from defaults: UserDefaults = .standard
    ) -> LocalPlaybackSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(LocalPlaybackSnapshot.self, from: data),
              snapshot.accountID == accountID,
              snapshot.uri.hasPrefix("spotify:track:") else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return snapshot
    }

    static func save(
        _ snapshot: LocalPlaybackSnapshot,
        to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
