import CryptoKit
import Foundation

/// One line of lyrics, optionally timed to its start position in milliseconds.
public struct LyricsLine: Codable, Sendable, Hashable {
    public let startTimeMs: Int?
    public let text: String

    public init(startTimeMs: Int? = nil, text: String) {
        self.startTimeMs = startTimeMs
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case startTimeMs = "start_time_ms"
        case text
    }
}

/// Lyrics for a track, from Spotify's `color-lyrics` service or LRCLIB.
public struct Lyrics: Codable, Sendable, Hashable {
    public let lines: [LyricsLine]
    public let synced: Bool
    public let instrumental: Bool
    public let source: String

    public init(lines: [LyricsLine], synced: Bool, instrumental: Bool = false, source: String) {
        self.lines = lines
        self.synced = synced
        self.instrumental = instrumental
        self.source = source
    }

    /// Index of the line active at `positionMs`, or `nil` before the first line
    /// or when the lyrics have no timestamps.
    public func activeLineIndex(at positionMs: Int) -> Int? {
        guard synced, !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if let start = lines[mid].startTimeMs, start <= positionMs {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low > 0 ? low - 1 : nil
    }

    /// Parses standard `[mm:ss.xx]` / `[mm:ss.xxx]` / `[mm:ss]` LRC lyrics.
    public static func parseLRC(_ raw: String, source: String = "LRCLIB") -> Lyrics? {
        var parsed: [LyricsLine] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            var remaining = Substring(rawLine).trimmingCharacters(in: .whitespaces)
            var timestamps: [Int] = []
            while remaining.hasPrefix("["), let close = remaining.firstIndex(of: "]") {
                let tag = String(remaining[remaining.index(after: remaining.startIndex) ..< close])
                guard let ms = parseLRCTimestamp(tag) else { break }
                timestamps.append(ms)
                remaining = String(remaining[remaining.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !timestamps.isEmpty else { continue }
            let text = remaining.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text != "\u{266A}" else { continue }
            for ms in timestamps {
                parsed.append(LyricsLine(startTimeMs: ms, text: text))
            }
        }
        guard !parsed.isEmpty else { return nil }
        parsed.sort { ($0.startTimeMs ?? 0) < ($1.startTimeMs ?? 0) }
        return Lyrics(lines: parsed, synced: true, instrumental: false, source: source)
    }

    public static func parsePlain(_ raw: String, source: String = "LRCLIB") -> Lyrics? {
        let lines = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "\u{266A}" }
            .map { LyricsLine(startTimeMs: nil, text: $0) }
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines, synced: false, instrumental: false, source: source)
    }

    private static func parseLRCTimestamp(_ tag: String) -> Int? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        let secParts = parts[1].split(separator: ".", maxSplits: 1)
        guard let seconds = Int(secParts[0]), seconds >= 0, seconds < 60 else { return nil }
        var millis = 0
        if secParts.count == 2 {
            let frac = secParts[1]
            guard !frac.isEmpty, frac.allSatisfy(\.isNumber) else { return nil }
            let digits = String(frac.prefix(3))
            guard let rawFrac = Int(digits) else { return nil }
            switch digits.count {
            case 1: millis = rawFrac * 100
            case 2: millis = rawFrac * 10
            default: millis = rawFrac
            }
        }
        return (minutes * 60 + seconds) * 1000 + millis
    }
}

/// Track metadata used for LRCLIB fallback lookups.
public struct LyricsQuery: Sendable, Hashable {
    public let trackURI: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationMs: Int

    public init(trackURI: String, title: String, artist: String, album: String, durationMs: Int) {
        self.trackURI = trackURI
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}

public enum LRCLIBError: Error, LocalizedError, Equatable {
    case rateLimited
    case serverError(Int)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .rateLimited: "LRCLIB is temporarily busy. Try again in a moment."
        case .serverError(let code): "LRCLIB answered HTTP \(code)."
        case .invalidURL: "Could not build lyrics request URL."
        }
    }
}

/// Fetches synced or plain lyrics from [LRCLIB](https://lrclib.net) as a
/// fallback when Spotify has no lyrics for a track.
public struct LRCLIBClient: Sendable {
    private let transport: HTTPTransport
    private let baseURL: String

    public init(transport: HTTPTransport = .shared, baseURL: String = "https://lrclib.net/api") {
        self.transport = transport
        self.baseURL = baseURL
    }

    public init(session: URLSession, baseURL: String = "https://lrclib.net/api") {
        self.transport = HTTPTransport(session: session)
        self.baseURL = baseURL
    }

