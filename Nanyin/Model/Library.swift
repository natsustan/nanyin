import Foundation
import NanyinKit
import Observation

/// What a route shows, kept while the app runs so going back costs nothing.
enum PageContent {
    case tracks(TrackList)
    case album(AlbumDetail)
    case artist(ArtistDetail)
    case search(SearchResultsModel)
    case albums(Pager<Album, Int>)
    case artists(Pager<Artist, String?>)
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
    private let stars: Stars
    private let session: PlaybackSession
    private var username: String?

    init(api: SpotifyWebAPI, stars: Stars, session: PlaybackSession) {
        self.api = api
        self.stars = stars
        self.session = session
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
        case .likedSongs: content = .tracks(.liked(api: api, username: username, stars: stars))
        case .playlist(let id, _):
            // Development Mode grants read only the listener's own playlists;
            // the session reads any, so it takes every one not known as own.
            let owned = playlists.contains { $0.id == id && $0.owner.id == username }
            content = .tracks(owned ? .playlist(api: api, id: id) : .sessionPlaylist(session: session, id: id))
        case .album(let id): content = .album(AlbumDetail(id: id, api: api))
        case .artist(let id): content = .artist(ArtistDetail(id: id, api: api))
        case .search(let query): content = .search(SearchResultsModel(query: query, api: api))
        case .albums: content = .albums(.savedAlbums(api: api))
        case .artists: content = .artists(.followedArtists(api: api))
        case .queue: return
        }
        pages[route] = content
    }
}

#if DEBUG
extension Library {
    func showDemo(playlists: [Playlist], pages: [Route: PageContent]) {
        self.playlists = playlists
        self.pages = pages
    }
}
#endif
