import Foundation
import NanyinKit
import Observation

/// The signed-in account's playlists, and the track lists already opened.
@MainActor
@Observable
final class Library {
    private(set) var playlists: [Playlist] = []
    private(set) var playlistsError: String?
    private var lists: [Route: TrackList] = [:]
    private let api: SpotifyWebAPI
    private var username: String?

    init(api: SpotifyWebAPI) {
        self.api = api
    }

    func signedIn(as username: String) {
        self.username = username
        Task { await loadPlaylists() }
    }

    func signedOut() {
        username = nil
        playlists = []
        lists = [:]
    }

    func loadPlaylists() async {
        playlistsError = nil
        var loaded: [Playlist] = []
        do {
            var offset = 0
            while true {
                let page = try await api.myPlaylists(offset: offset)
                loaded += page.items
                offset += page.items.count
                guard page.next != nil, !page.items.isEmpty else { break }
            }
            playlists = loaded
        } catch {
            playlistsError = error.localizedDescription
            if playlists.isEmpty { playlists = loaded }
        }
    }

    /// The track list for a route, kept while the app runs so going back is
    /// free.
    func trackList(for route: Route) -> TrackList? {
        if let list = lists[route] { return list }
        let list: TrackList
        switch route {
        case .likedSongs:
            guard let username else { return nil }
            list = .liked(api: api, username: username)
        case .playlist(let id, _):
            list = .playlist(api: api, id: id)
        default:
            return nil
        }
        lists[route] = list
        list.loadMore()
        return list
    }
}
