import Foundation
import NanyinKit
import Observation

/// One row of a track table, from whichever Web API object listed it.
/// Display strings are computed once here, not per cell as rows scroll.
struct TrackRow: Identifiable, Hashable, Sendable {
    /// A credited artist, and their page when Spotify gives one.
    struct Artist: Hashable, Sendable {
        let name: String
        let route: Route?

        init(name: String, uri: String?) {
            self.name = name
            route = uri.flatMap(Route.init(uri:))
        }
    }

    /// Unique within the list: the same track may appear twice in a playlist.
    let id: Int
    let uri: String
    let name: String
    let artists: [Artist]
    let album: String
    let durationMs: Int
    let duration: String
    let popularity: Int?
    let addedDate: Date?
    let added: String
    let isPlayable: Bool
    /// For the album link and "Show Album".
    let albumRoute: Route?

    init(index: Int, uri: String, name: String, artists: [Artist], album: String, durationMs: Int,
         popularity: Int? = nil, added: Date? = nil, isPlayable: Bool = true, albumURI: String? = nil) {
        id = index
        albumRoute = albumURI.flatMap(Route.init(uri:))
        self.uri = uri
        self.name = name
        self.artists = artists
        self.album = album
        self.durationMs = max(durationMs, 0)
        duration = Self.format(ms: durationMs)
        self.popularity = popularity
        addedDate = added
        self.added = added?.formatted(date: .numeric, time: .omitted) ?? ""
        self.isPlayable = isPlayable
    }

    init(index: Int, track: Track, addedAt: String? = nil) {
        self.init(
            index: index, uri: track.uri, name: track.name, artists: track.artists.map(Artist.init),
            album: track.album?.name ?? "", durationMs: track.duration_ms, popularity: track.popularity,
            added: addedAt.flatMap { Self.isoParser.date(from: $0) },
            isPlayable: track.is_playable ?? true, albumURI: track.album?.uri)
    }

    init(index: Int, track: AlbumTrack, album: Album) {
        self.init(index: index, uri: track.uri, name: track.name, artists: track.artists.map(Artist.init),
                  album: album.name, durationMs: track.duration_ms, albumURI: album.uri)
    }

    init(index: Int, track: CoreTrack, added: Date? = nil) {
        self.init(index: index, uri: track.uri, name: track.name,
                  artists: track.artists.map(Artist.init), album: track.album,
                  durationMs: track.durationMs, added: added, albumURI: track.albumURI)
    }

    var artistNames: String { artists.map(\.name).joined(separator: ", ") }

    func withID(_ newID: Int) -> TrackRow {
        TrackRow(
            index: newID, uri: uri, name: name, artists: artists, album: album,
            durationMs: durationMs, popularity: popularity, added: addedDate,
            isPlayable: isPlayable, albumURI: albumRoute.flatMap { route in
                if case .album(let id) = route { "spotify:album:\(id)" } else { nil }
            }
        )
    }

    /// "3:07".
    static func format(ms: Int) -> String {
        Duration.milliseconds(max(ms, 0)).formatted(.time(pattern: .minuteSecond))
    }

    /// "5 hr 3 min", "42 min", or "35 sec".
    static func formatTotal(ms: Int) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        }
        if totalMinutes > 0 {
            return "\(totalMinutes) min"
        }
        return "\(totalSeconds) sec"
    }

    private nonisolated(unsafe) static let isoParser = ISO8601DateFormatter()
}

extension TrackRow.Artist {
    init(_ ref: ArtistRef) {
        self.init(name: ref.name, uri: ref.uri)
    }

    init(_ artist: CoreTrack.Artist) {
        self.init(name: artist.name, uri: artist.uri)
    }
}

/// The rows of one page (a playlist, Liked Songs, an album) and the context
/// they play in.
@MainActor
final class TrackList {
    let pages: Pager<TrackRow, Int>
    /// The context to play from: rows start playing within it.
    let contextURI: String?

    init(contextURI: String?, fetch: @escaping (_ offset: Int) async throws -> Pager<TrackRow, Int>.Page) {
        self.contextURI = contextURI
        pages = Pager(first: 0, fetch: fetch)
    }

