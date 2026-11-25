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

/// An artist page: header stats, popular tracks with play counts, categorized
/// paginated discography, and related artists. Each read is independent so one
/// unavailable feed never blocks the rest of the page.
@MainActor
@Observable
final class ArtistDetail {
    let artistID: String
    private(set) var artist: Artist?
    private(set) var error: String?
    private(set) var monthlyListeners: UInt64?
    private(set) var overviewFollowers: UInt64?
    private(set) var playCounts: [String: UInt64] = [:]
    private(set) var relatedArtists: [Artist] = []
    private(set) var selectedGroup: ArtistAlbumGroup = .all
    private(set) var showAllTopTracks = false
    private(set) var libraryStatus: LibraryStatus = .loading
    private(set) var isUpdatingFollow = false
    let topTracks: TrackList

    private var discographyPagers: [ArtistAlbumGroup: Pager<AlbumSummary, Int>] = [:]

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
        self.artistID = id
        self.api = api
        self.notices = notices
        self.isCurrentAccount = isCurrentAccount
        self.onLibraryChanged = onLibraryChanged
        topTracks = .topTracks(session: session, artistID: id)
        discographyPagers[.all] = makeDiscographyPager(for: .all)

        loadArtist()
        Task {
            guard let overview = try? await session.readArtistOverview(artistID: id),
                  isCurrentAccount() else { return }
            self.monthlyListeners = overview.monthlyListeners
            self.overviewFollowers = overview.followers
            self.playCounts = overview.playCounts
        }
        Task {
            guard let related = try? await session.readRelatedArtists(artistID: id),
                  isCurrentAccount() else { return }
            self.relatedArtists = related
        }
    }

    var followersCount: UInt64? {
        if let total = artist?.followers?.total, total >= 0 {
            return UInt64(total)
        }
        return overviewFollowers
    }

    /// Always non-mutating: `init` seeds `.all` and `selectGroup(_:)` seeds
    /// any newly selected group before switching `selectedGroup`.
    var currentDiscography: Pager<AlbumSummary, Int>? {
        discographyPagers[selectedGroup]
    }

    /// Deduplicates duplicate regional/clean editions while keeping distinct
    /// album vs single releases with the same title.
    var visibleDiscography: [AlbumSummary] {
        guard let pager = currentDiscography else { return [] }
        var seen = Set<String>()
        return pager.items.filter { album in
            let title = album.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let kind = (album.album_type ?? album.album_group ?? "").lowercased()
            return seen.insert("\(title)|\(kind)").inserted
        }
    }

    func retryArtist() {
        guard artist == nil, error != nil else { return }
        error = nil
        loadArtist()
    }

    private func loadArtist() {
        let id = artistID
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
    }

    func selectGroup(_ group: ArtistAlbumGroup) {
        if discographyPagers[group] == nil {
            discographyPagers[group] = makeDiscographyPager(for: group)
        }
        guard group != selectedGroup else { return }
        selectedGroup = group
    }

    func toggleShowAllTopTracks() {
        showAllTopTracks.toggle()
    }

    func playCount(for trackURI: String) -> UInt64? {
        playCounts[trackURI]
    }

    private func makeDiscographyPager(for group: ArtistAlbumGroup) -> Pager<AlbumSummary, Int> {
        let id = artistID
        let api = api
        let isCurrentAccount = isCurrentAccount
        return Pager(first: 0) { offset in
            let page = try await api.artistAlbums(id, groups: group, offset: offset, limit: 10)
            guard isCurrentAccount() else { return ([], nil, nil) }
            let next = (page.next == nil || page.items.isEmpty) ? nil : offset + page.items.count
            return (page.items, page.total, next)
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
        case overview = "What's New"
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
