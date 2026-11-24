import Foundation

/// Time window for `/me/top/artists` and `/me/top/tracks`.
public enum TopTimeRange: String, CaseIterable, Sendable, Hashable {
    case shortTerm = "short_term"
    case mediumTerm = "medium_term"
    case longTerm = "long_term"

    public var label: String {
        switch self {
        case .shortTerm: "4 Weeks"
        case .mediumTerm: "6 Months"
        case .longTerm: "All Time"
        }
    }
}

/// Typed endpoints. Page sizes stay at 50 or below (Development Mode rejects
/// larger pages; search is limited to 10 per type).
public extension SpotifyWebAPI {
    func me() async throws -> UserProfile {
        try await get("/me")
    }

    func myPlaylists(offset: Int = 0) async throws -> Paging<Playlist> {
        try await get("/me/playlists", query: ["limit": "50", "offset": "\(offset)"])
    }

    func playlistItems(_ id: String, offset: Int = 0) async throws -> Paging<PlaylistItem> {
        try await get("/playlists/\(id)/items", query: [
            "limit": "50", "offset": "\(offset)", "additional_types": "track,episode",
        ])
    }

    func savedTracks(offset: Int = 0) async throws -> Paging<SavedTrack> {
        try await get("/me/tracks", query: ["limit": "50", "offset": "\(offset)"])
    }

    func savedAlbums(offset: Int = 0) async throws -> Paging<SavedAlbum> {
        try await get("/me/albums", query: ["limit": "50", "offset": "\(offset)"])
    }

    func followedArtists(after: String? = nil) async throws -> CursorPaging<Artist> {
        struct Body: Decodable, Sendable { let artists: CursorPaging<Artist> }
        var query = ["type": "artist", "limit": "50"]
        query["after"] = after
        return try await get("/me/following", query: query, as: Body.self).artists
    }

    func recentlyPlayed() async throws -> [PlayHistory] {
        try await get("/me/player/recently-played", query: ["limit": "50"], as: Paging<PlayHistory>.self).items
    }

    func topArtists(timeRange: TopTimeRange = .shortTerm, limit: Int = 20) async throws -> Paging<Artist> {
        let clamped = min(max(limit, 1), 50)
        return try await get("/me/top/artists", query: ["time_range": timeRange.rawValue, "limit": "\(clamped)"])
    }

    func topTracks(timeRange: TopTimeRange = .shortTerm, limit: Int = 20) async throws -> Paging<Track> {
        let clamped = min(max(limit, 1), 50)
        return try await get("/me/top/tracks", query: ["time_range": timeRange.rawValue, "limit": "\(clamped)"])
    }

    func album(_ id: String) async throws -> Album {
        try await get("/albums/\(id)")
    }

    func artist(_ id: String) async throws -> Artist {
        try await get("/artists/\(id)")
    }

    func artistAlbums(_ id: String) async throws -> Paging<AlbumSummary> {
        try await get("/artists/\(id)/albums", query: ["include_groups": "album,single", "limit": "10"])
    }

    func search(_ text: String, types: [String] = ["track", "artist", "album"]) async throws -> SearchResults {
        try await get("/search", query: ["q": text, "type": types.joined(separator: ","), "limit": "10"])
    }

    /// Appends `uris` to a playlist the listener may edit, in order, at most
    /// 100 per request as the endpoint allows.
    func addToPlaylist(_ id: String, uris: [String]) async throws {
        struct Body: Encodable, Sendable { let uris: [String] }
        for start in stride(from: 0, to: uris.count, by: 100) {
            let batch = Array(uris[start ..< min(start + 100, uris.count)])
            try await send("POST", "/playlists/\(id)/items", body: Body(uris: batch))
        }
    }

    /// Creates a playlist owned by the listener (2026: `/me/playlists`).
    func createPlaylist(name: String) async throws -> Playlist {
        struct Body: Encodable, Sendable { let name: String }
        let data = try await send("POST", "/me/playlists", body: Body(name: name))
        do {
            return try JSONDecoder().decode(Playlist.self, from: data)
        } catch {
            throw WebAPIError.decoding("/me/playlists: \(error)")
        }
    }

    func renamePlaylist(_ id: String, to name: String) async throws {
        struct Body: Encodable, Sendable { let name: String }
        try await send("PUT", "/playlists/\(id)", body: Body(name: name))
    }

    /// Saves tracks, albums, artists or playlists by URI (2026 unified library).
    func save(_ uris: [String]) async throws {
        try await send("PUT", "/me/library", query: ["uris": uris.joined(separator: ",")])
    }

    func remove(_ uris: [String]) async throws {
        try await send("DELETE", "/me/library", query: ["uris": uris.joined(separator: ",")])
    }

    func libraryContains(_ uris: [String]) async throws -> [Bool] {
        try await get("/me/library/contains", query: ["uris": uris.joined(separator: ",")])
    }
}
