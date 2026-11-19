import Foundation
import NanyinKit
import Observation

/// One row of a track table, from whichever Web API object listed it.
struct TrackRow: Identifiable, Hashable, Sendable {
    /// Unique within the list: the same track may appear twice in a playlist.
    let id: Int
    let uri: String
    let name: String
    let artists: [ArtistRef]
    let album: String
    let albumURI: String?
    let durationMs: Int
    let popularity: Int?
    let addedAt: String?
    let isPlayable: Bool
    let explicit: Bool

    var artistNames: String { artists.map(\.name).joined(separator: ", ") }

    init(index: Int, track: Track, addedAt: String?) {
        id = index
        uri = track.uri
        name = track.name
        artists = track.artists
        album = track.album?.name ?? ""
        albumURI = track.album?.uri
        durationMs = track.duration_ms
        popularity = track.popularity
        self.addedAt = addedAt
        isPlayable = track.is_playable ?? true
        explicit = track.explicit ?? false
    }

    init(index: Int, track: AlbumTrack, album: Album) {
        id = index
        uri = track.uri
        name = track.name
        artists = track.artists
        self.album = album.name
        albumURI = album.uri
        durationMs = track.duration_ms
        popularity = nil
        addedAt = nil
        isPlayable = true
        explicit = track.explicit ?? false
    }
}

/// The rows of one page (a playlist, Liked Songs, an album), loaded from the
/// Web API a page at a time as the table scrolls towards the end.
@MainActor
@Observable
final class TrackList {
    typealias Page = (rows: [TrackRow], total: Int?, hasMore: Bool)

    private(set) var rows: [TrackRow] = []
    private(set) var total: Int?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var hasMore = true

    /// The context to play from: rows start playing within it.
    let contextURI: String?
    private let fetch: (_ offset: Int) async throws -> Page

    init(contextURI: String?, fetch: @escaping (_ offset: Int) async throws -> Page) {
        self.contextURI = contextURI
        self.fetch = fetch
    }

    /// Loads the next page unless one is loading or all are here.
    func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            do {
                let page = try await fetch(rows.count)
                rows += page.rows
                total = page.total
                hasMore = page.hasMore && !page.rows.isEmpty
            } catch {
                self.error = error.localizedDescription
            }
        }
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
            let rows = page.items.enumerated().map { TrackRow(index: offset + $0.offset, track: $0.element.track, addedAt: $0.element.added_at) }
            return (rows, page.total, page.next != nil)
        }
    }

    static func playlist(api: SpotifyWebAPI, id: String) -> TrackList {
        TrackList(contextURI: "spotify:playlist:\(id)") { offset in
            let page = try await api.playlistItems(id, offset: offset)
            let rows = page.items.enumerated().compactMap { item -> TrackRow? in
                guard let track = item.element.playable else { return nil }
                return TrackRow(index: offset + item.offset, track: track, addedAt: item.element.added_at)
            }
            return (rows, page.total, page.next != nil)
        }
    }

    static func album(_ album: Album) -> TrackList {
        let rows = (album.tracks?.items ?? []).enumerated().map { TrackRow(index: $0.offset, track: $0.element, album: album) }
        let list = TrackList(contextURI: album.uri) { _ in (rows, rows.count, false) }
        list.loadMore()
        return list
    }

    static func tracks(_ tracks: [Track], contextURI: String? = nil) -> TrackList {
        let rows = tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element, addedAt: nil) }
        let list = TrackList(contextURI: contextURI) { _ in (rows, rows.count, false) }
        list.loadMore()
        return list
    }
}
