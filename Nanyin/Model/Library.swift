import Foundation
import NanyinKit
import Observation

/// What a route shows, kept while the app runs so going back costs nothing.
enum PageContent {
    case whatsNew(WhatsNewModel)
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
    /// Every page has arrived. Until then each page replaces the list, so
    /// it cannot be edited.
    private(set) var playlistsLoaded = false
    /// Filled by `prepare` before a route is shown; views only read it.
    @ObservationIgnored private var pages: [Route: PageContent] = [:]
    /// Playlists met outside the library (e.g. Made for You), remembered so
    /// opening one still shows its title and cover.
    private var knownPlaylists: [String: Playlist] = [:]
    private let api: SpotifyWebAPI
    private let stars: Stars
    private let session: PlaybackSession
    private let history: PlayHistoryStore
    private let notices: Notices
    private var username: String?
    /// Bumped at sign-out; a request's answer applies only to the account
    /// that sent it.
    @ObservationIgnored private var account = 0

    init(api: SpotifyWebAPI, stars: Stars, session: PlaybackSession, history: PlayHistoryStore, notices: Notices) {
        self.api = api
        self.stars = stars
        self.session = session
        self.history = history
        self.notices = notices
    }

    func signedIn(as username: String, showing route: Route) {
        self.username = username
        prepare(route)
        Task { await loadPlaylists() }
    }

    func signedOut() {
        account += 1
        busy = []
        username = nil
        playlists = []
        playlistsLoaded = false
        edit = nil
        pages = [:]
        knownPlaylists = [:]
    }

