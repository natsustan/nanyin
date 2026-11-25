import Foundation
import NanyinKit

/// Events from the Rust core (`core/src/events.rs`).
enum CoreEvent: Decodable, Equatable {
    case connected(username: String, credentials: String?)
    case connectFailed(reason: FailureReason, message: String)
    /// The session dropped. `resuming`: the song plays on and the next
    /// session picks it up, with its queue.
    case sessionEnded(resuming: Bool)
    case deactivated
    /// The new session could not pick up the song a dropped one left
    /// playing; it has stopped.
    case resumeFailed
    case trackChanged(CoreTrack)
    case loading(uri: String, positionMs: Int)
    case playing(uri: String, positionMs: Int)
    case position(uri: String, positionMs: Int)
    case paused(uri: String, positionMs: Int)
    case stopped
    case unavailable(uri: String)
    case volume(UInt16)
    case shuffle(Bool)
    case `repeat`(context: Bool, track: Bool)
    case queue(contextURI: String, tracks: [CoreTrack], manualCount: Int)

    enum FailureReason: String, Decodable {
        case authRejected = "auth_rejected"
        case accountMismatch = "account_mismatch"
        case timeout
        case other
    }

    private enum Key: String, CodingKey {
        case type, username, credentials, reason, message, track, uri, resuming
        case positionMs = "position_ms"
        case volume, on, context, tracks
        case contextURI = "context_uri"
        case manualCount = "manual_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        func position() throws -> Int { try c.decode(Int.self, forKey: .positionMs) }
        func uri() throws -> String { try c.decode(String.self, forKey: .uri) }
        switch type {
        case "connected":
            self = .connected(
                username: try c.decode(String.self, forKey: .username),
                credentials: try c.decodeIfPresent(String.self, forKey: .credentials))
        case "connect_failed":
            self = .connectFailed(
                reason: (try? c.decode(FailureReason.self, forKey: .reason)) ?? .other,
                message: try c.decode(String.self, forKey: .message))
        case "session_ended": self = .sessionEnded(resuming: (try? c.decode(Bool.self, forKey: .resuming)) ?? false)
        case "deactivated": self = .deactivated
        case "resume_failed": self = .resumeFailed
        case "track_changed": self = .trackChanged(try c.decode(CoreTrack.self, forKey: .track))
        case "loading": self = .loading(uri: try uri(), positionMs: try position())
        case "playing": self = .playing(uri: try uri(), positionMs: try position())
        case "position": self = .position(uri: try uri(), positionMs: try position())
        case "paused": self = .paused(uri: try uri(), positionMs: try position())
        case "stopped": self = .stopped
        case "unavailable": self = .unavailable(uri: try uri())
        case "volume": self = .volume(try c.decode(UInt16.self, forKey: .volume))
        case "shuffle": self = .shuffle(try c.decode(Bool.self, forKey: .on))
        case "repeat":
            self = .repeat(context: try c.decode(Bool.self, forKey: .context), track: try c.decode(Bool.self, forKey: .track))
        case "queue":
            self = .queue(
                contextURI: try c.decode(String.self, forKey: .contextURI),
                tracks: try c.decode([CoreTrack].self, forKey: .tracks),
                manualCount: (try? c.decode(Int.self, forKey: .manualCount)) ?? 0)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown event \(type)")
        }
    }
}

/// The track librespot is playing, with the metadata it already has.
struct CoreTrack: Decodable, Equatable, Sendable {
    struct Artist: Decodable, Equatable, Sendable {
        let uri: String
        let name: String
    }

    let uri: String
    /// When Spotify relinked playback to an alternative track, the playable
    /// audio item's URI.
    let linkedURI: String?
    let name: String
    let artists: [Artist]
    let album: String
    let albumURI: String?
    let coverURL: URL?
    let durationMs: Int
    let explicit: Bool

    enum CodingKeys: String, CodingKey {
        case uri, name, artists, album, explicit
        case linkedURI = "linked_uri"
        case albumURI = "album_uri"
        case coverURL = "cover_url"
        case durationMs = "duration_ms"
    }

    var artistNames: String { artists.map(\.name).joined(separator: ", ") }
    var isTrack: Bool { uri.hasPrefix("spotify:track:") }
    var allURIs: Set<String> { linkedURI.map { [uri, $0] } ?? [uri] }

    func matches(uri target: String) -> Bool {
        uri == target || linkedURI == target
    }
}

/// A page of a playlist read through the playback session.
struct SessionPlaylistPage: Decodable, Equatable, Sendable {
    struct Row: Decodable, Equatable, Sendable {
        let index: Int
        let addedAtMs: Int64?
        let track: CoreTrack

        enum CodingKeys: String, CodingKey {
            case index, track
            case addedAtMs = "added_at_ms"
        }
    }

    let total: Int
    let rows: [Row]
    let next: Int?
    let name: String?
    let description: String?
    let images: [SpotifyImage]?
}

/// A song's credits, read through the session (`core/src/reads.rs`).
struct CoreCredits: Decodable, Equatable, Sendable {
    struct Role: Decodable, Equatable, Sendable {
        let title: String
        let artists: [Credit]
    }

    struct Credit: Decodable, Equatable, Sendable {
        let name: String
        /// Empty for someone with no artist page.
        let uri: String
        /// "Composer", "Lyricist", "Lead Vocal"…
        let subroles: [String]
    }

    let roles: [Role]
    /// The labels or distributors that supplied the credits.
    let sources: [String]
}

/// Wrapped Spotify lyrics reply (`core/src/reads.rs`).
struct CoreLyricsReply: Decodable, Equatable, Sendable {
    let lyrics: Lyrics?
}

