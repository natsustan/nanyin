import Foundation
import NanyinKit
import Observation

/// What a route shows, kept while the app runs so going back costs nothing.
enum PageContent {
    case tracks(TrackList)
    case album(AlbumDetail)
    case artist(ArtistDetail)
    case search(SearchResultsModel)
}

/// The signed-in account's playlists, and the content of every page opened.
@MainActor
@Observable
final class Library {
    private(set) var playlists: [Playlist] = []
    private(set) var playlistsError: String?
    /// Filled by `prepare` before a route is shown; views only read it.
    @ObservationIgnored private var pages: [Route: PageContent] = [:]
    private let api: SpotifyWebAPI
    private var username: String?

    init(api: SpotifyWebAPI) {
        self.api = api
    }

    func signedIn(as username: String, showing route: Route) {
        self.username = username
        prepare(route)
        Task { await loadPlaylists() }
    }

    func signedOut() {
        username = nil
        playlists = []
        pages = [:]
    }

    /// Shows each page of playlists as it arrives.
    func loadPlaylists() async {
        playlistsError = nil
        var loaded: [Playlist] = []
        var offset = 0
        do {
            repeat {
                let page = try await api.myPlaylists(offset: offset)
                loaded += page.items
                playlists = loaded
                offset += page.items.count
                if page.next == nil || page.items.isEmpty { break }
            } while true
        } catch {
            playlistsError = error.localizedDescription
        }
    }

    func content(for route: Route) -> PageContent? {
        pages[route]
    }

    /// Creates the content for `route` the first time it is shown.
    func prepare(_ route: Route) {
        guard pages[route] == nil, let username else { return }
        let content: PageContent
        switch route {
        case .whatsNew: content = .tracks(.recentlyPlayed(api: api))
        case .likedSongs: content = .tracks(.liked(api: api, username: username))
        case .playlist(let id, _): content = .tracks(.playlist(api: api, id: id))
        case .album(let id): content = .album(AlbumDetail(id: id, api: api))
        case .artist(let id): content = .artist(ArtistDetail(id: id, api: api))
        case .search(let query): content = .search(SearchResultsModel(query: query, api: api))
        case .queue, .albums, .artists: return
        }
        pages[route] = content
    }
}
