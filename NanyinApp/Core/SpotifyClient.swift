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
        let artists: [String]
        let albumName: String
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

    // MARK: - JSON shapes

    private struct Image: Codable {
        let url: URL
    }

    private struct ArtistDTO: Codable {
        let name: String
    }

    private struct AlbumDTO: Codable {
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
                artists: (artists ?? []).map(\.name),
                albumName: album?.name ?? "",
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