/// Personalized Home shelves read through Pathfinder (`core/src/pathfinder.rs`).
struct CoreHomeShelves: Decodable, Equatable, Sendable {
    let madeForYou: [Playlist]
    let topMixes: [Playlist]

    enum CodingKeys: String, CodingKey {
        case madeForYou = "made_for_you"
        case topMixes = "top_mixes"
    }
}

/// Questions for the Rust core (`core/src/requests.rs`), each answered once.
enum CoreAsk: Encodable, Sendable {
    /// Answered with a `SessionPlaylistPage`.
    case playlist(id: String, offset: Int)
    /// Answered with `[CoreTrack]`.
    case topTracks(artistID: String)
    /// Answered with `CoreCredits`.
    case credits(trackID: String)
    /// Answered with `CoreLyricsReply`.
    case lyrics(trackID: String, coverFileID: String?)
    /// Answered with `[AlbumSummary]`.
    case newReleases(force: Bool)
    /// Answered with `CoreHomeShelves`.
    case madeForYou(timezone: String, force: Bool)

    private enum Key: String, CodingKey {
        case ask, id, offset, timezone, force
        case coverFileID = "cover_file_id"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .playlist(let id, let offset):
            try c.encode("playlist", forKey: .ask)
            try c.encode(id, forKey: .id)
            try c.encode(offset, forKey: .offset)
        case .topTracks(let artistID):
            try c.encode("top_tracks", forKey: .ask)
            try c.encode(artistID, forKey: .id)
        case .credits(let trackID):
            try c.encode("credits", forKey: .ask)
            try c.encode(trackID, forKey: .id)
        case .lyrics(let trackID, let coverFileID):
            try c.encode("lyrics", forKey: .ask)
            try c.encode(trackID, forKey: .id)
            try c.encodeIfPresent(coverFileID, forKey: .coverFileID)
        case .newReleases(let force):
            try c.encode("new_releases", forKey: .ask)
            try c.encode(force, forKey: .force)
        case .madeForYou(let timezone, let force):
            try c.encode("made_for_you", forKey: .ask)
            try c.encode(timezone, forKey: .timezone)
            try c.encode(force, forKey: .force)
        }
    }
}

/// Commands for the Rust core (`core/src/commands.rs`).
enum CoreCommand: Encodable, Equatable {
    case play, pause, playPause, next, previous
    case seek(positionMs: Int)
    case volume(UInt16)
    case shuffle(Bool)
    case `repeat`(context: Bool, track: Bool)
    case addToQueue(uri: String)
    case clearQueue
    case transfer
    case load(Load)

    struct Load: Encodable, Equatable {
        var contextURI: String?
        var trackURIs: [String] = []
        var startURI: String?
        var startIndex: Int?
        var positionMs = 0
        var shuffle: Bool?

        enum CodingKeys: String, CodingKey {
            case contextURI = "context_uri"
            case trackURIs = "track_uris"
            case startURI = "start_uri"
            case startIndex = "start_index"
            case positionMs = "position_ms"
            case shuffle
        }
    }

    private enum Key: String, CodingKey {
        case cmd, volume, on, context, track, uri
        case positionMs = "position_ms"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .play: try c.encode("play", forKey: .cmd)
        case .pause: try c.encode("pause", forKey: .cmd)
        case .playPause: try c.encode("play_pause", forKey: .cmd)
        case .next: try c.encode("next", forKey: .cmd)
        case .previous: try c.encode("previous", forKey: .cmd)
        case .seek(let position):
            try c.encode("seek", forKey: .cmd)
            try c.encode(max(0, position), forKey: .positionMs)
        case .volume(let volume):
            try c.encode("volume", forKey: .cmd)
            try c.encode(volume, forKey: .volume)
        case .shuffle(let on):
            try c.encode("shuffle", forKey: .cmd)
            try c.encode(on, forKey: .on)
        case .repeat(let context, let track):
            try c.encode("repeat", forKey: .cmd)
            try c.encode(context, forKey: .context)
            try c.encode(track, forKey: .track)
        case .addToQueue(let uri):
            try c.encode("add_to_queue", forKey: .cmd)
            try c.encode(uri, forKey: .uri)
        case .clearQueue:
            try c.encode("clear_queue", forKey: .cmd)
        case .transfer:
            try c.encode("transfer", forKey: .cmd)
        case .load(let load):
            try c.encode("load", forKey: .cmd)
            try load.encode(to: encoder)

        }
    }
}

/// What `nanyin_connect` needs (`core/src/engine.rs`).
struct CoreConfig: Encodable {
    enum Credentials: Encodable {
        case accessToken(String)
        case stored(json: String)

        private enum Key: String, CodingKey { case type, token, json }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Key.self)
            switch self {
            case .accessToken(let token):
                try c.encode("access_token", forKey: .type)
                try c.encode(token, forKey: .token)
            case .stored(let json):
                try c.encode("stored", forKey: .type)
                try c.encode(json, forKey: .json)
            }
        }
    }

    let deviceID: String
    let deviceName: String
    let initialVolume: UInt16
    let credentials: Credentials
    let expectedUsername: String?
    let audioCacheDir: String?
    let audioCacheLimit: UInt64?
    let proxy: String?
    let bitrate: UInt16
    let normalisation: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case initialVolume = "initial_volume"
        case credentials
        case expectedUsername = "expected_username"
        case audioCacheDir = "audio_cache_dir"
        case audioCacheLimit = "audio_cache_limit"
        case proxy
        case bitrate
        case normalisation
    }
}
