//
//  SpotifyClient.swift
//  Nanyin
//

import Foundation

/// Spotify Web API client (ncspot client quota).
struct SpotifyClient {
    // MARK: - Models

    struct Track: Identifiable, Hashable {
        let id: String
        let uri: String // spotify:track:...
        let name: String
        let durationMs: Int
        /// Artists with ids — clickable names (M4.1) without index alignment.
        let artists: [Artist]
        let albumName: String
        let albumId: String?
        let artworkURL: URL?

        /// Copy with album name/artwork/id filled in — album endpoints return
        /// simplified track objects without the album field.
        func withAlbum(_ album: String, artwork: URL?, albumId: String?) -> Track {
            Track(
                id: id,
                uri: uri,
                name: name,
                durationMs: durationMs,
                artists: artists,
                albumName: albumName.isEmpty ? album : albumName,
                albumId: albumId ?? self.albumId,
                artworkURL: artworkURL ?? artwork
            )
        }
    }

    struct Artist: Identifiable, Hashable {
        let id: String
        let name: String
        let artworkURL: URL?
    }

    struct AlbumInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let artistName: String
        /// Release group on the artist's discography: album / single / compilation.
        let group: String
        let year: String?
        let trackCount: Int
        let artworkURL: URL?
    }

    struct PlaylistInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let trackCount: Int
        let artworkURL: URL?
    }

    struct UserProfile: Codable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    enum APIError: Error {
        case needsAuth
        case http(Int, String)
    }

    // MARK: - Core

    private var accessToken: String

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], retries: Int = 2) async throws -> T {
        var components = URLComponents(string: "https://api.spotify.com\(path)")!
        if !query.isEmpty {
            components.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        var attempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                return try JSONDecoder().decode(T.self, from: data)
            }
            // 429: honor Retry-After, retry a bounded number of times (cliamp pattern).
            if status == 429, attempt < retries {
                let retryAfter = Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2.0
                let wait = min(max(retryAfter, 1.0), 30.0)
                dlog("web api 429 on \(path), retrying in \(wait)s")
                try await Task.sleep(for: .seconds(wait))
                attempt += 1
                continue
            }
            if status == 401 { throw APIError.needsAuth }
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private struct ArtistDTO: Codable {
        let id: String?
        let name: String
        let images: [Image]?

        var toArtist: Artist? {
            guard let id else { return nil }
            return Artist(id: id, name: name, artworkURL: images?.first?.url)
        }
    }
    private struct Image: Codable {
        let url: URL
    }

    private struct AlbumDTO: Codable {
        let id: String?
        let name: String
        let images: [Image]?
    }

    private struct TrackDTO: Codable {
        let id: String?
        let uri: String?
        let name: String?
        let durationMs: Int?
        let artists: [ArtistDTO]?
        let album: AlbumDTO?
        let isPlayable: Bool?

        enum CodingKeys: String, CodingKey {
            case id, uri, name, artists, album
            case durationMs = "duration_ms"
            case isPlayable = "is_playable"
        }

        var toTrack: Track? {
            guard let id, let uri, let name else { return nil }
            guard isPlayable ?? true else { return nil } // unavailable in market
            return Track(
                id: id,
                uri: uri,
                name: name,
                durationMs: durationMs ?? 0,
                artists: (artists ?? []).compactMap(\.toArtist),
                albumName: album?.name ?? "",
                albumId: album?.id,
                artworkURL: album?.images?.first?.url
            )
        }
    }

    private struct PagedTracksDTO: Codable {
        struct Item: Codable {
            let track: TrackDTO?
        }
        let items: [Item]
        let total: Int
    }

    private struct PlaylistDTO: Codable {
        let id: String
        let name: String
        let snapshotId: String?
        let images: [Image]?
        let owner: OwnerDTO?
        struct TracksDTO: Codable { let total: Int? }
        let tracks: TracksDTO?

        struct OwnerDTO: Codable {
            let id: String?
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, images, owner, tracks
            case snapshotId = "snapshot_id"
        }
    }

    private struct PagedPlaylistsDTO: Codable {
        let items: [PlaylistDTO]?
        let total: Int
    }

    private struct DiscographyAlbumDTO: Codable {
        let id: String
        let name: String
        let images: [Image]?
        let releaseDate: String?
        let totalTracks: Int?
        /// Only present on /v1/artists/{id}/albums responses.
        let albumGroup: String?
        let artists: [ArtistDTO]?
        let tracks: TracksPageDTO?

        struct TracksPageDTO: Codable {
            let items: [TrackDTO]?
            let total: Int?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, images, artists, tracks
            case releaseDate = "release_date"
            case totalTracks = "total_tracks"
            case albumGroup = "album_group"
        }

        var toAlbumInfo: AlbumInfo {
            AlbumInfo(
                id: id,
                name: name,
                artistName: artists?.first?.name ?? "",
                group: albumGroup ?? "album",
                year: releaseDate.map { String($0.prefix(4)) },
                trackCount: totalTracks ?? 0,
                artworkURL: images?.first?.url
            )
        }
    }

    private struct ArtistAlbumsDTO: Codable {
        let items: [DiscographyAlbumDTO]?
        let total: Int
    }

    private struct AlbumTracksPageDTO: Codable {
        let items: [TrackDTO]?
        let total: Int
    }
    private struct SearchDTO: Codable {
        struct TracksDTO: Codable {
            let items: [TrackDTO]?
        }
        struct ArtistsDTO: Codable {
            let items: [ArtistDTO]?
        }
        let tracks: TracksDTO?
        let artists: ArtistsDTO?
    }

    private struct TopTracksDTO: Codable {
        let tracks: [TrackDTO]?
    }

    // MARK: - Endpoints

    func currentUser() async throws -> UserProfile {
        try await get("/v1/me")
    }

    func track(id: String) async throws -> Track {
        let dto = try await get("/v1/tracks/\(id)") as TrackDTO
        guard let t = dto.toTrack else { throw APIError.http(0, "unplayable track") }
        return t
    }

    /// All playlists in the user's library (owned + followed), paginated.
    func playlists() async throws -> [PlaylistInfo] {
        var result: [PlaylistInfo] = []
        var offset = 0
        let limit = 50
        while true {
            let page: PagedPlaylistsDTO = try await get(
                "/v1/me/playlists",
                query: ["limit": "\(limit)", "offset": "\(offset)"]
            )
            for p in page.items ?? [] {
                result.append(
                    PlaylistInfo(
                        id: p.id,
                        name: p.name,
                        trackCount: p.tracks?.total ?? 0,
                        artworkURL: p.images?.first?.url
                    )
                )
            }
            offset += limit
            if offset >= page.total { break }
        }
        return result
    }

    /// Tracks of a playlist, paginated.
    func playlistTracks(_ playlistId: String) async throws -> [Track] {
        var result: [Track] = []
        var offset = 0
        let limit = 50
        while true {
            let page: PagedTracksDTO = try await get(
                "/v1/playlists/\(playlistId)/items",
                query: ["limit": "\(limit)", "offset": "\(offset)"]
            )
            result += page.items.compactMap(\.track?.toTrack)
            offset += limit
            if offset >= page.total { break }
        }
        return result
    }

    /// Liked songs, paginated.
    func likedTracks() async throws -> [Track] {
        var result: [Track] = []
        var offset = 0
        let limit = 50
        while true {
            let page: PagedTracksDTO = try await get(
                "/v1/me/tracks",
                query: ["limit": "\(limit)", "offset": "\(offset)"]
            )
            result += page.items.compactMap(\.track?.toTrack)
            offset += limit
            if offset >= page.total { break }
        }
        return result
    }

    /// Total liked-songs count (single tiny request).
    func likedTotal() async throws -> Int {
        let page: PagedTracksDTO = try await get("/v1/me/tracks", query: ["limit": "1"])
        return page.total
    }

    /// Track + artist search in one request (ncspot client id keeps
    /// /v1/search working). Single page — results play as a bounded
    /// ad-hoc context (M3).
    func search(_ query: String, limit: Int = 50) async throws -> (tracks: [Track], artists: [Artist]) {
        let dto: SearchDTO = try await get(
            "/v1/search",
            query: ["q": query, "type": "track,artist", "limit": "\(limit)"]
        )
        let tracks = (dto.tracks?.items ?? []).compactMap(\.toTrack)
        let artists = (dto.artists?.items ?? []).compactMap(\.toArtist)
        return (tracks, artists)
    }

    /// Full artist profile. Track responses contain simplified artist objects
    /// without images, so artist pages use this endpoint when needed.
    func artist(_ artistId: String) async throws -> Artist {
        let dto: ArtistDTO = try await get("/v1/artists/\(artistId)")
        guard let artist = dto.toArtist else {
            throw APIError.http(0, "invalid artist")
        }
        return artist
    }

    /// An artist's top tracks (small — plays as a bounded ad-hoc context).
    func artistTopTracks(_ artistId: String) async throws -> [Track] {
        let dto: TopTracksDTO = try await get(
            "/v1/artists/\(artistId)/top-tracks",
            query: ["market": "from_token"]
        )
        return (dto.tracks ?? []).compactMap(\.toTrack)
    }

    /// An artist's albums + singles + compilations, paginated.
    func artistAlbums(_ artistId: String) async throws -> [AlbumInfo] {
        var result: [AlbumInfo] = []
        var offset = 0
        let limit = 50
        while true {
            let page: ArtistAlbumsDTO = try await get(
                "/v1/artists/\(artistId)/albums",
                query: [
                    "include_groups": "album,single,compilation",
                    "limit": "\(limit)",
                    "offset": "\(offset)",
                    "market": "from_token",
                ]
            )
            result += (page.items ?? []).map(\.toAlbumInfo)
            offset += limit
            if offset >= page.total { break }
        }
        return result
    }

    /// An album's tracks, paginated past the first page embedded in the
    /// album object. Simplified tracks get the album's name/artwork filled in.
    func albumTracks(_ albumId: String) async throws -> [Track] {
        let dto: DiscographyAlbumDTO = try await get("/v1/albums/\(albumId)", query: ["market": "from_token"])
        let albumName = dto.name
        let artwork = dto.images?.first?.url
        var result = (dto.tracks?.items ?? []).compactMap(\.toTrack)
        let total = dto.tracks?.total ?? result.count
        var offset = max(result.count, 50)
        while offset < total {
            let page: AlbumTracksPageDTO = try await get(
                "/v1/albums/\(albumId)/tracks",
                query: ["limit": "50", "offset": "\(offset)", "market": "from_token"]
            )
            result += (page.items ?? []).compactMap(\.toTrack)
            offset += 50
        }
        return result.map { $0.withAlbum(albumName, artwork: artwork, albumId: albumId) }
    }

    /// Extracts the 22-char base62 id from any URI/URL form.
    static func trackId(from uriOrUrl: String) -> String? {
        var s = uriOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = s.lastIndex(of: "/") {
            // https://open.spotify.com/track/<id>?si=...
            let tail = String(s[s.index(after: open)...])
            s = tail.split(separator: "?").first.map(String.init) ?? tail
        } else if s.hasPrefix("spotify:track:") {
            s = String(s.dropFirst("spotify:track:".count))
        }
        return s.count == 22 ? s : nil
    }
}
