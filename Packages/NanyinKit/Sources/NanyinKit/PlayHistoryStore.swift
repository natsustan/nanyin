import Foundation

/// Merges local playback history with Spotify's `/me/player/recently-played`.
///
/// Spotify does not record playback from librespot clients. Nanyin records
/// local plays once a track has been listened to long enough, and merges them
/// with Spotify's remote history (from phones, web, speakers) without showing
/// the same listen twice.
public enum PlayHistoryMerger {
    /// A play counts after 30 seconds, or halfway through a shorter track,
    /// always requiring at least 1 second.
    public static func countsAfter(durationMs: Int) -> TimeInterval {
        let half = Double(max(durationMs, 0)) / 2000.0
        return max(1.0, min(30.0, half))
    }

    /// Window around a local play within which a remote report of the same
    /// track is considered the same listen (Spotify dates a play at its end,
    /// so a remote report may also follow by up to the track's length).
    private static let samePlayMargin: TimeInterval = 60

    /// Merges local and remote plays, newest first.
    ///
    /// A play reported by both sources within the duplicate window appears once.
    /// Separate plays from the same source remain separate entries. Entries
    /// with unparseable timestamps sort to the end.
    public static func merge(local: [PlayHistory], remote: [PlayHistory]) -> [PlayHistory] {
        var unmatched: [String: [TimeInterval]] = [:]
        var out: [(time: TimeInterval?, play: PlayHistory)] = []
        out.reserveCapacity(local.count + remote.count)

        for play in local {
            let at = parseTimestamp(play.played_at)
            if let at {
                unmatched[play.track.uri, default: []].append(at)
            }
            out.append((at, play))
        }

        // Pair remote reports oldest-first with the earliest matching local play
        // so back-to-back listens of the same song match in order.
        let reports = remote
            .map { (time: parseTimestamp($0.played_at), play: $0) }
            .sorted { ($0.time ?? -.infinity) < ($1.time ?? -.infinity) }

        for (at, play) in reports {
            let lag = Double(max(play.track.duration_ms, 0)) / 1000.0 + samePlayMargin
            if let at,
               var times = unmatched[play.track.uri],
               let matchIndex = times.enumerated()
                   .filter({ _, held in
                       let delta = at - held
                       return delta >= -samePlayMargin && delta <= lag
                   })
                   .min(by: { $0.element < $1.element })?
                   .offset {
                times.remove(at: matchIndex)
                unmatched[play.track.uri] = times
                continue
            }
            out.append((at, play))
        }

        out.sort { lhs, rhs in
            switch (lhs.time, rhs.time) {
            case let (a?, b?): a > b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): false
            }
        }
        return out.map(\.play)
    }

    public static func formatTimestamp(_ date: Date) -> String {
        date.ISO8601Format(.iso8601)
    }

    public static func parseTimestamp(_ text: String) -> TimeInterval? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return date.timeIntervalSince1970
        }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(text) {
            return date.timeIntervalSince1970
        }
        return nil
    }
}

/// Per-account local play history stored as JSON with owner-only permissions.
@MainActor
public final class PlayHistoryStore {
    public static let maxEntries = 500

    public private(set) var plays: [PlayHistory] = []
    private let directory: URL
    private var fileURL: URL?

    public init(directory: URL) {
        self.directory = directory
    }

    public convenience init(bundleID: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(directory: base.appending(path: bundleID))
    }

    public func load(for accountID: String) {
        let safe = accountID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        let url = directory.appending(path: "history-\(String(safe)).json")
        fileURL = url
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PlayHistory].self, from: data)
        else {
            plays = []
            return
        }
        plays = Array(decoded.prefix(Self.maxEntries))
    }

    public func unload() {
        fileURL = nil
        plays = []
    }

    public func record(_ track: Track, at date: Date = .now) {
        guard fileURL != nil else { return }
        let entry = PlayHistory(track: track, played_at: PlayHistoryMerger.formatTimestamp(date))
        plays.insert(entry, at: 0)
        if plays.count > Self.maxEntries {
            plays.removeSubrange(Self.maxEntries ..< plays.count)
        }
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(plays) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path(percentEncoded: false))
    }
}
