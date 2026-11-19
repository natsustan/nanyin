import Foundation

// Web API objects, trimmed to what Nanyin shows. Optional wherever Spotify
// has been seen to send null (unavailable or removed items).

public struct SpotifyImage: Codable, Sendable, Hashable {
    public let url: URL
    public let width: Int?
    public let height: Int?
}

extension [SpotifyImage] {
    /// The smallest image at least `minimum` pixels wide, else the largest.
    public func best(minimum: Int) -> URL? {
        let sorted = self.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return (sorted.first { ($0.width ?? 0) >= minimum } ?? sorted.last)?.url
    }
}

public struct UserProfile: Codable, Sendable, Hashable {
    public let id: String
    public let display_name: String?
    public let country: String?
    public let product: String?
    public let images: [SpotifyImage]?

    public var name: String { display_name ?? id }
    public var isPremium: Bool { product == "premium" }
}

public struct ArtistRef: Codable, Sendable, Hashable {
    public let id: String?
    public let name: String
    public let uri: String?
}

public struct AlbumRef: Codable, Sendable, Hashable {
    public let id: String?
    public let name: String
    public let uri: String?
    public let images: [SpotifyImage]?
    public let release_date: String?
}

public struct Track: Codable, Sendable, Hashable, Identifiable {
    public let id: String?
    public let name: String
    public let uri: String
    public let duration_ms: Int
    public let explicit: Bool?
    public let is_playable: Bool?
    public let popularity: Int?
    public let artists: [ArtistRef]
    public let album: AlbumRef?
    public let type: String?

    public var artistNames: String { artists.map(\.name).joined(separator: ", ") }
    public var isEpisode: Bool { type == "episode" }
}

public struct SavedTrack: Codable, Sendable, Hashable {
    public let added_at: String?
    public let track: Track
}

/// A playlist entry. Spotify's 2026 API names the object `item`; older
/// answers call it `track`.
public struct PlaylistItem: Codable, Sendable, Hashable {
    public let added_at: String?
    public let is_local: Bool?
    public let item: Track?
    public let track: Track?

    public var playable: Track? { item ?? track }
}

public struct PlaylistOwner: Codable, Sendable, Hashable {
    public let id: String
    public let display_name: String?
}

public struct Playlist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let description: String?
    public let images: [SpotifyImage]?
    public let owner: PlaylistOwner
    public let collaborative: Bool?
    public let snapshot_id: String?
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
}

/// An album's track listing omits the album itself.
public struct AlbumTrack: Codable, Sendable, Hashable {
    public let id: String?
    public let name: String
    public let uri: String
    public let duration_ms: Int
    public let explicit: Bool?
    public let track_number: Int?
    public let disc_number: Int?
    public let artists: [ArtistRef]
}

public struct SavedAlbum: Codable, Sendable, Hashable {
    public let added_at: String?
    public let album: Album
}

public struct Artist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]?
    public let genres: [String]?
}

public struct Paging<Item: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public let items: [Item]
    public let total: Int?
    public let offset: Int?
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
}

public struct SearchResults: Codable, Sendable, Hashable {
    public let tracks: Paging<Track>?
    public let artists: Paging<Artist>?
    public let albums: Paging<AlbumSummary>?
    /// Search can return null entries among playlists.
    public let playlists: Paging<Playlist?>?
}

/// Search and artist pages list albums without their tracks.
public struct AlbumSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let album_type: String?
    public let images: [SpotifyImage]?
    public let artists: [ArtistRef]
    public let release_date: String?
}
