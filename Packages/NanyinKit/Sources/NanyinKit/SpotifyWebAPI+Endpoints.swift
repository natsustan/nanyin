import Foundation

/// Typed endpoints. Page sizes stay at 50 or below (Development Mode rejects
/// larger pages; search is limited to 10 per type).
public extension SpotifyWebAPI {
    func me() async throws -> UserProfile {
        try await get("/me")
    }

    func myPlaylists(offset: Int = 0) async throws -> Paging<Playlist> {
        try await get("/me/playlists", query: ["limit": "50", "offset": "\(offset)"])
    }

    func playlist(_ id: String) async throws -> Playlist {
        try await get("/playlists/\(id)", query: ["fields": "id,name,uri,description,images,owner,collaborative,snapshot_id"])
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

    func topTracks() async throws -> [Track] {
        try await get("/me/top/tracks", query: ["limit": "50", "time_range": "short_term"], as: Paging<Track>.self).items
    }

    func album(_ id: String) async throws -> Album {
        try await get("/albums/\(id)")
    }

    func artist(_ id: String) async throws -> Artist {
        try await get("/artists/\(id)")
    }

    func artistTopTracks(_ id: String) async throws -> [Track] {
        struct Body: Decodable, Sendable { let tracks: [Track] }
        return try await get("/artists/\(id)/top-tracks", as: Body.self).tracks
    }

    func artistAlbums(_ id: String) async throws -> Paging<AlbumSummary> {
        try await get("/artists/\(id)/albums", query: ["include_groups": "album,single", "limit": "10"])
    }

    func search(_ text: String, types: [String] = ["track", "artist", "album", "playlist"]) async throws -> SearchResults {
        try await get("/search", query: ["q": text, "type": types.joined(separator: ","), "limit": "10"])
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
