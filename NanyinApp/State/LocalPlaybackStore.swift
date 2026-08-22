import Foundation

struct LocalPlaybackSnapshot: Codable, Equatable {
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
        durationMs == 0 ? positionMs : min(positionMs, durationMs)
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

    var snapshot: LocalPlaybackSnapshot {
        switch self {
        case let .idle(snapshot), let .starting(snapshot): snapshot
        }
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
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