    public func fetch(_ query: LyricsQuery) async throws -> Lyrics? {
        let rawTitle = query.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = Self.cleanTitle(rawTitle)
        let title = cleaned.isEmpty ? rawTitle : cleaned
        let artist = query.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        var exactItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
        ]
        let album = query.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !album.isEmpty {
            exactItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if query.durationMs > 0 {
            exactItems.append(URLQueryItem(name: "duration", value: "\(query.durationMs / 1000)"))
        }

        if let exact: Record = try await get("/get", queryItems: exactItems),
           let lyrics = exact.toLyrics() {
            return lyrics
        }

        let searchItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
        ]
        let candidates: [Record] = (try await get("/search", queryItems: searchItems)) ?? []
        return Self.pickBest(candidates, durationMs: query.durationMs)
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T? {
        guard var components = URLComponents(string: baseURL + path) else {
            throw LRCLIBError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw LRCLIBError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Nanyin/1.0 (https://github.com/natsustan/nanyin)", forHTTPHeaderField: "User-Agent")
        let session = try transport.currentSession()
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        if status == 429 { throw LRCLIBError.rateLimited }
        guard (200 ..< 300).contains(status) else {
            throw LRCLIBError.serverError(status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Strips common edition suffixes like "(Remastered 2011)" or " - Single Version".
    static func cleanTitle(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixPatterns = [
            #"\s*[\(\[][^\)\]]*\b(?:remaster(?:ed)?|deluxe|radio edit|single version|album version|bonus track|explicit|clean|live|mono|stereo)\b[^\)\]]*[\)\]]"#,
            #"\s+-\s+(?:\d{4}\s+)?(?:remaster(?:ed)?|radio edit|single version|album version|live|mono|stereo|bonus track).*$"#,
        ]
        for pattern in suffixPatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pickBest(_ candidates: [Record], durationMs: Int) -> Lyrics? {
        let targetSec = Double(durationMs) / 1000.0
        let parsed: [(duration: Double?, lyrics: Lyrics)] = candidates.compactMap { record in
            guard let lyrics = record.toLyrics() else { return nil }
            if durationMs > 0, let dur = record.duration, abs(dur - targetSec) > 8.0 {
                return nil
            }
            return (record.duration, lyrics)
        }
        return parsed.sorted { lhs, rhs in
            if lhs.lyrics.synced != rhs.lyrics.synced { return lhs.lyrics.synced }
            let lDiff = lhs.duration.map { abs($0 - targetSec) } ?? 999
            let rDiff = rhs.duration.map { abs($0 - targetSec) } ?? 999
            return lDiff < rDiff
        }.first?.lyrics
    }

    private struct Record: Decodable {
        let instrumental: Bool?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?

        func toLyrics() -> Lyrics? {
            if instrumental == true {
                return Lyrics(lines: [], synced: false, instrumental: true, source: "LRCLIB")
            }
            if let synced = syncedLyrics, let parsed = Lyrics.parseLRC(synced, source: "LRCLIB") {
                return parsed
            }
            if let plain = plainLyrics, let parsed = Lyrics.parsePlain(plain, source: "LRCLIB") {
                return parsed
            }
            return nil
        }
    }
}

/// Per-track disk cache for lyrics (30 days for found lyrics, 24 hours for
/// confirmed misses; transient errors are never cached).
public final class LyricsDiskCache: Sendable {
    public enum Entry: Equatable, Sendable {
        case found(Lyrics)
        case notFound
    }

    private struct Stored: Codable {
        let cachedAt: Date
        let lyrics: Lyrics?
    }

    private let directory: URL
    private let foundTTL: TimeInterval
    private let missTTL: TimeInterval

    public init(
        directory: URL,
        foundTTL: TimeInterval = 30 * 24 * 3600,
        missTTL: TimeInterval = 24 * 3600
    ) {
        self.directory = directory
        self.foundTTL = foundTTL
        self.missTTL = missTTL
    }

    public static func defaultDirectory(bundleID: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: bundleID).appending(path: "lyrics")
    }

    public func load(trackURI: String, now: Date = .now) -> Entry? {
        let url = fileURL(for: trackURI)
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return nil }
        let age = now.timeIntervalSince(stored.cachedAt)
        if let lyrics = stored.lyrics {
            return age <= foundTTL ? .found(lyrics) : nil
        }
        return age <= missTTL ? .notFound : nil
    }

    public func save(trackURI: String, lyrics: Lyrics?, now: Date = .now) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = Stored(cachedAt: now, lyrics: lyrics)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: fileURL(for: trackURI), options: .atomic)
        }
    }

    public func clear() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func fileURL(for trackURI: String) -> URL {
        let hash = SHA256.hash(data: Data(trackURI.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: "\(hash).json")
    }
}
