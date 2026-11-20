import Foundation
import NanyinKit
import Observation

/// One row of a track table, from whichever Web API object listed it.
/// Display strings are computed once here, not per cell as rows scroll.
struct TrackRow: Identifiable, Hashable, Sendable {
    /// Unique within the list: the same track may appear twice in a playlist.
    let id: Int
    let uri: String
    let name: String
    let artistNames: String
    let album: String
    let duration: String
    let popularity: Int?
    let added: String
    let isPlayable: Bool
    /// For "Show Album" and "Show Artist" (the first credited artist).
    let albumURI: String?
    let artistURI: String?

    init(index: Int, uri: String, name: String, artists: String, album: String, durationMs: Int,
         popularity: Int? = nil, added: Date? = nil, isPlayable: Bool = true,
         albumURI: String? = nil, artistURI: String? = nil) {
        id = index
        self.albumURI = albumURI
        self.artistURI = artistURI
        self.uri = uri
        self.name = name
        artistNames = artists
        self.album = album
        duration = Self.format(ms: durationMs)
        self.popularity = popularity
        self.added = added?.formatted(date: .numeric, time: .omitted) ?? ""
        self.isPlayable = isPlayable
    }

    init(index: Int, track: Track, addedAt: String? = nil) {
        self.init(
            index: index, uri: track.uri, name: track.name, artists: track.artists.names, album: track.album?.name ?? "",
            durationMs: track.duration_ms, popularity: track.popularity,
            added: addedAt.flatMap { Self.isoParser.date(from: $0) },
            isPlayable: track.is_playable ?? true, albumURI: track.album?.uri, artistURI: track.artists.first?.uri)
    }

    init(index: Int, track: AlbumTrack, album: Album) {
        self.init(index: index, uri: track.uri, name: track.name, artists: track.artists.names, album: album.name,
                  durationMs: track.duration_ms, albumURI: album.uri, artistURI: track.artists.first?.uri)
    }

    init(index: Int, track: CoreTrack, added: Date? = nil) {
        self.init(index: index, uri: track.uri, name: track.name, artists: track.artistNames, album: track.album,
                  durationMs: track.durationMs, added: added,
                  albumURI: track.albumURI, artistURI: track.artists.first?.uri)
    }

    /// "3:07".
    static func format(ms: Int) -> String {
        Duration.milliseconds(max(ms, 0)).formatted(.time(pattern: .minuteSecond))
    }

    private nonisolated(unsafe) static let isoParser = ISO8601DateFormatter()
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
    static func sessionPlaylist(session: PlaybackSession, id: String) -> TrackList {
        TrackList(contextURI: "spotify:playlist:\(id)") { offset in
            let page = try await session.readPlaylist(id: id, offset: offset)
            let rows = page.rows.map { row in
                TrackRow(index: row.index, track: row.track,
                         added: row.addedAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) })
            }
            return (rows, page.total, page.next)
        }
    }

    static func recentlyPlayed(api: SpotifyWebAPI) -> TrackList {
        TrackList(contextURI: nil) { _ in
            var seen = Set<String>()
            let tracks = try await api.recentlyPlayed().map(\.track).filter { seen.insert($0.uri).inserted }
            return (tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element) }, tracks.count, nil)
        }
    }
}
