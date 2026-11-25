import Foundation

// Web API objects, trimmed to what Nanyin shows. Optional wherever Spotify
// has been seen to send null (unavailable or removed items).

public struct SpotifyImage: Codable, Sendable, Hashable {
    public let url: URL
    public let width: Int?
}

extension [SpotifyImage] {
    /// The smallest image at least `minimum` pixels wide, else the largest.
    /// Spotify orders images widest-first and omits `width` on many playlist
    /// covers, so unsized lists fall back to the first entry.
    public func best(minimum: Int) -> URL? {
        let sized = filter { ($0.width ?? 0) > 0 }.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        if let match = sized.first(where: { ($0.width ?? 0) >= minimum }) ?? sized.last {
            return match.url
        }
        return first?.url
    }
}

public struct UserProfile: Codable, Sendable, Hashable {
    public let id: String
    public let display_name: String?
    public let product: String?

    public var name: String { display_name ?? id }
    public var isPremium: Bool { product == "premium" }
}

public struct ArtistRef: Codable, Sendable, Hashable {
    public let id: String?
    public let name: String
    public let uri: String?

    public init(id: String? = nil, name: String, uri: String? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
    }
}

extension [ArtistRef] {
    /// "A, B & C" as a track row lists them.
    public var names: String { map(\.name).joined(separator: ", ") }
}

public struct AlbumRef: Codable, Sendable, Hashable {
    public let name: String
    public let uri: String?

    public init(name: String, uri: String? = nil) {
        self.name = name
        self.uri = uri
    }
}

public struct Track: Codable, Sendable, Hashable {
    public let name: String
    public let uri: String
    public let duration_ms: Int
    public let explicit: Bool?
    public let is_playable: Bool?
    public let popularity: Int?
    public let artists: [ArtistRef]
    public let album: AlbumRef?

    public init(
        name: String,
        uri: String,
        duration_ms: Int,
        explicit: Bool? = nil,
        is_playable: Bool? = true,
        popularity: Int? = nil,
        artists: [ArtistRef],
        album: AlbumRef? = nil
    ) {
        self.name = name
        self.uri = uri
        self.duration_ms = duration_ms
        self.explicit = explicit
        self.is_playable = is_playable
        self.popularity = popularity
        self.artists = artists
        self.album = album
    }
}

public struct SavedTrack: Codable, Sendable, Hashable {
    public let added_at: String?
    public let track: Track
}

/// A playlist entry. Spotify's 2026 API names the object `item`; older
/// answers call it `track`.
public struct PlaylistItem: Codable, Sendable, Hashable {
    public let added_at: String?
    public let item: Track?
    public let track: Track?

    public var playable: Track? { item ?? track }
}

public struct PlaylistOwner: Codable, Sendable, Hashable {
    public let id: String
    public let display_name: String?

    public init(id: String, display_name: String? = nil) {
        self.id = id
        self.display_name = display_name
    }
}

public struct Playlist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public let uri: String
    public var description: String?
    public var images: [SpotifyImage]?
    public let owner: PlaylistOwner
    public let collaborative: Bool?

    public init(
        id: String,
        name: String,
        uri: String,
        description: String? = nil,
        images: [SpotifyImage]? = nil,
        owner: PlaylistOwner,
        collaborative: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.uri = uri
        self.description = description
        self.images = images
        self.owner = owner
        self.collaborative = collaborative
    }

    public var ownerName: String? {
        if let display = owner.display_name, !display.isEmpty { return display }
        return owner.id.isEmpty ? nil : owner.id
    }

    /// Plain-text description with Spotify's HTML tags and common entities
    /// stripped, or `nil` when blank.
    public var plainDescription: String? {
        guard let description else { return nil }
        let plain = Self.stripHTML(description).trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }

    private static func stripHTML(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeHTMLEntities(withoutTags)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semi = text[i...].firstIndex(of: ";") {
                let entity = text[text.index(after: i) ..< semi]
                if let decoded = decodeEntity(entity) {
                    out.append(decoded)
                    i = text.index(after: semi)
                    continue
                }
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }

    private static func decodeEntity(_ entity: Substring) -> String? {
        switch entity {
        case "amp": "&"
        case "lt": "<"
        case "gt": ">"
        case "quot": "\""
        case "apos": "'"
        case "nbsp": " "
        default:
            if entity.hasPrefix("#x") || entity.hasPrefix("#X"),
               let value = UInt32(entity.dropFirst(2), radix: 16),
               let scalar = Unicode.Scalar(value) {
                String(scalar)
            } else if entity.hasPrefix("#"),
                      let value = UInt32(entity.dropFirst(1), radix: 10),
                      let scalar = Unicode.Scalar(value) {
                String(scalar)
            } else {
                nil
            }
        }
    }
}