    /// Shows each page of playlists as it arrives.
    func loadPlaylists() async {
        playlistsError = nil
        playlistsLoaded = false
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
            playlistsLoaded = true
        } catch {
            playlistsError = error.localizedDescription
        }
    }

    /// Playlists the listener may add tracks to: their own and collaborative ones.
    var editablePlaylists: [Playlist] {
        playlists.filter { canEditTracks($0) }
    }

    func isOwn(_ playlist: Playlist) -> Bool {
        playlist.owner.id == username
    }

    func canEditTracks(_ playlist: Playlist) -> Bool {
        isOwn(playlist) || playlist.collaborative == true
    }

    func isSaved(playlistID id: String) -> Bool {
        playlists.contains { $0.id == id }
    }

    func playlist(_ id: String) -> Playlist? {
        playlists.first { $0.id == id } ?? knownPlaylists[id]
    }

    func remember(_ playlists: [Playlist]) {
        for playlist in playlists { knownPlaylists[playlist.id] = playlist }
    }

    // MARK: Creating, renaming and removing playlists

    /// The sidebar row being edited in place, if any.
    enum PlaylistEdit: Equatable {
        case new
        case rename(id: String)
    }

    /// Set through `begin`; the sidebar clears it when the field closes.
    var edit: PlaylistEdit?
    /// The name of a playlist Spotify is creating, shown until it answers.
    private(set) var creating: String?

    var canEditPlaylists: Bool { playlistsLoaded && edit == nil && creating == nil }

    /// One field at a time: a second request waits for the first to close.
    func begin(_ edit: PlaylistEdit) {
        guard canEditPlaylists else { return }
        self.edit = edit
    }

    /// Creates a playlist and returns it, first in the list, once Spotify has.
    func createPlaylist(named name: String) async -> Playlist? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, playlistsLoaded, creating == nil else { return nil }
        let account = account
        creating = name
        defer { creating = nil }
        do {
            let playlist = try await api.createPlaylist(name: name)
            guard account == self.account else { return nil }
            playlists.insert(playlist, at: 0)
            return playlist
        } catch {
            notices.report("Could not create “\(name)”: \(error.localizedDescription)")
            return nil
        }
    }

    /// Playlists with a rename or removal on its way: each takes one at a
    /// time, so a failure has only one earlier state to return to.
    private(set) var busy: Set<String> = []

    func canEdit(_ playlist: Playlist) -> Bool {
        canEditPlaylists && !busy.contains(playlist.id)
    }

    /// Only the owner may rename a playlist.
    func rename(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard playlistsLoaded, !busy.contains(id), let index = playlists.firstIndex(where: { $0.id == id }),
              isOwn(playlists[index]), !name.isEmpty, name != playlists[index].name else { return }
        let account = account
        let old = playlists[index].name
        playlists[index].name = name
        busy.insert(id)
        Task {
            do {
                try await api.renamePlaylist(id, to: name)
            } catch {
                guard account == self.account else { return }
                if let index = playlists.firstIndex(where: { $0.id == id }) { playlists[index].name = old }
                notices.report("Could not rename “\(old)”: \(error.localizedDescription)")
            }
            if account == self.account { busy.remove(id) }
        }
    }

    /// Updates a playlist's name and description; only the owner may edit details.
    func updateDetails(_ id: String, name: String, description: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard playlistsLoaded, !busy.contains(id), let index = playlists.firstIndex(where: { $0.id == id }),
              isOwn(playlists[index]), !name.isEmpty else { return }
        let oldName = playlists[index].name
        let oldDescription = playlists[index].description
        let oldPlainDescription = playlists[index].plainDescription ?? ""
        let newDescription: String? = description.isEmpty ? nil : description
        guard name != oldName || description != oldPlainDescription else { return }
        let account = account
        playlists[index].name = name
        playlists[index].description = newDescription
        busy.insert(id)
        Task {
            do {
                try await api.updatePlaylist(id, name: name, description: description)
            } catch {
                guard account == self.account else { return }
                if let index = playlists.firstIndex(where: { $0.id == id }) {
                    playlists[index].name = oldName
                    playlists[index].description = oldDescription
                }
                notices.report("Could not update “\(oldName)”: \(error.localizedDescription)")
            }
            if account == self.account { busy.remove(id) }
        }
    }

    /// Saves or removes a playlist the listener does not own, keeping its page
    /// open so the listener can undo a misclick.
    func toggleSave(_ playlist: Playlist) {
        guard playlistsLoaded, !busy.contains(playlist.id), !isOwn(playlist) else { return }
        let account = account
        knownPlaylists[playlist.id] = playlist
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            let removed = playlists.remove(at: index)
            busy.insert(playlist.id)
            Task {
                do {
                    try await api.remove([removed.uri])
                } catch {
                    guard account == self.account else { return }
                    playlists.insert(removed, at: min(index, playlists.count))
                    notices.report("Could not remove “\(removed.name)”: \(error.localizedDescription)")
                }
                if account == self.account { busy.remove(playlist.id) }
            }
        } else {
            playlists.insert(playlist, at: 0)
            busy.insert(playlist.id)
            Task {
                do {
                    try await api.save([playlist.uri])
                } catch {
                    guard account == self.account else { return }
                    playlists.removeAll { $0.id == playlist.id }
                    notices.report("Could not save “\(playlist.name)”: \(error.localizedDescription)")
                }
                if account == self.account { busy.remove(playlist.id) }
            }
        }
    }

    /// Removes tracks from an editable playlist optimistically, rolling back on failure.
    func removeTracks(_ rows: [TrackRow], from playlist: Playlist, list: TrackList) {
        guard canEditTracks(playlist), !busy.contains(playlist.id) else { return }
        var seen = Set<String>()
        let uris = rows.map(\.uri).filter { seen.insert($0).inserted }
        guard !uris.isEmpty else { return }
        let account = account
        let hadMore = list.pages.hasMore
        let removal = list.pages.remove { seen.contains($0.uri) }
        busy.insert(playlist.id)
        Task {
            var removedAny = false
            var remaining = Set(uris)
            do {
                for start in stride(from: 0, to: uris.count, by: 100) {
                    let batch = Array(uris[start ..< min(start + 100, uris.count)])
                    try await api.removeFromPlaylist(playlist.id, uris: batch)
                    removedAny = true
                    remaining.subtract(batch)
                }
                if account == self.account, hadMore {
                    // Server offsets shifted for pages beyond the first; reload cleanly.
                    list.pages.reload()
                }
            } catch {
                guard account == self.account else { return }
                if removedAny {
                    if hadMore {
                        list.pages.reload()
                    } else {
                        list.pages.restore(removal) { remaining.contains($0.uri) }
                    }
                } else {
                    list.pages.restore(removal)
                }
                notices.report("Could not remove tracks from “\(playlist.name)”: \(error.localizedDescription)")
            }
            if account == self.account { busy.remove(playlist.id) }
        }
    }

    /// Removes a playlist from the listener's library; for their own ones
    /// this is what Spotify calls deleting.
    func remove(_ playlist: Playlist) {
        guard playlistsLoaded, !busy.contains(playlist.id),
              let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let playlist = playlists.remove(at: index)
        busy.insert(playlist.id)
        if edit == .rename(id: playlist.id) { edit = nil }
        let account = account
        Task {
            do {
                try await api.remove([playlist.uri])
                pages[.playlist(id: playlist.id)] = nil
            } catch {
                guard account == self.account else { return }
                playlists.insert(playlist, at: min(index, playlists.count))
                notices.report("Could not remove “\(playlist.name)”: \(error.localizedDescription)")
            }
            if account == self.account { busy.remove(playlist.id) }
        }
    }

    func add(_ uris: [String], to playlist: Playlist) {
        let account = account
        let needsCover = playlist.images?.isEmpty ?? true
        Task {
            do {
                try await api.addToPlaylist(playlist.id, uris: uris)
                guard account == self.account else { return }
                // Shown afresh next time it is opened.
                pages[.playlist(id: playlist.id)] = nil
                if needsCover, let images = try? await api.playlistImages(playlist.id), !images.isEmpty,
                   account == self.account,
                   let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                    playlists[index].images = images
                }
            } catch {
                guard account == self.account else { return }
                notices.report("Could not add to “\(playlist.name)”: \(error.localizedDescription)")
            }
        }
    }

    private func applySessionMetadata(id: String, page: SessionPlaylistPage) {
        func merge(into playlist: inout Playlist) {
            if playlist.name.isEmpty, let name = page.name, !name.isEmpty {
                playlist.name = name
            }
            if playlist.description?.isEmpty != false, let description = page.description, !description.isEmpty {
                playlist.description = description
            }
            if playlist.images?.isEmpty != false, let images = page.images, !images.isEmpty {
                playlist.images = images
            }
        }
        if let index = playlists.firstIndex(where: { $0.id == id }) {
            merge(into: &playlists[index])
        } else if var known = knownPlaylists[id] {
            merge(into: &known)
            knownPlaylists[id] = known
        }
    }

    func didRecordPlay() {
        if case .whatsNew(let model) = pages[.whatsNew] {
            model.didRecordPlay()
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
        case .whatsNew:
            content = .whatsNew(WhatsNewModel(api: api, session: session, history: history) { [weak self] in self?.remember($0) })
        case .likedSongs: content = .tracks(.liked(api: api, username: username, stars: stars))
        case .playlist(let id):
            // Development Mode grants read only the listener's own playlists;
            // the session reads any, so it takes every one not known as own.
            let owned = playlists.contains { $0.id == id && isOwn($0) }
            let account = account
            content = .tracks(owned
                ? .playlist(api: api, id: id)
                : .sessionPlaylist(session: session, id: id) { [weak self] page in
                    guard let self, self.account == account else { return }
                    self.applySessionMetadata(id: id, page: page)
                })
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
