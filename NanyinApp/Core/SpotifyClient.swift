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
        /// Display-only fallback when playback metadata has names but no ids.
        let artistDisplayText: String?
        let albumName: String
        let albumId: String?
        let artworkURL: URL?
        /// Position in the unfiltered server context, including unavailable
        /// and non-track entries. Display row numbers are not playback offsets.
        var contextPosition: ContextPosition? = nil

        struct ContextPosition: Hashable {
            let source: String
            let index: Int
        }

        init(
            id: String,
            uri: String,
            name: String,
            durationMs: Int,
            artists: [Artist],
            artistDisplayText: String? = nil,
            albumName: String,
            albumId: String?,
            artworkURL: URL?
        ) {
            self.id = id
            self.uri = uri
            self.name = name
            self.durationMs = durationMs
            self.artists = artists
            self.artistDisplayText = artistDisplayText
            self.albumName = albumName
            self.albumId = albumId
            self.artworkURL = artworkURL
        }

        /// Copy with album name/artwork/id filled in — album endpoints return
        /// simplified track objects without the album field.
        func withAlbum(_ album: String, artwork: URL?, albumId: String?) -> Track {
            var track = Track(
                id: id,
                uri: uri,
                name: name,
                durationMs: durationMs,
                artists: artists,
                artistDisplayText: artistDisplayText,
                albumName: albumName.isEmpty ? album : albumName,
                albumId: albumId ?? self.albumId,
                artworkURL: artworkURL ?? artwork
            )
            track.contextPosition = contextPosition
            return track
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

    /// A saved album entry from /v1/me/albums — the library item, not the
    /// bare release (M4.3). Saved albums and Liked Songs stay separate.
    struct SavedAlbum: Identifiable, Hashable {
        let album: AlbumInfo
        /// When the user saved it — drives the Recently Added ordering.
        let addedAt: Date?
        var id: String { album.id }
    }

    struct FollowedArtistsPage: Equatable {
        let artists: [Artist]
        let after: String?
        let total: Int
    }

    struct PlaylistInfo: Identifiable, Hashable {
        let id: String
        let name: String
        /// Server-reported track total — bumped locally after a confirmed
        /// add (M4.5) while Spotify's read side catches up.
        var trackCount: Int
        let artworkURL: URL?
        /// Owner's user id — owned playlists are the writable targets for
        /// Add to Playlist (M4.5). Retained at load; no extra request.
        let ownerId: String?

        init(
            id: String,
            name: String,
            trackCount: Int,
            artworkURL: URL?,
            ownerId: String? = nil
        ) {
            self.id = id
            self.name = name
            self.trackCount = trackCount
            self.artworkURL = artworkURL
            self.ownerId = ownerId
        }
    }

    /// One entry from GET /v1/me/player/recently-played: the track plus the
    /// context (album / playlist / artist) it was played from. The context
    /// carries only a URI and type string — no name or artwork.
    struct PlayHistoryItem {
        let track: Track
        let contextURI: String?
        let contextType: String?
    }

    /// Listening-affinity window for /v1/me/top/* endpoints.
    enum TopTimeRange: String {
        case shortTerm = "short_term" // ~4 weeks
        case mediumTerm = "medium_term" // ~6 months
        case longTerm = "long_term"
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

    private let transport: SpotifyWebTransport

    init(accessToken: String, transport: SpotifyWebTransport = SpotifyWebTransport()) {
        self.accessToken = accessToken
        self.transport = transport
    }

    private static let iso8601Parser = ISO8601DateFormatter()

    private static func parseISO8601(_ raw: String) -> Date? {
        iso8601Parser.date(from: raw)
    }

    private func request(path: String, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], retries: Int = 2) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await fetch(path, query: query, retries: retries))
    }

    /// GET returning the raw body — endpoints with testable static decoders
    /// (personalized home) fetch through this so decode logic stays pure.
    private func fetch(_ path: String, query: [String: String] = [:], retries: Int = 2) async throws -> Data {
        var components = URLComponents(string: "https://api.spotify.com\(path)")!
        if !query.isEmpty {
            components.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await transport.send(req, retries: retries)
    }

    /// Only explicit 429 responses are retried. Ambiguous failed writes must
    /// not be replayed: a playlist insertion might already have succeeded.
    private func mutate(
        path: String,
        method: String,
        body: Data? = nil,
        retries: Int = 2
    ) async throws -> Data? {
        let data = try await transport.send(request(path: path, method: method, body: body), retries: retries)
        return data.isEmpty ? nil : data
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
        let isLocal: Bool?

        enum CodingKeys: String, CodingKey {
            case id, uri, name, artists, album
            case durationMs = "duration_ms"
            case isPlayable = "is_playable"
            case isLocal = "is_local"
        }

        var toTrack: Track? {
            guard let id, let uri, let name else { return nil }
            guard isPlayable ?? true else { return nil } // unavailable in market
            guard isLocal != true, uri.hasPrefix("spotify:track:") else { return nil }
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

    struct LikedTracksPage {
        let tracks: [Track]
        let total: Int
        let nextOffset: Int?
        let rawCount: Int
    }

    private struct PagedTracksDTO: Decodable {
        struct Item: Decodable { let track: TrackDTO? }
        let items: [Item?]
        let total: Int
        let offset: Int?
        let next: String?

        func decoded(after requestedOffset: Int) throws -> LikedTracksPage {
            let page = PlaylistPageDTO(items: items, offset: offset, next: next)
            let nextOffset = try page.nextOffset(after: requestedOffset)
            let tracks = items.enumerated().compactMap { index, item -> Track? in
                guard var track = item?.track?.toTrack else { return nil }
                track.contextPosition = .init(source: "liked", index: requestedOffset + index)
                return track
            }
            return .init(tracks: tracks, total: total, nextOffset: nextOffset, rawCount: items.count)
        }
    }

    private struct PlaylistItemDTO: Decodable {
        let item: TrackDTO?
        let track: TrackDTO?
        let is_local: Bool?

        var playableTrack: Track? {
            guard is_local != true else { return nil }
            return (item ?? track)?.toTrack
        }
    }

    /// Keep null slots until after assigning the server position. A page of
    /// unavailable entries still advances pagination by its raw item count.
    private struct PlaylistPageDTO<Item: Decodable>: Decodable {
        let items: [Item?]
        let offset: Int?
        let next: String?

        func nextOffset(after requestedOffset: Int) throws -> Int? {
            guard offset == nil || offset == requestedOffset else {
                throw APIError.http(0, "Spotify returned an unexpected playlist page offset")
            }
            guard next != nil else { return nil }
            guard !items.isEmpty else {
                throw APIError.http(0, "Spotify returned an empty playlist page with more results")
            }
            return requestedOffset + items.count
        }
    }

    private struct PlaylistDTO: Codable {
        let id: String
        let name: String
        let snapshotId: String?
        let images: [Image]?
        let owner: OwnerDTO?
        struct ItemsSummaryDTO: Codable { let total: Int? }
        let items: ItemsSummaryDTO?
        let tracks: ItemsSummaryDTO?

        struct OwnerDTO: Codable {
            let id: String?
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, images, owner, items, tracks
            case snapshotId = "snapshot_id"
        }

        var toPlaylistInfo: PlaylistInfo {
            PlaylistInfo(
                id: id,
                name: name,
                trackCount: items?.total ?? tracks?.total ?? 0,
                artworkURL: images?.first?.url,
                ownerId: owner?.id
            )
        }
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
            let items: [TrackDTO?]?
            let total: Int?
            let offset: Int?
            let next: String?
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

    private struct SavedAlbumItemDTO: Codable {
        let addedAt: String?
        let album: DiscographyAlbumDTO

        enum CodingKeys: String, CodingKey {
            case addedAt = "added_at"
            case album
        }

        var toSavedAlbum: SavedAlbum {
            SavedAlbum(
                album: album.toAlbumInfo,
                addedAt: addedAt.flatMap(SpotifyClient.parseISO8601)
            )
        }
    }

    private struct PagedSavedAlbumsDTO: Codable {
        let items: [SavedAlbumItemDTO]?
        let total: Int
    }

    private struct FollowedArtistsDTO: Codable {
        struct ArtistsPage: Codable {
            struct Cursors: Codable {
                let after: String?
            }

            let items: [ArtistDTO]?
            let cursors: Cursors?
            let next: String?
            let total: Int
        }

        let artists: ArtistsPage
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

    private struct TracksBatchDTO: Codable {
        let tracks: [TrackDTO]?
    }

    private struct PlayerQueueDTO: Codable {
        let currentlyPlaying: TrackDTO?
        let queue: [TrackDTO]?

        enum CodingKeys: String, CodingKey {
            case currentlyPlaying = "currently_playing"
            case queue
        }
    }

    private struct PlayHistoryDTO: Codable {
        struct Item: Codable {
            struct Context: Codable {
                let uri: String?
                let type: String?
            }
            let track: TrackDTO?
            let context: Context?
        }
        let items: [Item]
    }

    private struct TopTracksPageDTO: Codable {
        let items: [TrackDTO]
    }

    private struct TopArtistsPageDTO: Codable {
        let items: [ArtistDTO]
    }

    private struct SaveTracksBody: Codable {
        let ids: [String]
    }

    private struct CreatePlaylistBody: Codable {
        let name: String
        /// Must be sent explicitly as "" — omitting the key makes Spotify
        /// store the literal string "null" as the description (observed
        /// live 2026-08-21; NullSpot sends `description ?? ""` for the
        /// same reason).
        let description: String
        let isPublic: Bool

        enum CodingKeys: String, CodingKey {
            case name, description
            case isPublic = "public"
        }
    }

    private struct PlaylistItemsBody: Codable {
        let uris: [String]
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

    /// Batch track lookup, ≤50 ids per request (queue metadata resolution).
    func tracks(ids: [String]) async throws -> [Track] {
        try await ids.isEmpty ? [] : ids.chunked(into: 50).mapAsync { chunk in
            let dto: TracksBatchDTO = try await self.get(
                "/v1/tracks", query: ["ids": chunk.joined(separator: ",")]
            )
            return (dto.tracks ?? []).compactMap(\ .toTrack)
        }.flatMap { $0 }
    }

    /// The active device's queue: current track + upcoming, in play order
    /// (user-added entries first, then the context continuation). Full track
    /// objects — no extra metadata resolution needed.
    func playerQueue() async throws -> (current: Track?, upcoming: [Track]) {
        let dto: PlayerQueueDTO? = try await get("/v1/me/player/queue")
        return (dto?.currentlyPlaying?.toTrack, (dto?.queue ?? []).compactMap(\.toTrack))
    }

    /// All playlists in the user's library (owned + followed), paginated.
    func playlists() async throws -> [PlaylistInfo] {
        var result: [PlaylistInfo] = []
        var offset = 0
        let limit = 50
        while true {
            let page: PlaylistPageDTO<PlaylistDTO> = try await get(
                "/v1/me/playlists",
                query: ["limit": "\(limit)", "offset": "\(offset)"]
            )
            for p in page.items.compactMap({ $0 }) {
                result.append(p.toPlaylistInfo)
            }
            guard let next = try page.nextOffset(after: offset) else { break }
            offset = next
        }
        return result
    }

    /// Tracks of a playlist, paginated.
    func playlistTracks(_ playlistId: String) async throws -> [Track] {
        var result: [Track] = []
        var offset = 0
        let limit = 50
        while true {
            let page: PlaylistPageDTO<PlaylistItemDTO> = try await get(
                "/v1/playlists/\(playlistId)/items",
                query: ["limit": "\(limit)", "offset": "\(offset)"]
            )
            let next = try page.nextOffset(after: offset)
            result += page.items.enumerated().compactMap { index, item in
                guard var track = item?.playableTrack else { return nil }
                track.contextPosition = .init(source: "spotify:playlist:\(playlistId)", index: offset + index)
                return track
            }
            guard let next else { break }
            offset = next
        }
        return result
    }

    struct SessionLibraryError: LocalizedError, Decodable {
        let code: String
        let message: String
        var errorDescription: String? { message }
    }

    /// Shared decoder/walker for the Rust bridge and offline protocol fixtures.
    /// One revision must cover the whole list; never cache a mixed snapshot.
    static func sessionPlaylistTracks(
        _ playlistID: String,
        readPage: (Int) async throws -> Data
    ) async throws -> [Track] {
        struct Envelope: Decodable { let error: SessionLibraryError? }
        struct Header: Decodable { let snapshot_id: String; let total: Int }
        var tracks: [Track] = []
        var offset = 0
        var revision: String?
        var total: Int?
        while true {
            try Task.checkCancellation()
            let data = try await readPage(offset)
            try Task.checkCancellation()
            let decoder = JSONDecoder()
            if let error = try decoder.decode(Envelope.self, from: data).error {
                if error.code == "cancelled" { throw CancellationError() }
                throw error
            }
            let header = try decoder.decode(Header.self, from: data)
            let page = try decoder.decode(PlaylistPageDTO<PlaylistItemDTO>.self, from: data)
            guard !header.snapshot_id.isEmpty, header.total >= 0,
                  page.offset == offset, page.items.count <= 50,
                  page.items.count == min(50, max(0, header.total - offset)),
                  revision == nil || revision == header.snapshot_id,
                  total == nil || total == header.total else {
                throw SessionLibraryError(code: "changed", message: "Playlist changed while loading. Please retry.")
            }
            let next = try page.nextOffset(after: offset)
            guard (next != nil) == (offset + page.items.count < header.total) else {
                throw SessionLibraryError(code: "invalid_response", message: "Incomplete playlist response")
            }
            revision = header.snapshot_id
            total = header.total
            tracks += page.items.enumerated().compactMap { index, item in
                guard var track = item?.playableTrack else { return nil }
                track.contextPosition = .init(source: "spotify:playlist:\(playlistID)", index: offset + index)
                return track
            }
            guard let next else { return tracks }
            offset = next
        }
    }

    /// First page of Liked Songs plus the library total. Used as a cheap
    /// change probe so a revisit does not re-page the whole collection.
    func likedTracksPrefix(limit: Int = 50) async throws -> LikedTracksPage {
        let page: PagedTracksDTO = try await get(
            "/v1/me/tracks",
            query: ["limit": "\(Self.clampedLimit(limit))", "offset": "0"]
        )
        return try page.decoded(after: 0)
    }

    /// Continue from the server prefix's raw offset, not the number of visible
    /// songs or a presumed 50-row page. A changing total is not a full snapshot.
    func likedTracks(after prefix: LikedTracksPage? = nil, pageSize: Int = 50) async throws -> [Track] {
        let first: LikedTracksPage
        if let prefix { first = prefix }
        else { first = try await likedTracksPrefix(limit: pageSize) }
        var result = first.tracks
        var nextOffset = first.nextOffset
        while let offset = nextOffset {
            let dto: PagedTracksDTO = try await get(
                "/v1/me/tracks",
                query: ["limit": "\(Self.clampedLimit(pageSize))", "offset": "\(offset)"]
            )
            let page = try dto.decoded(after: offset)
            guard page.total == first.total else {
                throw APIError.http(0, "Liked Songs changed while loading. Please retry.")
            }
            result += page.tracks
            nextOffset = page.nextOffset
        }
        return result
    }

    // MARK: - Personalized home

    /// Clamps a page size into the endpoint's valid 1…50 range.
    static func clampedLimit(_ limit: Int) -> Int {
        min(max(limit, 1), 50)
    }

    /// Static decode entry points (shared with the state reducer tests so
    /// response parsing stays pure and covered).
    static func decodeRecentlyPlayed(_ data: Data) throws -> [PlayHistoryItem] {
        let dto = try JSONDecoder().decode(PlayHistoryDTO.self, from: data)
        return dto.items.compactMap { item in
            guard let track = item.track?.toTrack else { return nil }
            return PlayHistoryItem(
                track: track,
                contextURI: item.context?.uri,
                contextType: item.context?.type
            )
        }
    }

    static func decodeTopTracks(_ data: Data) throws -> [Track] {
        let dto = try JSONDecoder().decode(TopTracksPageDTO.self, from: data)
        return dto.items.compactMap(\.toTrack)
    }

    static func decodeTopArtists(_ data: Data) throws -> [Artist] {
        let dto = try JSONDecoder().decode(TopArtistsPageDTO.self, from: data)
        return dto.items.compactMap(\.toArtist)
    }

    /// Recently played history (GET /v1/me/player/recently-played). One page
    /// is enough for the home strip; the endpoint is cursor-based, so limit
    /// only controls how far back the server looks (max 50).
    func recentlyPlayed(limit: Int = 20) async throws -> [PlayHistoryItem] {
        try Self.decodeRecentlyPlayed(
            try await fetch(
                "/v1/me/player/recently-played",
                query: ["limit": "\(Self.clampedLimit(limit))"]
            )
        )
    }

    /// The user's most-played tracks (GET /v1/me/top/tracks).
    func topTracks(timeRange: TopTimeRange = .shortTerm, limit: Int = 10) async throws -> [Track] {
        try Self.decodeTopTracks(
            try await fetch(
                "/v1/me/top/tracks",
                query: [
                    "time_range": timeRange.rawValue,
                    "limit": "\(Self.clampedLimit(limit))",
                ]
            )
        )
    }

    /// The user's most-played artists (GET /v1/me/top/artists). Full artist
    /// objects — portraits included, no extra profile round trip.
    func topArtists(timeRange: TopTimeRange = .mediumTerm, limit: Int = 10) async throws -> [Artist] {
        try Self.decodeTopArtists(
            try await fetch(
                "/v1/me/top/artists",
                query: [
                    "time_range": timeRange.rawValue,
                    "limit": "\(Self.clampedLimit(limit))",
                ]
            )
        )
    }

    // MARK: - Likes round-trip (M4.2)

    /// Which of the given track ids are in the user's Liked Songs (≤50 ids).
    /// NOTE: the server lags behind its own PUT/DELETE by a moment — never
    /// use this to confirm a save the app just made; keep the optimistic UI.
    func likedContains(ids: [String]) async throws -> [Bool] {
        try await get("/v1/me/tracks/contains", query: ["ids": ids.joined(separator: ",")])
    }

    /// Saves tracks to Liked Songs (PUT /v1/me/tracks).
    func saveTracks(ids: [String]) async throws {
        try await mutateSavedTracks(ids: ids, method: "PUT")
    }

    /// Removes tracks from Liked Songs (DELETE /v1/me/tracks).
    func removeTracks(ids: [String]) async throws {
        try await mutateSavedTracks(ids: ids, method: "DELETE")
    }

    private func mutateSavedTracks(ids: [String], method: String, retries: Int = 2) async throws {
        let body = try JSONEncoder().encode(SaveTracksBody(ids: ids))
        _ = try await mutate(path: "/v1/me/tracks", method: method, body: body, retries: retries)
    }

    // MARK: - Saved Albums (M4.3)

    /// One page of the user's saved albums (server order: newest first).
    func savedAlbumsPage(offset: Int, limit: Int = 50) async throws -> (albums: [SavedAlbum], total: Int) {
        let page: PagedSavedAlbumsDTO = try await get(
            "/v1/me/albums",
            query: ["limit": "\(limit)", "offset": "\(offset)"]
        )
        return ((page.items ?? []).map(\.toSavedAlbum), page.total)
    }

    /// Remaining pages of the saved-albums library after an already-fetched
    /// prefix (mirrors likedTracks(after:)). Reports whether every page kept
    /// the expected total so callers can reject a snapshot that drifted while
    /// offset pagination was in progress.
    func savedAlbums(
        offset: Int,
        expectedTotal: Int
    ) async throws -> (albums: [SavedAlbum], totalsMatch: Bool) {
        var result: [SavedAlbum] = []
        var cursor = offset
        var totalsMatch = true
        while cursor < expectedTotal {
            let page = try await savedAlbumsPage(offset: cursor)
            totalsMatch = totalsMatch && page.total == expectedTotal
            guard !page.albums.isEmpty else {
                totalsMatch = false
                break
            }
            result += page.albums
            cursor += page.albums.count
        }
        return (result, totalsMatch)
    }

    // MARK: - Unified library writes and probes (M4.3)

    /// Saved-state probe via the unified library endpoint. Batched at 40
    /// URIs (roadmap cap). The server lags behind its own writes — never use
    /// this to confirm a save the app just made; keep the optimistic UI.
    func libraryContainsAlbums(ids: [String]) async throws -> [Bool] {
        try await libraryContains(uris: ids.map { "spotify:album:\($0)" })
    }

    func libraryContainsArtists(ids: [String]) async throws -> [Bool] {
        try await libraryContains(uris: ids.map { "spotify:artist:\($0)" })
    }

    private func libraryContains(uris: [String]) async throws -> [Bool] {
        var flags: [Bool] = []
        for chunk in uris.chunked(into: 40) {
            let batch: [Bool] = try await get(
                "/v1/me/library/contains",
                query: ["uris": chunk.joined(separator: ",")]
            )
            flags += batch
        }
        return flags
    }

    /// Saves albums to the user's library (PUT /v1/me/library).
    func saveAlbumsToLibrary(ids: [String]) async throws {
        try await mutateLibrary(uris: ids.map { "spotify:album:\($0)" }, method: "PUT")
    }

    /// Removes albums from the user's library (DELETE /v1/me/library).
    func removeAlbumsFromLibrary(ids: [String]) async throws {
        try await mutateLibrary(uris: ids.map { "spotify:album:\($0)" }, method: "DELETE")
    }

    func saveArtistsToLibrary(ids: [String]) async throws {
        try await mutateLibrary(uris: ids.map { "spotify:artist:\($0)" }, method: "PUT")
    }

    func removeArtistsFromLibrary(ids: [String]) async throws {
        try await mutateLibrary(uris: ids.map { "spotify:artist:\($0)" }, method: "DELETE")
    }

    /// PUT/DELETE /v1/me/library — the unified save surface. Never regress to
    /// deprecated album-specific or /v1/me/following write endpoints.
    private func mutateLibrary(uris: [String], method: String, retries: Int = 2) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/library")!
        components.queryItems = [URLQueryItem(name: "uris", value: uris.joined(separator: ","))]
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await transport.send(req, retries: retries)
    }

    // MARK: - Followed Artists (M4.9)

    /// One cursor-paginated page of artists followed by the current user.
    func followedArtistsPage(
        after: String? = nil,
        limit: Int = 50
    ) async throws -> FollowedArtistsPage {
        var query = ["type": "artist", "limit": "\(limit)"]
        if let after { query["after"] = after }
        return try Self.decodeFollowedArtistsPage(
            try await fetch("/v1/me/following", query: query)
        )
    }

    static func decodeFollowedArtistsPage(_ data: Data) throws -> FollowedArtistsPage {
        let response = try JSONDecoder().decode(FollowedArtistsDTO.self, from: data)
        return FollowedArtistsPage(
            artists: (response.artists.items ?? []).compactMap(\.toArtist),
            after: response.artists.next == nil ? nil : response.artists.cursors?.after,
            total: response.artists.total
        )
    }

    // MARK: - Playlist writes (M4.5)

    /// Creates a private playlist for the current user and returns the
    /// created playlist decoded from the response (POST
    /// /v1/me/playlists) — no synthesized ids, no library refresh required.
    func createPlaylist(name: String) async throws -> PlaylistInfo {
        let body = try Self.encodeCreatePlaylistBody(name: name)
        guard let data = try await mutate(
            path: "/v1/me/playlists",
            method: "POST",
            body: body
        ) else {
            throw APIError.http(0, "create playlist returned no body")
        }
        return try Self.decodeCreatedPlaylist(data)
    }

    /// Static encode entry point (shared with the state tests so the
    /// create-body shape — explicit empty description, private — stays
    /// covered).
    static func encodeCreatePlaylistBody(name: String) throws -> Data {
        try JSONEncoder().encode(CreatePlaylistBody(name: name, description: "", isPublic: false))
    }

    /// Static decode entry point (shared with the state tests so the
    /// create-playlist response parsing stays pure and covered).
    static func decodeCreatedPlaylist(_ data: Data) throws -> PlaylistInfo {
        try JSONDecoder().decode(PlaylistDTO.self, from: data).toPlaylistInfo
    }

    /// Appends one track to a playlist (POST /v1/playlists/{id}/items —
    /// not the legacy /tracks route).
    func addTrackToPlaylist(playlistId: String, uri: String) async throws {
        let body = try JSONEncoder().encode(PlaylistItemsBody(uris: [uri]))
        _ = try await mutate(path: "/v1/playlists/\(playlistId)/items", method: "POST", body: body)
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
        var result: [Track] = []
        var offset = 0
        var page: PlaylistPageDTO<TrackDTO>
        if let embedded = dto.tracks, let items = embedded.items {
            page = .init(items: items, offset: embedded.offset, next: embedded.next)
        } else {
            page = try await get("/v1/albums/\(albumId)/tracks",
                query: ["limit": "50", "offset": "0", "market": "from_token"])
        }
        while true {
            let next = try page.nextOffset(after: offset)
            result += page.items.enumerated().compactMap { index, item in
                guard var track = item?.toTrack else { return nil }
                track.contextPosition = .init(source: "spotify:album:\(albumId)", index: offset + index)
                return track.withAlbum(dto.name, artwork: dto.images?.first?.url, albumId: albumId)
            }
            guard let next else { break }
            offset = next
            page = try await get("/v1/albums/\(albumId)/tracks",
                query: ["limit": "50", "offset": "\(offset)", "market": "from_token"])
        }
        return result
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(dropFirst($0).prefix(size)) }
    }

    func mapAsync<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}


/// Request pacing per transport, with a durable installation-wide cooldown. Playback credentials and librespot never pass through this object.
final class SpotifyWebTransport: @unchecked Sendable {
    private let lock = NSLock()
    private let session: URLSession
    private let safetyStore: TrafficSafetyStore
    private let gate: SpotifyRequestGate
    private let requests = SpotifyRequestCoordinator()
    private var valid = true
    private var excessiveCooldown = false
    private var cooldownUntil = ContinuousClock.now
    private var nextStart = ContinuousClock.now

    init(session: URLSession = .shared, safetyStore: TrafficSafetyStore = .shared,
         gate: SpotifyRequestGate = .shared) {
        self.session = session
        self.safetyStore = safetyStore
        self.gate = gate
    }

    func invalidate() {
        lock.withLock { valid = false }
        Task { await requests.invalidate() }
    }

    static func retryAfter(_ header: String?, now: Date = Date()) -> TimeInterval {
        if let header, let seconds = Double(header), seconds.isFinite, seconds >= 0 {
            return max(1, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        if let header, let date = formatter.date(from: header) {
            return max(1, date.timeIntervalSince(now))
        }
        return 5
    }

    private func reserveStart() throws -> Duration {
        try lock.withLock {
            guard valid else { throw CancellationError() }
            if excessiveCooldown {
                throw SpotifyClient.APIError.http(429, "Spotify requested an unusually long cooldown.")
            }
            let durableDelay = try safetyStore.cooldown(.web)
            guard durableDelay <= 30 else {
                throw SpotifyClient.APIError.http(429, "Spotify requested a cooldown. Try again later.")
            }
            let now = ContinuousClock.now
            let delay = max(.seconds(durableDelay), now.duration(to: max(cooldownUntil, nextStart)))
            // Report long cooldowns promptly instead of leaving every library
            // screen spinning. The full deadline remains enforced on retries.
            if delay > .seconds(30) {
                throw SpotifyClient.APIError.http(429, "Spotify requested a cooldown. Try again later.")
            }
            if delay <= .zero { nextStart = now.advanced(by: .milliseconds(150)) }
            return max(.zero, delay)
        }
    }

    private func recordRateLimit(_ header: String?) throws {
        let delay = Self.retryAfter(header)
        try safetyStore.recordCooldown(.web, seconds: delay)
        lock.withLock {
            // Reject an unrepresentable deadline without making more requests.
            guard delay < Double(Int32.max) else {
                excessiveCooldown = true
                return
            }
            // No cap: in particular, a 120s Retry-After must never become 30s.
            cooldownUntil = max(cooldownUntil, .now.advanced(by: .seconds(delay)))
        }
    }

    func send(_ request: URLRequest, retries: Int = 2) async throws -> Data {
        guard lock.withLock({ valid }) else { throw CancellationError() }
        return try await requests.perform(request, retries: retries) { [self] in
            try await sendUnshared(request, retries: retries)
        }
    }

    private enum Attempt { case wait(Duration), response(Data, Int) }

    private func attempt(_ request: URLRequest) async throws -> Attempt {
        try Task.checkCancellation()
        let wait = try reserveStart()
        if wait > .zero { return .wait(wait) }
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 429 {
            // Publish the hold before handing this permit to another request.
            try recordRateLimit(http?.value(forHTTPHeaderField: "Retry-After"))
        }
        guard lock.withLock({ valid }) else { throw CancellationError() }
        return .response(data, status)
    }

    private func sendUnshared(_ request: URLRequest, retries: Int) async throws -> Data {
        var retry = 0
        while true {
            try Task.checkCancellation()
            try await gate.acquire()
            let result: Attempt
            do {
                result = try await attempt(request)
            } catch {
                await gate.release()
                throw error
            }
            await gate.release()
            switch result {
            case let .wait(duration):
                try await Task.sleep(for: duration)
            case let .response(data, status):
                if status == 429, retry < retries {
                    retry += 1
                    continue
                }
                if status == 401 { throw SpotifyClient.APIError.needsAuth }
                guard (200..<300).contains(status) else {
                    throw SpotifyClient.APIError.http(status, String(data: data, encoding: .utf8) ?? "")
                }
                return data
            }
        }
    }
}

/// Shared across transports/account changes. Rate spacing alone cannot bound
/// requests that remain in flight during a slow network or server response.
actor SpotifyRequestGate {
    static let shared = SpotifyRequestGate(limit: 2)
    private let limit: Int
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    init(limit: Int) { precondition(limit > 0); self.limit = limit }

    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                if active < limit {
                    active += 1
                    continuation.resume()
                } else {
                    waiting.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
    func release() {
        precondition(active > 0)
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().1.resume() }
    }
}

/// Coalesce identical GETs only. Every caller has independent cancellation;
/// the underlying task is cancelled when the last waiter leaves or on sign-out.
private actor SpotifyRequestCoordinator {
    private enum Key: Hashable { case read(URLRequest, Int), write(UUID) }
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Data, Error>]
    }
    private var valid = true
    private var flights: [Key: Flight] = [:]

    func perform(_ request: URLRequest, retries: Int,
                 operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let key: Key = (request.httpMethod ?? "GET") == "GET" ? .read(request, retries) : .write(UUID())
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard valid else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                if flights[key] != nil {
                    flights[key]?.waiters[waiter] = continuation
                    return
                }
                let id = UUID()
                let task = Task {
                    let result: Result<Data, Error>
                    do { result = .success(try await operation()) }
                    catch { result = .failure(error) }
                    self.complete(key, id: id, result: result)
                }
                flights[key] = Flight(id: id, task: task, waiters: [waiter: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key, waiter: waiter) }
        }
    }
    private func complete(_ key: Key, id: UUID, result: Result<Data, Error>) {
        guard let flight = flights[key], flight.id == id else { return }
        flights.removeValue(forKey: key)
        for waiter in flight.waiters.values { waiter.resume(with: result) }
    }
    private func cancel(_ key: Key, waiter: UUID) {
        guard var flight = flights[key], let continuation = flight.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key)
            flight.task.cancel()
        } else { flights[key] = flight }
    }
    func invalidate() {
        valid = false
        let old = flights.values
        flights.removeAll()
        for flight in old {
            flight.task.cancel()
            for waiter in flight.waiters.values { waiter.resume(throwing: CancellationError()) }
        }
    }
}
