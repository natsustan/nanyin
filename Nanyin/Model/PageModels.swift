import Foundation
import NanyinKit
import Observation

/// Saved/followed state of an album or artist on its detail page.
enum LibraryStatus: Equatable {
    case loading
    case known(Bool)
    case failed(String)
}

/// An album page: the album and its tracks, in one request.
@MainActor
@Observable
final class AlbumDetail {
    private(set) var album: Album?
    private(set) var tracks: TrackList?
    private(set) var error: String?
    private(set) var libraryStatus: LibraryStatus = .loading
    private(set) var isSaving = false

    @ObservationIgnored private let api: SpotifyWebAPI
    @ObservationIgnored private let notices: Notices
    @ObservationIgnored private let isCurrentAccount: () -> Bool
    @ObservationIgnored private let onLibraryChanged: () -> Void

    init(
        id: String,
        api: SpotifyWebAPI,
        notices: Notices,
        isCurrentAccount: @escaping () -> Bool = { true },
        onLibraryChanged: @escaping () -> Void = {}
    ) {
        self.api = api
        self.notices = notices
        self.isCurrentAccount = isCurrentAccount
        self.onLibraryChanged = onLibraryChanged
        Task {
            do {
                let album = try await api.album(id)
                guard isCurrentAccount() else { return }
                self.album = album
                let rows = (album.tracks?.items ?? []).enumerated().map {
                    TrackRow(index: $0.offset, track: $0.element, album: album)
                }
                tracks = TrackList(rows: rows, contextURI: album.uri)
                await checkLibraryStatus(for: album)
            } catch {
                guard isCurrentAccount() else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func retryLibraryStatus() {
        guard let album, case .failed = libraryStatus else { return }
        libraryStatus = .loading
        Task { await checkLibraryStatus(for: album) }
    }

    private func checkLibraryStatus(for album: Album) async {
        do {
            let saved = try await api.libraryContains([album.uri]).first
            guard isCurrentAccount() else { return }
            if let saved {
                libraryStatus = .known(saved)
            } else {
                libraryStatus = .failed("Spotify did not return library status.")
            }
        } catch {
            guard isCurrentAccount() else { return }
            libraryStatus = .failed(error.localizedDescription)
        }
    }

    func toggleSave() {
        guard let album, case .known(let current) = libraryStatus, !isSaving else { return }
        let target = !current
        libraryStatus = .known(target)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if target {
                    try await api.save([album.uri])
                } else {
                    try await api.remove([album.uri])
                }
                guard isCurrentAccount() else { return }
                onLibraryChanged()
            } catch {
                guard isCurrentAccount() else { return }
                libraryStatus = .known(current)
                notices.report("Could not \(target ? "save" : "remove") “\(album.name)”: \(error.localizedDescription)")
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
    private(set) var error: String?
    private(set) var albums: [AlbumSummary] = []
    private(set) var albumsError: String?
    private(set) var libraryStatus: LibraryStatus = .loading
    private(set) var isUpdatingFollow = false
    let topTracks: TrackList

    @ObservationIgnored private let api: SpotifyWebAPI
    @ObservationIgnored private let notices: Notices
    @ObservationIgnored private let isCurrentAccount: () -> Bool
    @ObservationIgnored private let onLibraryChanged: () -> Void

    init(
        id: String,
        api: SpotifyWebAPI,
        session: PlaybackSession,
        notices: Notices,
        isCurrentAccount: @escaping () -> Bool = { true },
        onLibraryChanged: @escaping () -> Void = {}
    ) {
        self.api = api
        self.notices = notices
        self.isCurrentAccount = isCurrentAccount
        self.onLibraryChanged = onLibraryChanged
        topTracks = .topTracks(session: session, artistID: id)
        Task {
            do {
                let artist = try await api.artist(id)
                guard isCurrentAccount() else { return }
                self.artist = artist
                await checkLibraryStatus(for: artist)
            } catch {
                guard isCurrentAccount() else { return }
                self.error = error.localizedDescription
            }
        }
        Task {
            do {
                let items = try await api.artistAlbums(id).items
                guard isCurrentAccount() else { return }
                albums = items
            } catch {
                guard isCurrentAccount() else { return }
                albumsError = error.localizedDescription
            }
        }
    }

    func retryLibraryStatus() {
        guard let artist, case .failed = libraryStatus else { return }
        libraryStatus = .loading
        Task { await checkLibraryStatus(for: artist) }
    }

    private func checkLibraryStatus(for artist: Artist) async {
        do {
            let following = try await api.libraryContains([artist.uri]).first
            guard isCurrentAccount() else { return }
            if let following {
                libraryStatus = .known(following)
            } else {
                libraryStatus = .failed("Spotify did not return follow status.")
            }
        } catch {
            guard isCurrentAccount() else { return }
            libraryStatus = .failed(error.localizedDescription)
        }
    }

    func toggleFollow() {
        guard let artist, case .known(let current) = libraryStatus, !isUpdatingFollow else { return }
        let target = !current
        libraryStatus = .known(target)
        isUpdatingFollow = true
        Task {
            defer { isUpdatingFollow = false }
            do {
                if target {
                    try await api.save([artist.uri])
                } else {
                    try await api.remove([artist.uri])
                }
                guard isCurrentAccount() else { return }
                onLibraryChanged()
            } catch {
                guard isCurrentAccount() else { return }
                libraryStatus = .known(current)
                notices.report("Could not \(target ? "follow" : "unfollow") \(artist.name): \(error.localizedDescription)")
            }
        }
    }
}

/// A song's credits, shown in a sheet over the window.
@MainActor
@Observable
final class TrackCredits: Identifiable {
    let title: String
    let artists: String
    private(set) var credits: CoreCredits?
    private(set) var error: String?

    init(trackID id: String, title: String, artists: String, session: PlaybackSession) {
        self.title = title
        self.artists = artists
        Task {
            do {
                let credits = try await session.readCredits(trackID: id)
                if credits.roles.allSatisfy(\.artists.isEmpty) {
                    error = "Spotify has no credits for this song."
                } else {
                    self.credits = credits
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// One search: matching artists, albums, playlists, and tracks.
@MainActor
@Observable
final class SearchResultsModel {
    private(set) var artists: [Artist] = []
    private(set) var albums: [AlbumSummary] = []
    private(set) var playlists: [Playlist] = []
    private(set) var tracks: TrackList?
    private(set) var error: String?

    init(query: String, api: SpotifyWebAPI, onPlaylists: @escaping ([Playlist]) -> Void = { _ in }) {
        Task {
            do {
                let found = try await api.search(query)
                artists = found.artists?.items ?? []
                albums = found.albums?.items ?? []
                playlists = found.compactPlaylists
                onPlaylists(playlists)
                let rows = (found.tracks?.items ?? []).enumerated().map { TrackRow(index: $0.offset, track: $0.element) }
                tracks = TrackList(rows: rows)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// The What's New page: followed artists' new releases, personalized Home
/// playlists, top artists, top tracks and recently played songs. Each section
/// loads on its own so a refused private feed never blocks the rest.
@MainActor
@Observable
final class WhatsNewModel {
    enum Tab: String, CaseIterable, Hashable {
        case overview = "Overview"
        case recentlyPlayed = "Recently Played"
        case topTracks = "Top Tracks"
    }

    private(set) var tab: Tab = .overview
    private(set) var topRange: TopTimeRange = .shortTerm

    private(set) var newReleases: [AlbumSummary] = []
    private(set) var newReleasesLoading = false
    private(set) var madeForYou: [Playlist] = []
    private(set) var topMixes: [Playlist] = []
    private(set) var madeForYouLoading = false
    private(set) var topArtists: [Artist] = []
    private(set) var topArtistsLoading = false
    private(set) var topArtistsError: String?

    private(set) var recentlyPlayed: TrackList?
    private(set) var topTracks: TrackList?

    @ObservationIgnored private let api: SpotifyWebAPI?
    @ObservationIgnored private let session: PlaybackSession?
    @ObservationIgnored private let history: PlayHistoryStore?
    @ObservationIgnored private let onPlaylists: ([Playlist]) -> Void
    @ObservationIgnored private var remoteRecent: [PlayHistory] = []
    @ObservationIgnored private var shelfTasks: [Task<Void, Never>] = []

    init(
        api: SpotifyWebAPI,
        session: PlaybackSession,
        history: PlayHistoryStore,
        onPlaylists: @escaping ([Playlist]) -> Void
    ) {
        self.api = api
        self.session = session
        self.history = history
        self.onPlaylists = onPlaylists
        loadShelves(force: false)
    }

    #if DEBUG
    init(
        newReleases: [AlbumSummary],
        madeForYou: [Playlist],
        topMixes: [Playlist],
        topArtists: [Artist],
        recentlyPlayed: TrackList,
        topTracks: TrackList
    ) {
        self.api = nil
        self.session = nil
        self.history = nil
        self.onPlaylists = { _ in }
        self.newReleases = newReleases
        self.madeForYou = madeForYou
        self.topMixes = topMixes
        self.topArtists = topArtists
        self.recentlyPlayed = recentlyPlayed
        self.topTracks = topTracks
    }
    #endif

    var isLoadingOverview: Bool {
        newReleasesLoading || madeForYouLoading || topArtistsLoading
    }

    var hasOverviewContent: Bool {
        !newReleases.isEmpty || !madeForYou.isEmpty || !topMixes.isEmpty || !topArtists.isEmpty
    }

    func selectTab(_ tab: Tab) {
        self.tab = tab
        guard let api else { return }
        switch tab {
        case .overview:
            break
        case .recentlyPlayed:
            if recentlyPlayed == nil, let history {
                recentlyPlayed = makeRecentlyPlayed(api: api, history: history)
            }
        case .topTracks:
            if topTracks == nil {
                topTracks = .topTracks(api: api, timeRange: topRange)
            }
        }
    }

    func setTopRange(_ range: TopTimeRange) {
        guard range != topRange else { return }
        topRange = range
        guard let api else { return }
        topTracks = .topTracks(api: api, timeRange: range)
    }

    func didRecordPlay() {
        guard let history, let current = recentlyPlayed, !current.pages.isLoading else { return }
        recentlyPlayed = .mergedRecentlyPlayed(local: history.plays, remote: remoteRecent)
    }

    func refresh() {
        guard let api else { return }
        switch tab {
        case .overview:
            loadShelves(force: true)
        case .recentlyPlayed:
            if let history { recentlyPlayed = makeRecentlyPlayed(api: api, history: history) }
        case .topTracks:
            topTracks = .topTracks(api: api, timeRange: topRange)
        }
    }

    private func makeRecentlyPlayed(api: SpotifyWebAPI, history: PlayHistoryStore) -> TrackList {
        .recentlyPlayed(api: api, history: history) { [weak self] remote in
            self?.remoteRecent = remote
        }
    }

    private func loadShelves(force: Bool) {
        guard let api, let session else { return }
        shelfTasks.forEach { $0.cancel() }
        shelfTasks = []

        newReleasesLoading = true
        let releasesTask = Task { [weak self] in
            let albums = try? await session.readNewReleases(force: force)
            guard !Task.isCancelled, let self else { return }
            self.newReleasesLoading = false
            if let albums { self.newReleases = albums }
        }

        madeForYouLoading = true
        let homeTask = Task { [weak self] in
            let shelves = try? await session.readMadeForYou(force: force)
            guard !Task.isCancelled, let self else { return }
            self.madeForYouLoading = false
            if let shelves {
                self.madeForYou = shelves.madeForYou
                self.topMixes = shelves.topMixes
                self.onPlaylists(shelves.madeForYou + shelves.topMixes)
            }
        }

        topArtistsLoading = true
        topArtistsError = nil
        let artistsTask = Task { [weak self] in
            do {
                let items = try await api.topArtists(timeRange: .shortTerm, limit: 20).items
                guard !Task.isCancelled, let self else { return }
                self.topArtists = items
                self.topArtistsLoading = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.topArtistsError = error.localizedDescription
                self.topArtistsLoading = false
            }
        }

        shelfTasks = [releasesTask, homeTask, artistsTask]
    }
}