public struct Album: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let album_type: String?
    public let images: [SpotifyImage]?
    public let artists: [ArtistRef]
    public let release_date: String?
    public let total_tracks: Int?
    public let tracks: Paging<AlbumTrack>?

    public var releaseYear: String? { release_date.map { String($0.prefix(4)) } }
}

/// An album's track listing omits the album itself.
public struct AlbumTrack: Codable, Sendable, Hashable {
    public let id: String?
    public let name: String
    public let uri: String
    public let duration_ms: Int
    public let explicit: Bool?
    public let artists: [ArtistRef]
}

public struct SavedAlbum: Codable, Sendable, Hashable {
    public let added_at: String?
    public let album: Album
}

public struct Followers: Codable, Sendable, Hashable {
    public let total: Int

    public init(total: Int) {
        self.total = total
    }
}

public struct Artist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]?
    public let genres: [String]?
    public let followers: Followers?

    public init(
        id: String,
        name: String,
        uri: String,
        images: [SpotifyImage]? = nil,
        genres: [String]? = nil,
        followers: Followers? = nil
    ) {
        self.id = id
        self.name = name
        self.uri = uri
        self.images = images
        self.genres = genres
        self.followers = followers
    }
}

public struct Paging<Item: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public let items: [Item]
    public let total: Int?
    public let next: String?
}

/// Followed artists page by cursor, not offset.
public struct CursorPaging<Item: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public let items: [Item]
    public let total: Int?
    public let next: String?
    public let cursors: Cursors?

    public struct Cursors: Codable, Sendable, Hashable {
        public let after: String?
    }
}

public struct PlayHistory: Codable, Sendable, Hashable {
    public let track: Track
    public let played_at: String

    public init(track: Track, played_at: String) {
        self.track = track
        self.played_at = played_at
    }
}

public struct SearchResults: Codable, Sendable, Hashable {
    public let tracks: Paging<Track>?
    public let artists: Paging<Artist>?
    public let albums: Paging<AlbumSummary>?
    /// Spotify's playlist search can include `null` slots for removed or
    /// inaccessible playlists; decode optionals and read `compactPlaylists`.
    public let playlists: Paging<Playlist?>?

    public var compactPlaylists: [Playlist] {
        playlists?.items.compactMap { $0 } ?? []
    }
}

/// Discography filter groups for `/artists/{id}/albums`.
public enum ArtistAlbumGroup: String, CaseIterable, Sendable, Hashable {
    case all
    case albums
    case singles
    case compilations
    case appearsOn

    public var label: String {
        switch self {
        case .all: "All"
        case .albums: "Albums"
        case .singles: "Singles & EPs"
        case .compilations: "Compilations"
        case .appearsOn: "Appears On"
        }
    }

    public var includeGroups: String {
        switch self {
        case .all: "album,single,compilation"
        case .albums: "album"
        case .singles: "single"
        case .compilations: "compilation"
        case .appearsOn: "appears_on"
        }
    }
}

/// Search and artist pages list albums without their tracks.
public struct AlbumSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let album_type: String?
    public let album_group: String?
    public let total_tracks: Int?
    public let images: [SpotifyImage]?
    public let artists: [ArtistRef]
    public let release_date: String?

    public var releaseYear: String? { release_date.map { String($0.prefix(4)) } }

    /// Human-readable release category ("Album", "Single", "EP", "Compilation").
    public var kindLabel: String? {
        switch (album_type ?? album_group)?.lowercased() {
        case "album": "Album"
        case "single": "Single"
        case "ep": "EP"
        case "compilation": "Compilation"
        default: nil
        }
    }

    /// "2024 · Album" or whichever portion is available.
    public var releaseSubtitle: String {
        [releaseYear, kindLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A Spotify Connect device returned by `GET /me/player/devices`.
public struct ConnectDevice: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let is_active: Bool
    public let is_restricted: Bool
    public let name: String
    public let type: String
    public let volume_percent: Int?

    public var stableID: String { id ?? "\(type):\(name)" }
}
