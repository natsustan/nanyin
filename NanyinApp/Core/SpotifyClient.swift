//
//  SpotifyClient.swift
//  Nanyin
//

import Foundation

/// Minimal Spotify Web API client (M0: me + track metadata).
/// Token refresh is handled by AppModel before calls.
struct SpotifyClient {
    struct Track: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let durationMs: Int
        let artists: [String]
        let albumName: String
        let artworkURL: URL?

        enum CodingKeys: String, CodingKey {
            case id, name
            case durationMs = "duration_ms"
            case artists
            case album
        }

        enum AlbumKeys: String, CodingKey {
            case name
            case images
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            durationMs = try c.decode(Int.self, forKey: .durationMs)
            let artistsContainer = try c.nestedUnkeyedContainer(forKey: .artists)
            var names: [String] = []
            var iter = artistsContainer
            while !iter.isAtEnd {
                var artist: KeyedDecodingContainer<ArtistKeys>
                artist = try iter.nestedContainer(keyedBy: ArtistKeys.self)
                names.append(try artist.decode(String.self, forKey: .name))
            }
            artists = names
            let album = try c.nestedContainer(keyedBy: AlbumKeys.self, forKey: .album)
            albumName = try album.decode(String.self, forKey: .name)
            let images = try album.decode([Image].self, forKey: .images)
            artworkURL = images.first?.url
        }

        private enum ArtistKeys: String, CodingKey { case name }

        private struct Image: Codable {
            let url: URL
        }
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

    private var accessToken: String

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: "https://api.spotify.com\(path)")!
        if !query.isEmpty {
            components.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw APIError.needsAuth }
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func currentUser() async throws -> UserProfile {
        try await get("/v1/me")
    }

    func track(id: String) async throws -> Track {
        try await get("/v1/tracks/\(id)")
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
