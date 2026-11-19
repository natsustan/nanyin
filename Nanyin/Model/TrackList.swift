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

    init(index: Int, uri: String, name: String, artists: String, album: String, durationMs: Int,
         popularity: Int? = nil, addedAt: String? = nil, isPlayable: Bool = true) {
        id = index
        self.uri = uri
        self.name = name
        artistNames = artists
        self.album = album
        duration = Self.format(ms: durationMs)
        self.popularity = popularity
        added = addedAt.flatMap { Self.isoParser.date(from: $0) }?.formatted(date: .numeric, time: .omitted) ?? ""
        self.isPlayable = isPlayable
    }

    init(index: Int, track: Track, addedAt: String? = nil) {
        self.init(
            index: index, uri: track.uri, name: track.name, artists: track.artists.names, album: track.album?.name ?? "",
            durationMs: track.duration_ms, popularity: track.popularity, addedAt: addedAt,
            isPlayable: track.is_playable ?? true)
    }

    init(index: Int, track: AlbumTrack, album: Album) {
        self.init(index: index, uri: track.uri, name: track.name, artists: track.artists.names, album: album.name,
                  durationMs: track.duration_ms)
    }

    init(index: Int, track: CoreTrack) {
        self.init(index: index, uri: track.uri, name: track.name, artists: track.artistNames, album: track.album,
                  durationMs: track.durationMs)
    }

    /// "3:07".
    static func format(ms: Int) -> String {
        Duration.milliseconds(max(ms, 0)).formatted(.time(pattern: .minuteSecond))
    }

    private nonisolated(unsafe) static let isoParser = ISO8601DateFormatter()
}

/// The rows of one page (a playlist, Liked Songs, an album), loaded from the
/// Web API a page at a time as the table scrolls towards the end.
@MainActor
@Observable
final class TrackList {
    /// A fetched page and the offset of the next one (nil at the end).
    typealias Page = (rows: [TrackRow], total: Int?, next: Int?)

    private(set) var rows: [TrackRow] = []
    private(set) var total: Int?
    private(set) var isLoading = false
    private(set) var error: String?

    /// The context to play from: rows start playing within it.
    let contextURI: String?
    private var nextOffset: Int?
    private let fetch: (_ offset: Int) async throws -> Page

    init(contextURI: String?, fetch: @escaping (_ offset: Int) async throws -> Page) {
        self.contextURI = contextURI
        self.fetch = fetch
        nextOffset = 0
        loadMore()
    }

    /// A list whose rows are already known.
    init(rows: [TrackRow], contextURI: String? = nil) {
        self.contextURI = contextURI
        self.rows = rows
        total = rows.count
        fetch = { _ in ([], nil, nil) }
    }

    /// Loads the next page unless one is loading, all are here, or the last
    /// attempt failed (then only `retry` tries again).
    private func loadMore() {
        guard let offset = nextOffset, !isLoading, error == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let page = try await fetch(offset)
                rows += page.rows
                total = page.total
                nextOffset = page.next
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func retry() {
        error = nil
        loadMore()
    }

    /// Called as rows appear: fetches more when the end is near.
    func rowAppeared(_ index: Int) {
        if index >= rows.count - 20 { loadMore() }
    }
}

extension TrackList {
    static func liked(api: SpotifyWebAPI, username: String) -> TrackList {
        TrackList(contextURI: "spotify:user:\(username):collection") { offset in
            let page = try await api.savedTracks(offset: offset)
            let rows = page.items.enumerated().map {
                TrackRow(index: offset + $0.offset, track: $0.element.track, addedAt: $0.element.added_at)
            }
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

    static func recentlyPlayed(api: SpotifyWebAPI) -> TrackList {
        TrackList(contextURI: nil) { _ in
            var seen = Set<String>()
            let tracks = try await api.recentlyPlayed().map(\.track).filter { seen.insert($0.uri).inserted }
            return (tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element) }, tracks.count, nil)
        }
    }
}