    /// A list whose rows are already known.
    init(rows: [TrackRow], contextURI: String? = nil) {
        self.contextURI = contextURI
        pages = Pager(items: rows)
    }

    var rows: [TrackRow] { pages.items }
}

extension TrackList {
    static func liked(api: SpotifyWebAPI, username: String, stars: Stars) -> TrackList {
        TrackList(contextURI: "spotify:user:\(username):collection") { offset in
            let page = try await api.savedTracks(offset: offset)
            let rows = page.items.enumerated().map {
                TrackRow(index: offset + $0.offset, track: $0.element.track, addedAt: $0.element.added_at)
            }
            stars.learn(rows.map(\.uri), starred: true)
            return (rows, page.total, page.next == nil ? nil : offset + page.items.count)
        }
    }

    static func playlist(api: SpotifyWebAPI, id: String) -> TrackList {
        TrackList(contextURI: "spotify:playlist:\(id)") { offset in
            let page = try await api.playlistItems(id, offset: offset)
            // Removed or unavailable entries come back as null and are
            // skipped, but still count towards the next offset.
            let rows = page.items.enumerated().compactMap { item -> TrackRow? in
                item.element.playable.map { TrackRow(index: offset + item.offset, track: $0, addedAt: item.element.added_at) }
            }
            return (rows, page.total, page.next == nil ? nil : offset + page.items.count)
        }
    }

    /// A playlist the Web API grant may not read (one the listener does not
    /// own), read through the playback session instead.
    static func sessionPlaylist(
        session: PlaybackSession,
        id: String,
        onMetadata: @escaping @MainActor (SessionPlaylistPage) -> Void = { _ in }
    ) -> TrackList {
        TrackList(contextURI: "spotify:playlist:\(id)") { offset in
            let page = try await session.readPlaylist(id: id, offset: offset)
            if offset == 0 { onMetadata(page) }
            let rows = page.rows.map { row in
                TrackRow(index: row.index, track: row.track,
                         added: row.addedAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) })
            }
            return (rows, page.total, page.next)
        }
    }

    /// An artist's popular songs, read through the playback session (the
    /// Web API refuses them to Development Mode apps).
    static func topTracks(session: PlaybackSession, artistID: String) -> TrackList {
        TrackList(contextURI: "spotify:artist:\(artistID)") { _ in
            let tracks = try await session.readTopTracks(artistID: artistID)
            return (tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element) }, tracks.count, nil)
        }
    }

    static func recentlyPlayed(
        api: SpotifyWebAPI,
        history: PlayHistoryStore,
        onRemote: @escaping @MainActor ([PlayHistory]) -> Void = { _ in }
    ) -> TrackList {
        TrackList(contextURI: nil) { _ in
            let remote: [PlayHistory]
            do {
                remote = try await api.recentlyPlayed()
                onRemote(remote)
            } catch {
                guard !history.plays.isEmpty else { throw error }
                remote = []
            }
            let rows = Self.recentRows(local: history.plays, remote: remote)
            return (rows, rows.count, nil)
        }
    }

    static func mergedRecentlyPlayed(local: [PlayHistory], remote: [PlayHistory]) -> TrackList {
        TrackList(rows: recentRows(local: local, remote: remote))
    }

    private static func recentRows(local: [PlayHistory], remote: [PlayHistory]) -> [TrackRow] {
        var seen = Set<String>()
        let tracks = PlayHistoryMerger.merge(local: local, remote: remote)
            .map(\.track)
            .filter { seen.insert($0.uri).inserted }
        return tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element) }
    }

    static func topTracks(api: SpotifyWebAPI, timeRange: TopTimeRange) -> TrackList {
        TrackList(contextURI: nil) { _ in
            let page = try await api.topTracks(timeRange: timeRange, limit: 50)
            let rows = page.items.enumerated().map { TrackRow(index: $0.offset, track: $0.element) }
            return (rows, page.total ?? rows.count, nil)
        }
    }
}
