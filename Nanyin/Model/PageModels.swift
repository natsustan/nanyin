import Foundation
import NanyinKit
import Observation

/// An album page: the album and its tracks, in one request.
@MainActor
@Observable
final class AlbumDetail {
    private(set) var album: Album?
    private(set) var tracks: TrackList?
    private(set) var error: String?

    init(id: String, api: SpotifyWebAPI) {
        Task {
            do {
                let album = try await api.album(id)
                self.album = album
                let rows = (album.tracks?.items ?? []).enumerated().map {
                    TrackRow(index: $0.offset, track: $0.element, album: album)
                }
                tracks = TrackList(rows: rows, contextURI: album.uri)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// An artist page: the artist, popular tracks and releases. Each is read
/// on its own, so one refused read leaves the others on the page.
@MainActor
@Observable
final class ArtistDetail {
    private(set) var artist: Artist?
    private(set) var topTracks: TrackList?
    private(set) var albums: [AlbumSummary] = []
    private(set) var error: String?
    private(set) var topTracksError: String?

    init(id: String, api: SpotifyWebAPI, session: PlaybackSession) {
        Task {
            do { artist = try await api.artist(id) } catch { self.error = error.localizedDescription }
        }
        Task {
            do { albums = try await api.artistAlbums(id).items } catch {}
        }
        Task {
            do {
                let tracks = try await session.readTopTracks(artistID: id)
                let rows = tracks.enumerated().map { TrackRow(index: $0.offset, track: $0.element) }
                topTracks = TrackList(rows: rows, contextURI: "spotify:artist:\(id)")
            } catch {
                topTracksError = error.localizedDescription
            }
        }
    }
}

/// One search: matching artists and albums, and the matching tracks.
@MainActor
@Observable
final class SearchResultsModel {
    private(set) var artists: [Artist] = []
    private(set) var albums: [AlbumSummary] = []
    private(set) var tracks: TrackList?
    private(set) var error: String?

    init(query: String, api: SpotifyWebAPI) {
        Task {
            do {
                let found = try await api.search(query)
                artists = found.artists?.items ?? []
                albums = found.albums?.items ?? []
                let rows = (found.tracks?.items ?? []).enumerated().map { TrackRow(index: $0.offset, track: $0.element) }
                tracks = TrackList(rows: rows)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
