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
    private(set) var error: String?
    private(set) var albums: [AlbumSummary] = []
    private(set) var albumsError: String?
    let topTracks: TrackList

    init(id: String, api: SpotifyWebAPI, session: PlaybackSession) {
        topTracks = .topTracks(session: session, artistID: id)
        Task {
            do { artist = try await api.artist(id) } catch { self.error = error.localizedDescription }
        }
        Task {
            do { albums = try await api.artistAlbums(id).items } catch { albumsError = error.localizedDescription }
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
