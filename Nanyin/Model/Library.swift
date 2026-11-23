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
    private let notices: Notices
    private var username: String?

    init(api: SpotifyWebAPI, stars: Stars, session: PlaybackSession, notices: Notices) {
        self.api = api
        self.stars = stars
        self.session = session
        self.notices = notices
    }

    func signedIn(as username: String, showing route: Route) {
        self.username = username
        prepare(route)
        Task { await loadPlaylists() }
    }

    func signedOut() {
        username = nil
        playlists = []
        edit = nil
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

    /// Playlists the listener may add tracks to: their own and collaborative ones.
    var editablePlaylists: [Playlist] {
        playlists.filter { isOwn($0) || $0.collaborative == true }
    }

    func isOwn(_ playlist: Playlist) -> Bool {
        playlist.owner.id == username
    }

    func playlist(_ id: String) -> Playlist? {
        playlists.first { $0.id == id }
    }

    // MARK: Creating, renaming and removing playlists

    /// The sidebar row being edited in place, if any.
    enum PlaylistEdit: Equatable {
        case new
        case rename(id: String)
    }

    var edit: PlaylistEdit?
    /// The name of a playlist Spotify is creating, shown until it answers.
    private(set) var creating: String?

    func beginNewPlaylist() {
        guard username != nil, creating == nil else { return }
        edit = .new
    }

    /// Creates a playlist and returns it, first in the list, once Spotify has.
    func createPlaylist(named name: String) async -> Playlist? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, creating == nil else { return nil }
        creating = name
        defer { creating = nil }
        do {
            let playlist = try await api.createPlaylist(name: name)
            playlists.insert(playlist, at: 0)
            return playlist
        } catch {
            notices.report("Could not create “\(name)”: \(error.localizedDescription)")
            return nil
        }
    }

    /// Only the owner may rename a playlist.
    func rename(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = playlists.firstIndex(where: { $0.id == id }), isOwn(playlists[index]),
              !name.isEmpty, name != playlists[index].name else { return }
        let old = playlists[index].name
        playlists[index].name = name
        Task {
            do {
                try await api.renamePlaylist(id, to: name)
            } catch {
                if let index = playlists.firstIndex(where: { $0.id == id }) { playlists[index].name = old }
                notices.report("Could not rename “\(old)”: \(error.localizedDescription)")
            }
        }
    }

    /// Removes a playlist from the listener's library; for their own ones
    /// this is what Spotify calls deleting.
    func remove(_ playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists.remove(at: index)
        if edit == .rename(id: playlist.id) { edit = nil }
        Task {
            do {
                try await api.remove([playlist.uri])
                pages[.playlist(id: playlist.id)] = nil
            } catch {
                playlists.insert(playlist, at: min(index, playlists.count))
                notices.report("Could not remove “\(playlist.name)”: \(error.localizedDescription)")
            }
        }
    }

    func add(_ uris: [String], to playlist: Playlist) {
        Task {
            do {
                try await api.addToPlaylist(playlist.id, uris: uris)
                // Shown afresh next time it is opened.
                pages[.playlist(id: playlist.id)] = nil
            } catch {
                notices.report("Could not add to “\(playlist.name)”: \(error.localizedDescription)")
            }
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
        case .playlist(let id):
            // Development Mode grants read only the listener's own playlists;
            // the session reads any, so it takes every one not known as own.
            let owned = playlists.contains { $0.id == id && isOwn($0) }
            content = .tracks(owned ? .playlist(api: api, id: id) : .sessionPlaylist(session: session, id: id))
        case .album(let id): content = .album(AlbumDetail(id: id, api: api))
        case .artist(let id): content = .artist(ArtistDetail(id: id, api: api, session: session))
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
