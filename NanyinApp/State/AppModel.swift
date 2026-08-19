//
//  AppModel.swift
//  Nanyin
//

import Foundation
import Observation
import AppKit

/// Unbuffered debug logging to stderr (survives process kill, unlike print).
func dlog(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write(Data("[nanyin] \(message())\n".utf8))
}

/// App-wide state: auth, playback, and glue between Web API and the Rust core.
@Observable
@MainActor
final class AppModel {
    enum AuthState {
        case checking // trying silent refresh on launch
        case loggedOut
        case signingIn
        case loggedIn
    }

    struct PlayerInitError: Error, LocalizedError {
        let message: String
        init(detail: String) { message = detail }
        var errorDescription: String? { message }
    }

    // MARK: - Auth

    private(set) var authState: AuthState = .checking
    private(set) var userDisplayName: String = ""
    /// Spotify user id (login5 username form) — builds the collection context URI.
    private(set) var userId: String = ""
    private(set) var authError: String?

    // MARK: - Token store (auto-refresh with in-flight dedup)

    private var playbackAccessToken: String = ""
    private var webAccessToken: String = ""
    private var webTokenExpiry: Date = .distantPast
    private var api: SpotifyClient?
    private var accountEpoch = 0
    private var webRefreshInFlight: (epoch: Int, task: Task<SpotifyAuth.Token, Error>)?

    /// Returns a valid Web API access token, refreshing when near expiry.
    /// Concurrent callers share one in-flight refresh.
    private func ensureWebToken(
        for expectedEpoch: Int? = nil,
        forceRefresh: Bool = false
    ) async throws -> String {
        let epoch = expectedEpoch ?? accountEpoch
        guard epoch == accountEpoch else { throw CancellationError() }
        if !forceRefresh,
           Date() < webTokenExpiry.addingTimeInterval(-60),
           !webAccessToken.isEmpty {
            return webAccessToken
        }
        if let existing = webRefreshInFlight, existing.epoch == epoch {
            let token = try await existing.task.value
            guard epoch == accountEpoch else { throw CancellationError() }
            return token.accessToken
        }
        let task = Task<SpotifyAuth.Token, Error> {
            try await SpotifyAuth.refreshAccessToken(for: .web)
        }
        webRefreshInFlight = (epoch, task)
        defer {
            if webRefreshInFlight?.epoch == epoch { webRefreshInFlight = nil }
        }
        let token = try await task.value
        guard epoch == accountEpoch else { throw CancellationError() }
        apply(webToken: token)
        return token.accessToken
    }

    /// Same as ensureWebToken but rebuilds the API client with a fresh token.
    private func refreshAPIClient(
        for expectedEpoch: Int? = nil,
        forceRefresh: Bool = false
    ) async {
        let epoch = expectedEpoch ?? accountEpoch
        guard let token = try? await ensureWebToken(for: epoch, forceRefresh: forceRefresh),
              epoch == accountEpoch else { return }
        api = SpotifyClient(accessToken: token)
    }

    /// Retries one Web API operation with a fresh token after an actual 401.
    private func withAPIAuthRetry<T>(
        for epoch: Int,
        operation: (SpotifyClient) async throws -> T
    ) async throws -> T {
        guard epoch == accountEpoch else { throw CancellationError() }
        await refreshAPIClient(for: epoch)
        guard epoch == accountEpoch, let api else { throw CancellationError() }
        do {
            return try await operation(api)
        } catch SpotifyClient.APIError.needsAuth {
            guard epoch == accountEpoch else { throw CancellationError() }
            await refreshAPIClient(for: epoch, forceRefresh: true)
            guard epoch == accountEpoch, let refreshedAPI = self.api else {
                throw CancellationError()
            }
            return try await operation(refreshedAPI)
        }
    }

    // MARK: - Playback

    private(set) var isPlaying = false
    private(set) var isBuffering = false
    // NOTE: playback position is intentionally NOT stored here. Polling it at
    // 2Hz from the app-wide observable would invalidate every view reading
    // the model (including every track row) — PlayerBar ticks it locally.
    private(set) var durationMs: UInt32 = 0
    private(set) var volume: Double = 1.0 // 0…1
    private(set) var shuffle = false
    /// Classic client repeat: off / all(context) / one(track).
    enum RepeatMode: Equatable {
        case off
        case all
        case one
    }
    private(set) var repeatMode: RepeatMode = .off

    struct NowPlaying {
        let uri: String
        let title: String
        /// Display string ("A, B") — also feeds MPNowPlayingInfoCenter.
        let artist: String
        /// Artists with ids — drives the player-bar artist link.
        let artists: [SpotifyClient.Artist]
        let album: String
        let albumId: String?
        let artworkURL: URL?
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var connectionNote: String?

    // MARK: - Library (M1)

    enum Page: Hashable {
        case home
        case search
        case queue
        case liked
        case playlist(id: String, name: String)
        case artist(id: String, name: String, artworkURL: URL?)
        case album(id: String, name: String, subtitle: String, artworkURL: URL?)

        var contextKey: String? {
            switch self {
            case .home, .queue: nil
            case .search: "search"
            case .liked: "liked"
            case let .playlist(id, _): id
            case let .artist(id, _, _): "artist:\(id)"
            case let .album(id, _, _, _): "album:\(id)"
            }
        }
    }

    /// Cache keys mirrored by RootView when building detail views; keep in sync.
    static func artistContextKey(_ id: String) -> String { "artist:\(id)" }
    static func albumContextKey(_ id: String) -> String { "album:\(id)" }

    private(set) var page: Page = .home
    /// Back/forward navigation stacks (page-level, like the desktop client's
    /// sidebar arrows). open() pushes; goBack()/goForward() walk both ways.
    private var history: [Page] = []
    private var forwardStack: [Page] = []
    var canGoBack: Bool { !history.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    private(set) var playlists: [SpotifyClient.PlaylistInfo] = []
    private(set) var likedCount = 0

    // MARK: - Likes (M4.2)

    /// Liked state per track id, overlaid by in-app toggles.
    private(set) var likedIDs: Set<String> = []
    /// IDs resolved by contains() before the full library snapshot arrives.
    private var knownLikeIDs: Set<String> = []
    private var likedSnapshotComplete = false
    private var pendingLikeProbeIDs: Set<String> = []
    private var likedProbeTask: Task<Void, Never>?
    /// Desired like state that must win over a lagged server snapshot.
    /// Successful writes expire after a bounded reconciliation window.
    private struct LikeOverride {
        let liked: Bool
        let track: SpotifyClient.Track
        let mutationID: UUID
        var expiresAt: Date?
    }
    private var likeOverrides: [String: LikeOverride] = [:]
    /// One writer per track; rapid toggles are folded into the latest override.
    private var activeLikeMutations: Set<String> = []
    private var isRefreshingLiked = false
    private var likedRefreshPending = false
    private var lastLikedRefresh = Date.distantPast
    /// Last server-reported library size (not adjusted by local overrides).
    private var likedServerTotal: Int?
    /// Minimum gap between opportunistic probes (app-active). Page opens force.
    private let likedRefreshMinInterval: TimeInterval = 15
    /// Keep transient contains failures from leaving visible rows unresolved,
    /// while bounding the extra Web API traffic after the client's own retries.
    private let likedProbeRetryLimit = 2
    /// Covers Spotify's normal write-to-read lag without masking later changes
    /// made by another client indefinitely.
    private let likeOverrideLagWindow: TimeInterval = 30

    func isLikeKnown(_ id: String) -> Bool {
        likedSnapshotComplete || knownLikeIDs.contains(id) || likeOverrides[id] != nil
    }

    /// Rows request state as they become visible. Requests are deduplicated,
    /// debounced, and drained serially in Spotify's 50-id maximum batches.
    func requestLikedState(_ id: String) {
        guard authState == .loggedIn, !isLikeKnown(id) else { return }
        pendingLikeProbeIDs.insert(id)
        guard likedProbeTask == nil else { return }
        let epoch = accountEpoch
        likedProbeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            await self?.flushLikeProbes(for: epoch)
        }
    }

    private func flushLikeProbes(for epoch: Int) async {
        defer {
            if epoch == accountEpoch { likedProbeTask = nil }
        }
        await refreshAPIClient(for: epoch)
        guard epoch == accountEpoch,
              authState == .loggedIn,
              !likedSnapshotComplete,
              let api else { return }

        var retryAttempt = 0
        while epoch == accountEpoch, !likedSnapshotComplete, !pendingLikeProbeIDs.isEmpty {
            let ids = Array(pendingLikeProbeIDs.prefix(50))
            pendingLikeProbeIDs.subtract(ids)
            do {
                let flags = try await api.likedContains(ids: ids)
                guard epoch == accountEpoch,
                      authState == .loggedIn,
                      !likedSnapshotComplete else { return }
                zip(ids, flags).forEach { id, liked in
                    knownLikeIDs.insert(id)
                    if likeOverrides[id] != nil { return }
                    if liked {
                        likedIDs.insert(id)
                    } else if tracksByContext["liked"]?.contains(where: { $0.id == id }) != true {
                        likedIDs.remove(id)
                    }
                }
                retryAttempt = 0
            } catch {
                guard epoch == accountEpoch,
                      !likedSnapshotComplete,
                      !Task.isCancelled else { return }
                pendingLikeProbeIDs.formUnion(ids)
                guard retryAttempt < likedProbeRetryLimit else {
                    dlog("likedContains failed after bounded retries: \(error)")
                    return
                }
                retryAttempt += 1
                let delay = min(pow(2.0, Double(retryAttempt)), 8.0)
                dlog("likedContains failed: \(error); retrying in \(delay)s")
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
        }
    }

    /// Applies display data, then reconciles overrides only against IDs that
    /// came from the server. Cached tracks are never confirmation of a write.
    private func applyLikedSnapshot(
        displayTracks: [SpotifyClient.Track],
        confirmedServerIDs: Set<String>,
        total: Int,
        displayIsComplete: Bool,
        serverSnapshotIsComplete: Bool
    ) {
        pruneExpiredLikeOverrides()
        var list = displayTracks
        var ids = Set(displayTracks.map(\.id))
        var count = total
        for (id, override) in likeOverrides {
            if override.liked {
                if !ids.contains(id) {
                    list.insert(override.track, at: 0)
                    ids.insert(id)
                }
                if !confirmedServerIDs.contains(id) {
                    count += 1
                }
            } else {
                if ids.contains(id) {
                    list.removeAll { $0.id == id }
                    ids.remove(id)
                }
                if confirmedServerIDs.contains(id) {
                    count -= 1
                }
            }
        }
        tracksByContext["liked"] = list
        if !displayIsComplete {
            ids.formUnion(likedIDs.filter { knownLikeIDs.contains($0) })
        }
        likedIDs = ids
        likedSnapshotComplete = likedSnapshotComplete || displayIsComplete
        if displayIsComplete {
            pendingLikeProbeIDs.removeAll()
            likedProbeTask?.cancel()
        }
        likedServerTotal = total
        likedCount = max(0, count)
        for (id, override) in likeOverrides {
            guard !activeLikeMutations.contains(id) else { continue }
            if override.liked && confirmedServerIDs.contains(id) {
                likeOverrides.removeValue(forKey: id)
            } else if serverSnapshotIsComplete,
                      !override.liked,
                      !confirmedServerIDs.contains(id) {
                likeOverrides.removeValue(forKey: id)
            }
        }
    }

    /// Newest page on top; keep cached tail entries that were only pushed down.
    private func mergeLikedPrefix(
        cached: [SpotifyClient.Track],
        prefix: [SpotifyClient.Track]
    ) -> [SpotifyClient.Track] {
        let prefixIDs = Set(prefix.map(\.id))
        return prefix + cached.filter { !prefixIDs.contains($0.id) }
    }

    private func rememberLikeOverride(_ track: SpotifyClient.Track, liked: Bool) {
        likeOverrides[track.id] = LikeOverride(
            liked: liked,
            track: track,
            mutationID: UUID(),
            expiresAt: nil
        )
    }

    private func forgetLikeOverride(_ id: String) {
        likeOverrides.removeValue(forKey: id)
    }

    private func pruneExpiredLikeOverrides(now: Date = Date()) {
        likeOverrides = likeOverrides.filter { _, override in
            guard let expiresAt = override.expiresAt else { return true }
            return expiresAt > now
        }
    }

    private func hasPendingLikeOverrides() -> Bool {
        pruneExpiredLikeOverrides()
        return !likeOverrides.isEmpty
    }

    /// Reconcile Liked Songs with the server. Forced on page open / re-click;
    /// opportunistic (throttled) when the app becomes active. Third-party
    /// clients do not receive library-change pushes.
    func refreshLiked(force: Bool = false) {
        guard authState == .loggedIn else { return }
        pruneExpiredLikeOverrides()
        guard !isRefreshingLiked else {
            likedRefreshPending = true
            return
        }
        if !force, Date().timeIntervalSince(lastLikedRefresh) < likedRefreshMinInterval {
            return
        }
        isRefreshingLiked = true
        lastLikedRefresh = Date()
        let epoch = accountEpoch
        let loadingToken = tracksByContext["liked"] == nil
            ? beginTrackLoading(contextKey: "liked")
            : nil
        if loadingToken != nil {
            tracksError["liked"] = nil
        }
        Task {
            defer {
                if epoch == accountEpoch {
                    isRefreshingLiked = false
                    if let loadingToken {
                        endTrackLoading(contextKey: "liked", token: loadingToken)
                    }
                    if likedRefreshPending {
                        likedRefreshPending = false
                        refreshLiked(force: true)
                    }
                }
            }
            do {
                let prefix = try await withAPIAuthRetry(for: epoch) { api in
                    try await api.likedTracksPrefix()
                }
                guard epoch == accountEpoch else { return }
                let cached = tracksByContext["liked"] ?? []
                let prefixMatches = Array(cached.prefix(prefix.tracks.count)).map(\.id) == prefix.tracks.map(\.id)
                let previousTotal = likedServerTotal ?? likedCount
                // Skip a full re-page when the newest 50 and the total agree.
                if likedSnapshotComplete,
                   likeOverrides.isEmpty,
                   prefixMatches,
                   previousTotal == prefix.total {
                    if tracksByContext["liked"] == nil {
                        tracksByContext["liked"] = []
                    }
                    likedServerTotal = prefix.total
                    return
                }

                if prefix.total <= prefix.tracks.count {
                    applyLikedSnapshot(
                        displayTracks: prefix.tracks,
                        confirmedServerIDs: Set(prefix.tracks.map(\.id)),
                        total: prefix.total,
                        displayIsComplete: true,
                        serverSnapshotIsComplete: true
                    )
                    return
                }

                // Phone like/unlike almost always lands in the first page.
                // Merge that page onto the cache and paint immediately — do
                // not wait for the rest of the library.
                if !cached.isEmpty {
                    let merged = mergeLikedPrefix(cached: cached, prefix: prefix.tracks)
                    applyLikedSnapshot(
                        displayTracks: merged,
                        confirmedServerIDs: Set(prefix.tracks.map(\.id)),
                        total: prefix.total,
                        displayIsComplete: likedSnapshotComplete,
                        serverSnapshotIsComplete: false
                    )
                    let reconciled = likedSnapshotComplete && likeOverrides.isEmpty
                        && (merged.count - cached.count) == (prefix.total - previousTotal)
                    if reconciled { return }
                } else {
                    // First visit: show the newest 50 so the page is not blank
                    // while the tail pages in. Do not replace likedIDs — a
                    // prefix-only snapshot would unpin hearts on other pages.
                    tracksByContext["liked"] = prefix.tracks
                    likedIDs.formUnion(prefix.tracks.map(\.id))
                    knownLikeIDs.formUnion(prefix.tracks.map(\.id))
                    likedServerTotal = prefix.total
                    likedCount = prefix.total
                }

                let tracks = try await withAPIAuthRetry(for: epoch) { api in
                    try await api.likedTracks(after: prefix)
                }
                guard epoch == accountEpoch else { return }
                applyLikedSnapshot(
                    displayTracks: tracks,
                    confirmedServerIDs: Set(tracks.map(\.id)),
                    total: prefix.total,
                    displayIsComplete: true,
                    serverSnapshotIsComplete: true
                )
            } catch {
                guard epoch == accountEpoch else { return }
                if loadingToken != nil { tracksError["liked"] = error.localizedDescription }
                dlog("liked refresh failed: \(error)")
            }
        }
    }

    func handleAppDidBecomeActive() {
        refreshLiked(force: false)
    }

    /// Toggles like state for one track. Optimistic UI; server PUT/DELETE
    /// runs in the background, reverts on failure. Also keeps the liked
    /// page cache and sidebar count coherent.
    func toggleLike(_ track: SpotifyClient.Track) {
        guard authState == .loggedIn else { return }
        guard isLikeKnown(track.id) else {
            requestLikedState(track.id)
            return
        }
        let wasLiked = likedIDs.contains(track.id)
        rememberLikeOverride(track, liked: !wasLiked)
        knownLikeIDs.insert(track.id)
        if wasLiked {
            likedIDs.remove(track.id)
        } else {
            likedIDs.insert(track.id)
        }
        if likedServerTotal != nil {
            likedCount += wasLiked ? -1 : 1
        }

        // Liked page cache maintenance: unliking removes the row, a like
        // inserts at top (matches Spotify's newest-first ordering).
        if var liked = tracksByContext["liked"] {
            if wasLiked {
                liked.removeAll { $0.id == track.id }
                tracksByContext["liked"] = liked
            } else {
                liked.insert(track, at: 0)
                tracksByContext["liked"] = liked
            }
        }

        if activeLikeMutations.insert(track.id).inserted {
            let epoch = accountEpoch
            Task { [weak self] in
                await self?.flushLikeMutations(for: track.id, epoch: epoch)
            }
        }
    }

    /// Persists toggles for one track in order. If the user toggles again while
    /// a request is in flight, only the latest desired state is sent next.
    private func flushLikeMutations(for id: String, epoch: Int) async {
        defer {
            if epoch == accountEpoch { activeLikeMutations.remove(id) }
        }
        while epoch == accountEpoch, let attempted = likeOverrides[id] {
            do {
                try await persistLike(id: id, liked: attempted.liked, epoch: epoch)
            } catch {
                guard epoch == accountEpoch else { return }
                // An older failed request must not undo a newer click.
                guard likeOverrides[id]?.mutationID == attempted.mutationID else { continue }
                revertLike(attempted.track, failedDesired: attempted.liked)
                return
            }

            guard var latest = likeOverrides[id] else { return }
            guard latest.liked != attempted.liked else {
                latest.expiresAt = Date().addingTimeInterval(likeOverrideLagWindow)
                likeOverrides[id] = latest
                return
            }
        }
    }

    private func persistLike(id: String, liked: Bool, epoch: Int) async throws {
        func mutate(using api: SpotifyClient) async throws {
            if liked {
                try await api.saveTracks(ids: [id])
            } else {
                try await api.removeTracks(ids: [id])
            }
        }

        guard epoch == accountEpoch, let api = self.api else { throw CancellationError() }
        do {
            try await mutate(using: api)
        } catch SpotifyClient.APIError.needsAuth {
            guard epoch == accountEpoch else { throw CancellationError() }
            await refreshAPIClient(for: epoch, forceRefresh: true)
            guard epoch == accountEpoch, let refreshedAPI = self.api else { throw CancellationError() }
            try await mutate(using: refreshedAPI)
        }
    }

    /// Player-bar like: the playing track may not be in any loaded context —
    /// build a minimal Track so the same toggle path applies.
    func toggleLikePlaying() {
        guard let np = nowPlaying, let id = SpotifyClient.trackId(from: np.uri) else { return }
        let track = SpotifyClient.Track(
            id: id, uri: np.uri, name: np.title,
            durationMs: Int(durationMs), artists: np.artists,
            artistDisplayText: np.artist,
            albumName: np.album, albumId: np.albumId, artworkURL: np.artworkURL
        )
        toggleLike(track)
    }

    private func revertLike(_ track: SpotifyClient.Track, failedDesired: Bool) {
        dlog("like toggle FAILED for \(track.id), reverting")
        guard likeOverrides[track.id]?.liked == failedDesired else { return }
        forgetLikeOverride(track.id)
        if failedDesired {
            let removed = likedIDs.remove(track.id) != nil
            if removed, likedServerTotal != nil { likedCount -= 1 }
        } else {
            let inserted = likedIDs.insert(track.id).inserted
            if inserted, likedServerTotal != nil { likedCount += 1 }
        }
        if var liked = tracksByContext["liked"] {
            if failedDesired {
                liked.removeAll { $0.id == track.id }
            } else {
                if !liked.contains(where: { $0.id == track.id }) {
                    liked.insert(track, at: 0)
                }
            }
            tracksByContext["liked"] = liked
        }
    }
    private(set) var tracksByContext: [String: [SpotifyClient.Track]] = [:]

    /// Artist discography (albums + singles + compilations), keyed by artist
    /// context key. Absent = still loading; [] = artist has none.
    private(set) var albumsByArtist: [String: [SpotifyClient.AlbumInfo]] = [:]
    /// Full artist profiles, including portrait URLs. Track responses only
    /// carry simplified artists and usually omit their images.
    private(set) var artistsByID: [String: SpotifyClient.Artist] = [:]
    private var artistProfileFetches: Set<String> = []
    /// Request ownership for track loaders, isolated by page context.
    private var trackLoadingTokens: [String: UUID] = [:]
    private(set) var tracksError: [String: String] = [:]
    /// Increments on every open() — stale load tasks compare and discard.
    private var loadEpoch = 0

    func isLoadingTracks(contextKey: String) -> Bool {
        trackLoadingTokens[contextKey] != nil
    }

    private func beginTrackLoading(contextKey: String) -> UUID {
        let token = UUID()
        trackLoadingTokens[contextKey] = token
        return token
    }

    private func endTrackLoading(contextKey: String, token: UUID) {
        guard trackLoadingTokens[contextKey] == token else { return }
        trackLoadingTokens.removeValue(forKey: contextKey)
    }


    // MARK: - Lifecycle

    init() {
        installCoreCallbacks()
    }

    private var nowPlayingMgr: NowPlayingManager { NowPlayingManager.shared }

    func start() {
        Task {
            do {
                dlog("silent refresh…")
                let web = try await SpotifyAuth.refreshAccessToken(for: .web)
                apply(webToken: web)
                dlog("web refresh OK, playback refresh…")
                let playback = try await SpotifyAuth.refreshAccessToken(for: .playback)
                apply(playbackToken: playback)
                dlog("refresh OK, init player…")
                try await initPlayerAndUser()
                nowPlayingMgr.activate()
                authState = .loggedIn
                dlog("logged in (silent)")
            } catch {
                if case SpotifyAuth.AuthError.refreshTokenRevoked = error {
                    // SpotifyAuth attempted to drop the dead credential and
                    // includes any cleanup failure in the surfaced error.
                    dlog("silent login failed: \(error)")
                    authError = error.localizedDescription
                    authState = .loggedOut
                } else if error is PlayerInitError {
                    // Credentials are valid — only the player couldn't start
                    // (typically Spotify accesspoint risk-control throttling).
                    // Don't bounce to the login page: Web API (library,
                    // search) works without the dealer; playback recovers on
                    // a later launch once the block decays.
                    dlog("player init failed, keeping session: \(error)")
                    authState = .loggedIn
                    connectionNote = "Playback service unavailable — will retry on relaunch"
                    loadLibrary()
                } else {
                    dlog("silent login failed: \(error)")
                    authError = error.localizedDescription
                    authState = .loggedOut
                }
            }
        }
    }

    func signIn() {
        authState = .signingIn
        authError = nil
        Task {
            do {
                let tokens = try await SpotifyAuth.signIn()
                apply(webToken: tokens.web)
                apply(playbackToken: tokens.playback)
                try await initPlayerAndUser()
                nowPlayingMgr.activate()
                authState = .loggedIn
                // The browser that hosted the OAuth journey holds focus;
                // pull nanyin back to the foreground so the completed
                // sign-in is actually visible (no nanyin:// scheme needed).
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                authError = error.localizedDescription
                authState = .loggedOut
                // Same for failures: surface the error instead of leaving
                // the user staring at a closed browser tab.
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Clean shutdown of the Rust core (Connect goodbye) — app quit path.
    func shutdown() {
        _ = Core.shutdown()
        AudioRenderer.shared.stop()
        NowPlayingManager.shared.clear()
    }

    /// Invalidates every task carrying the current account epoch before any
    /// replacement credentials can be installed.
    private func invalidateAccountSession() {
        accountEpoch += 1
        _ = Core.shutdown()
        AudioRenderer.shared.stop()
        webRefreshInFlight?.task.cancel()
        webRefreshInFlight = nil
        likedProbeTask?.cancel()
        likedProbeTask = nil
        pendingLikeProbeIDs.removeAll()
        likedIDs.removeAll()
        knownLikeIDs.removeAll()
        likedSnapshotComplete = false
        likeOverrides.removeAll()
        activeLikeMutations.removeAll()
        isRefreshingLiked = false
        likedRefreshPending = false
        lastLikedRefresh = .distantPast
        likedServerTotal = nil
        likedCount = 0
        tracksByContext["liked"] = nil
        trackLoadingTokens["liked"] = nil
        tracksError["liked"] = nil
        playbackAccessToken = ""
        webAccessToken = ""
        webTokenExpiry = .distantPast
        api = nil
        userDisplayName = ""
        userId = ""
        nowPlaying = nil
        connectionNote = nil
        queueEpoch += 1
        queueCurrent = nil
        queueUpcoming = []
        queueRecent = []
        pendingQueueHistory = nil
        isLoadingQueue = false
        queueRefreshPending = false
        authState = .loggedOut
    }

    func signOut() async {
        invalidateAccountSession()
        var keychainErrors: [String] = []
        for kind in [SpotifyAuth.TokenKind.web, .playback] {
            do {
                try await SpotifyAuth.clearRefreshToken(for: kind)
            } catch {
                keychainErrors.append(error.localizedDescription)
                dlog("sign-out credential cleanup failed: \(error)")
            }
        }
        authError = keychainErrors.isEmpty
            ? nil
            : "Signed out, but stored credentials could not be removed: \(keychainErrors.joined(separator: "; "))"
    }

    private func apply(webToken: SpotifyAuth.Token) {
        webAccessToken = webToken.accessToken
        webTokenExpiry = webToken.expiresAt
        api = SpotifyClient(accessToken: webToken.accessToken)
    }

    private func apply(playbackToken: SpotifyAuth.Token) {
        playbackAccessToken = playbackToken.accessToken
    }

    private func initPlayerAndUser() async throws {
        let deviceId = try KeychainStore.spotifyDeviceId()
        let rc = await Core.initializePlayer(accessToken: playbackAccessToken, deviceId: deviceId)
        guard rc == 0 else {
            let detail = Core.lastErrorMessage() ?? "unknown"
            dlog("player init rc=\(rc): \(detail)")
            throw PlayerInitError(detail: "Player init failed (rc \(rc)): \(detail)")
        }
        do {
            if let profile = try await api?.currentUser() {
                userDisplayName = profile.displayName ?? profile.id
                userId = profile.id
                dlog("/v1/me OK — \(userDisplayName) (id \(userId))")
            }
        } catch {
            dlog("/v1/me failed: \(error)")
        }
        loadLibrary()
    }

    /// Loads playlists + liked songs in the background after login.
    private func loadLibrary() {
        Task {
            do {
                playlists = try await api!.playlists()
            } catch {
                dlog("library load failed: \(error)")
            }
            refreshLiked(force: true)
        }
    }

    // MARK: - Search (M3)

    private(set) var isSearching = false
    /// Search field text — kept here so it survives page switches.
    var searchQuery = ""
    /// Artist results of the current search (top row; click → artist page).
    private(set) var searchArtists: [SpotifyClient.Artist] = []
    /// Increments on focusSearch() — SearchView focuses its field on change.
    private(set) var searchFocusToken = 0
    private var searchEpoch = 0
    private var searchDebounce: Task<Void, Never>?

    /// ⌘K/⌘F: open the Search page and focus the field.
    func focusSearch() {
        open(.search)
        searchFocusToken += 1
    }

    /// Debounced as-you-type search (≥300ms, roadmap 3.1).
    func searchDebounced(_ raw: String) {
        searchDebounce?.cancel()
        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            search(raw)
        }
    }

    func search(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        searchEpoch += 1
        searchDebounce?.cancel() // submit supersedes a pending debounce
        tracksError["search"] = nil
        guard !query.isEmpty else {
            tracksByContext["search"] = nil
            searchArtists = []
            isSearching = false
            return
        }
        let epoch = searchEpoch
        isSearching = true
        Task {
            do {
                // Token may have expired while idle — revalidate (same as open()).
                await refreshAPIClient()
                let results = try await api!.search(query)
                // Discard if the query changed mid-flight.
                guard epoch == searchEpoch else { return }
                dlog("search \"\(query)\" → \(results.tracks.count) tracks, \(results.artists.count) artists")
                tracksByContext["search"] = results.tracks
                searchArtists = results.artists
            } catch {
                guard epoch == searchEpoch else { return }
                tracksError["search"] = error.localizedDescription
                dlog("search failed: \(error)")
            }
            if epoch == searchEpoch {
                isSearching = false
            }
        }
    }

    // MARK: - Queue (M2.3)

    struct QueueItem: Identifiable {
        let id = UUID()
        let track: SpotifyClient.Track
        let artist: String

        init(track: SpotifyClient.Track, artist: String? = nil) {
            self.track = track
            self.artist = artist ?? track.artistDisplayText
                ?? track.artists.map(\.name).joined(separator: ", ")
        }
    }

    /// The active device's current track from the queue endpoint.
    private(set) var queueCurrent: SpotifyClient.Track?
    /// Context continuation after the current track (Web API order —
    /// user-added entries first, then the context tail).
    private(set) var queueUpcoming: [QueueItem] = []
    /// Recently played, appended locally on each track change.
    private(set) var queueRecent: [QueueItem] = []
    private(set) var isLoadingQueue = false
    private var queueEpoch = 0
    private var queueRefreshPending = false
    private var pendingQueueHistory: (nowPlaying: NowPlaying, durationMs: UInt32)?

    /// Refreshes the queue from GET /v1/me/player/queue (the active device's
    /// queue — reflects adds from any client, including ours). Dealer cluster
    /// pushes are not available to third-party clients (verified: the dealer
    /// websocket rejects SUBSCRIBE frames), so this polls on the events that
    /// change the queue instead.
    func refreshQueue() {
        guard authState == .loggedIn else { return }
        guard !isLoadingQueue else {
            queueRefreshPending = true
            return
        }
        isLoadingQueue = true
        queueEpoch += 1
        let epoch = queueEpoch
        let account = accountEpoch
        Task {
            defer {
                if epoch == queueEpoch {
                    isLoadingQueue = false
                    if queueRefreshPending {
                        queueRefreshPending = false
                        refreshQueue()
                    }
                }
            }
            do {
                await refreshAPIClient(for: account)
                guard account == accountEpoch,
                      epoch == queueEpoch,
                      authState == .loggedIn,
                      let api else { return }
                let result = try await api.playerQueue()
                guard account == accountEpoch,
                      epoch == queueEpoch,
                      authState == .loggedIn else { return }
                queueCurrent = result.current
                queueUpcoming = result.upcoming.map { QueueItem(track: $0) }
            } catch {
                dlog("queue refresh failed: \(error)")
            }
        }
    }

    /// Delayed refresh after an add-to-queue (server needs a moment to settle).
    func refreshQueueSoon() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshQueue()
        }
    }

    /// Tracks local recently-played history for the queue view.
    private func trackQueueHistory(_ np: NowPlaying, durationMs: UInt32) {
        let item = QueueItem(
            track: SpotifyClient.Track(
                id: SpotifyClient.trackId(from: np.uri) ?? np.uri,
                uri: np.uri, name: np.title,
                durationMs: Int(durationMs), artists: np.artists,
                albumName: np.album, albumId: np.albumId, artworkURL: np.artworkURL
            ),
            artist: np.artist
        )
        queueRecent.removeAll { $0.track.uri == np.uri }
        queueRecent.insert(item, at: 0)
        if queueRecent.count > 30 {
            queueRecent.removeLast(queueRecent.count - 30)
        }
    }

    // MARK: - Navigation

    /// Navigate forward to a new page (sidebar click, artist/album link…).
    /// Pushes the current page onto the history stack and clears the forward
    /// stack — a fresh branch of navigation.
    func open(_ newPage: Page) {
        guard newPage != page else {
            // Re-clicking the current live page is a manual refresh.
            if case .liked = newPage { refreshLiked(force: true) }
            if case .queue = newPage { refreshQueue() }
            return
        }
        history.append(page)
        forwardStack.removeAll()
        navigate(to: newPage)
    }

    /// Walk back to the previous page (sidebar ◀ / ⌘[).
    func goBack() {
        guard let previous = history.popLast() else { return }
        forwardStack.append(page)
        navigate(to: previous)
    }

    /// Re-enter a page we walked back from (sidebar ▶ / ⌘]).
    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        history.append(page)
        navigate(to: next)
    }

    /// Applies the page and loads its content only when the cache misses
    /// (back/forward into an already-visited page is instant).
    private func navigate(to newPage: Page) {
        page = newPage
        if case .queue = newPage {
            refreshQueue()
        }
        if case .liked = newPage {
            // refreshLiked owns the fetch (and the first-visit loader).
            refreshLiked(force: true)
            return
        }
        if case let .artist(id, _, artworkURL) = newPage, artworkURL == nil {
            // Start the portrait request at the same time as the page data,
            // instead of waiting for ArtistDetailView's first render.
            loadArtistProfileIfNeeded(id: id)
        }
        guard let key = newPage.contextKey, tracksByContext[key] == nil else { return }
        let loadingToken = beginTrackLoading(contextKey: key)
        tracksError[key] = nil
        loadEpoch += 1
        let epoch = loadEpoch
        Task {
            defer { endTrackLoading(contextKey: key, token: loadingToken) }
            do {
                // Token may have expired while the app sat idle — revalidate.
                await refreshAPIClient()
                var discography: [SpotifyClient.AlbumInfo]?
                let tracks: [SpotifyClient.Track]
                switch newPage {
                case .liked:
                    tracks = try await api!.likedTracks()
                case let .playlist(id, _):
                    tracks = try await api!.playlistTracks(id)
                case let .artist(id, _, _):
                    // Top tracks and discography in parallel; discography is a
                    // bonus section — its failure must not fail the page.
                    async let albums = api!.artistAlbums(id)
                    do {
                        tracks = try await api!.artistTopTracks(id)
                    } catch {
                        // Preserve a successful discography even when the
                        // top-tracks endpoint fails, so the artist page can
                        // still show Albums/Singles alongside the error.
                        if let releases = try? await albums, epoch == loadEpoch {
                            albumsByArtist[key] = releases
                            dlog("discography \(key) → \(releases.count) releases (top tracks failed)")
                        }
                        throw error
                    }
                    discography = try? await albums
                case let .album(id, _, _, _):
                    tracks = try await api!.albumTracks(id)
                case .search:
                    // Results are fetched by search(), not by page-open.
                    return
                case .queue, .home:
                    // Live views — nothing to prefetch.
                    return
                }
                // Discard if the user navigated elsewhere mid-flight (P0-3).
                guard epoch == loadEpoch else { return }
                tracksByContext[key] = tracks
                if let discography {
                    albumsByArtist[key] = discography
                    dlog("discography \(key) → \(discography.count) releases")
                }
            } catch {
                guard epoch == loadEpoch else { return }
                tracksError[key] = error.localizedDescription
                dlog("tracks load failed: \(error)")
            }
        }
    }

    /// Loads a full artist profile when a navigation source did not include
    /// the artist portrait (track artist objects commonly omit images).
    func loadArtistProfileIfNeeded(id: String) {
        guard artistsByID[id] == nil, !artistProfileFetches.contains(id) else { return }
        artistProfileFetches.insert(id)
        Task {
            defer { artistProfileFetches.remove(id) }
            var artist: SpotifyClient.Artist?
            do {
                if let client = api {
                    // The existing client is already authenticated in the
                    // normal path; avoid a redundant token check here.
                    artist = try await client.artist(id)
                } else {
                    await refreshAPIClient()
                    artist = try? await api?.artist(id)
                }
            } catch SpotifyClient.APIError.needsAuth {
                // Refresh only when the current client is actually rejected.
                await refreshAPIClient(forceRefresh: true)
                artist = try? await api?.artist(id)
            } catch {
                return
            }
            guard let artist else { return }
            artistsByID[id] = artist
        }
    }

    /// Player-bar artist link → first artist's page. When ids aren't known
    /// yet (track started from another device — TrackChanged carries names
    /// only), fetch metadata first, then navigate. Failed fetches stop the
    /// chain instead of retrying forever.
    func openNowPlayingArtist() {
        openNowPlaying { np in
            guard let artist = np.artists.first else { return nil }
            return .artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL)
        }
    }

    /// Player-bar album link. Same id-missing fallback as the artist link.
    func openNowPlayingAlbum() {
        openNowPlaying { np in
            guard let id = np.albumId, !id.isEmpty else { return nil }
            return .album(id: id, name: np.album, subtitle: np.artist, artworkURL: np.artworkURL)
        }
    }

    private var metadataFetchInFlight = false

    private func openNowPlaying(buildPage: @escaping (NowPlaying) -> Page?) {
        guard let np = nowPlaying else { return }
        if let target = buildPage(np) {
            open(target)
            return
        }
        ensureNowPlayingMetadata { [weak self] succeeded in
            if succeeded { self?.openNowPlaying(buildPage: buildPage) }
        }
    }

    /// Fills in NowPlaying's artist/album ids via /v1/tracks when they're
    /// missing (external start). Reports whether richer metadata was applied
    /// — callers use that to decide whether retrying navigation is useful.
    private func ensureNowPlayingMetadata(completion: @escaping (Bool) -> Void) {
        guard !metadataFetchInFlight,
              let uri = nowPlaying?.uri,
              let id = SpotifyClient.trackId(from: uri) else {
            completion(false)
            return
        }
        metadataFetchInFlight = true
        Task {
            var succeeded = false
            if let track = try? await api?.track(id: id) {
                applyNowPlaying(track)
                succeeded = true
            }
            metadataFetchInFlight = false
            completion(succeeded)
        }
    }

    /// Plays a track within its loaded context. Large contexts go through
    /// server-resolved context URIs (liked = spotify:user:<id>:collection,
    /// playlist = spotify:playlist:<id>) — uploading thousands of URIs into
    /// Connect state gets 429-rejected. Falls back to a bounded track window
    /// if the context path doesn't start audio in time.
    func play(track: SpotifyClient.Track, contextKey: String) {
        if pendingQueueHistory == nil, let nowPlaying, nowPlaying.uri != track.uri {
            pendingQueueHistory = (nowPlaying, durationMs)
        }
        applyNowPlaying(track)
        isBuffering = true

        let index = tracksByContext[contextKey]?.firstIndex(where: { $0.uri == track.uri }) ?? 0
        let contextURI: String?
        switch page {
        case .liked:
            // A newly inserted/removed local row may not have reached Spotify's
            // server-resolved collection yet, so its local index is unsafe.
            contextURI = userId.isEmpty || hasPendingLikeOverrides()
                ? nil
                : "spotify:user:\(userId):collection"
        case let .playlist(id, _):
            contextURI = "spotify:playlist:\(id)"
        case let .album(id, _, _, _):
            contextURI = "spotify:album:\(id)"
        case .search, .artist, .queue, .home:
            // Ad-hoc context: results are small — play the window directly.
            contextURI = nil
        }

        if let contextURI {
            let rc = Core.playContext(contextURI, startIndex: index)
            dlog("playContext(\(contextURI), index \(index)) rc=\(rc)")
            if rc == 0 {
                scheduleContextFallback(track: track, contextKey: contextKey, index: index)
                return
            }
        }

        playWindowed(track: track, contextKey: contextKey, index: index)
    }

    /// Bounded-context fallback: 50 tracks from the clicked index.
    private func playWindowed(track: SpotifyClient.Track, contextKey: String, index: Int) {
        guard let context = tracksByContext[contextKey] else {
            _ = Core.playTracks([track.uri])
            return
        }
        let window = context.map(\.uri).dropFirst(index).prefix(50)
        let rc = Core.playTracks(Array(window), startIndex: 0)
        dlog("playWindowed(\(window.count) uris) rc=\(rc)")
    }

    /// If a context load doesn't produce audio within 8s, retry windowed.
    private func scheduleContextFallback(track: SpotifyClient.Track, contextKey: String, index: Int) {
        let uri = track.uri
        Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, isBuffering, nowPlaying?.uri == uri else { return }
            dlog("context load stalled — falling back to windowed tracks")
            playWindowed(track: track, contextKey: contextKey, index: index)
        }
    }

    // MARK: - Core callbacks

    private func installCoreCallbacks() {
        Core.onAudioData = { samples, count in
            AudioRenderer.shared.write(samples: samples, count: count)
        }
        Core.onAudioControl = { event in
            switch event {
            case 0: AudioRenderer.shared.stop()      // AUDIO_CONTROL_STOP
            case 1: AudioRenderer.shared.start()     // AUDIO_CONTROL_START
            case 2: AudioRenderer.shared.clear()     // AUDIO_CONTROL_CLEAR
            default: break
            }
        }
        Core.onConnected = {
            self.connectionNote = nil
        }
        Core.onDisconnected = {
            self.reconnect()
        }
        Core.onEvent = { event in
            self.handle(event)
        }
    }

    private func handle(_ event: Core.Event) {
        switch event {
        case .playing:
            isPlaying = true
            isBuffering = false
            pushNowPlayingInfo()
        case let .paused(_, positionMs):
            isPlaying = false
            _ = positionMs
            pushNowPlayingInfo()
        case .stopped:
            isPlaying = false
            isBuffering = false
            pushNowPlayingInfo()
        case let .loading(uri, _):
            isBuffering = true
            fetchMetadata(uri: uri)
        case let .trackChanged(uri, durationMs, title, artists, album, coverURL):
            let previous = nowPlaying
            let previousDurationMs = self.durationMs
            self.durationMs = UInt32(durationMs)
            dlog("trackChanged coverURL=\(coverURL ?? "nil") title=\(title ?? "nil")")
            let outgoing = pendingQueueHistory
                ?? previous.map { (nowPlaying: $0, durationMs: previousDurationMs) }
            pendingQueueHistory = nil
            if let outgoing, outgoing.nowPlaying.uri != uri {
                trackQueueHistory(outgoing.nowPlaying, durationMs: outgoing.durationMs)
            }
            // TrackChanged carries full metadata — no Web API round trip needed.
            if let title, !title.isEmpty {
                let known = nowPlaying?.uri == uri && nowPlaying?.title == title
                if !known {
                    nowPlaying = NowPlaying(
                        uri: uri,
                        title: title,
                        artist: artists ?? "",
                        artists: [],
                        album: album ?? "",
                        albumId: nil,
                        artworkURL: coverURL.flatMap(URL.init(string:))
                    )
                }
            } else {
                fetchMetadata(uri: uri)
            }
        case .position:
            break // position handled by PlayerBar's local Core.positionMs polling
        case let .shuffleChanged(on):
            shuffle = on
        case let .repeatChanged(context, track):
            switch (context, track) {
            case (true, true): repeatMode = .one
            case (true, false): repeatMode = .all
            case (false, true): repeatMode = .one
            case (false, false): repeatMode = .off
            }
        case .endOfTrack:
            break // Spirc auto-advances within the context
        }
        // Queue refresh on the two events that shift it (a new track also
        // fires on skip/prev, covering those without extra triggers).
        switch event {
        case .trackChanged, .endOfTrack:
            refreshQueueSoon()
        default:
            break
        }
    }

    private func fetchMetadata(uri: String) {
        // Skip when we already have richer local data for this URI.
        if nowPlaying?.uri == uri, nowPlaying?.title != "…" { return }
        guard let id = SpotifyClient.trackId(from: uri) else { return }
        if nowPlaying?.uri != uri {
            nowPlaying = NowPlaying(uri: uri, title: "…", artist: "", artists: [], album: "", albumId: nil, artworkURL: nil)
        }
        Task {
            guard let track = try? await api?.track(id: id) else {
                dlog("fetchMetadata FAILED for \(id)")
                return
            }
            let artwork = track.artworkURL
            dlog("fetchMetadata OK artwork=\(artwork?.absoluteString ?? "nil")")
            nowPlaying = NowPlaying(
                uri: uri,
                title: track.name,
                artist: track.artists.map(\.name).joined(separator: ", "),
                artists: track.artists,
                album: track.albumName,
                albumId: track.albumId,
                artworkURL: artwork
            )
        }
    }

    private func applyNowPlaying(_ track: SpotifyClient.Track) {
        nowPlaying = NowPlaying(
            uri: track.uri,
            title: track.name,
            artist: track.artists.map(\.name).joined(separator: ", "),
            artists: track.artists,
            album: track.albumName,
            albumId: track.albumId,
            artworkURL: track.artworkURL
        )
    }

    /// Session dropped: re-init the player with the existing token first
    /// (session drops are usually network/dealer events, NOT expired tokens).
    /// Only refresh the token when the existing one is actually rejected —
    /// aggressive refresh on every disconnect rotates tokens in a loop,
    /// which Spotify's risk control treats as abuse and revokes everything
    /// (learned the hard way: refresh token got invalidated).
    private func reconnect() {
        guard authState == .loggedIn else { return }
        let epoch = accountEpoch
        let accessToken = playbackAccessToken
        connectionNote = "Reconnecting…"
        Task {
            let deviceId: String
            do {
                deviceId = try KeychainStore.spotifyDeviceId()
            } catch {
                guard epoch == accountEpoch, authState == .loggedIn else { return }
                dlog("device id persistence failed: \(error)")
                connectionNote = "Connection lost — \(error.localizedDescription)"
                return
            }
            // 1) Try re-init with the CURRENT access token — cheap and usually
            //    sufficient (librespot also refreshes internally via login5).
            guard epoch == accountEpoch, authState == .loggedIn else { return }
            let rc = await Core.initializePlayer(accessToken: accessToken, deviceId: deviceId)
            guard epoch == accountEpoch, authState == .loggedIn else { return }
            if rc == 0 {
                connectionNote = nil
                return
            }
            // 2) Only if that fails, mint a fresh token via refresh.
            do {
                let token = try await SpotifyAuth.refreshAccessToken(for: .playback)
                guard epoch == accountEpoch, authState == .loggedIn else { return }
                apply(playbackToken: token)
                let rc2 = await Core.initializePlayer(accessToken: playbackAccessToken, deviceId: deviceId)
                guard epoch == accountEpoch, authState == .loggedIn else { return }
                connectionNote = rc2 == 0 ? nil : "Connection lost"
            } catch {
                guard epoch == accountEpoch, authState == .loggedIn else { return }
                if case SpotifyAuth.AuthError.refreshTokenRevoked = error {
                    // Dead credential: surface re-auth instead of a footnote.
                    // Retrying against a revoked token only feeds risk control.
                    dlog("playback refresh token revoked — forcing re-auth")
                    invalidateAccountSession()
                    authError = error.localizedDescription
                } else {
                    connectionNote = "Connection lost — sign in again"
                }
            }
        }
    }

    // MARK: - Playback commands

    func playURI(_ input: String) {
        var uri = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uri.hasPrefix("spotify:"), let id = SpotifyClient.trackId(from: uri) {
            uri = "spotify:track:\(id)"
        }
        dlog("playURI → \(uri)")
        let rc = Core.playTracks([uri])
        dlog("playTracks rc=\(rc)")
        if rc == 0 {
            isBuffering = true
        }
    }

    func togglePlay() {
        if isPlaying {
            _ = Core.pause()
        } else {
            _ = Core.resume()
        }
    }

    /// Mirrors current state into Control Center / lock screen.
    private func pushNowPlayingInfo() {
        guard let np = nowPlaying else {
            nowPlayingMgr.clear()
            return
        }
        nowPlayingMgr.updateNowPlaying(
            title: np.title,
            artist: np.artist,
            album: np.album,
            durationMs: durationMs,
            positionMs: Core.positionMs,
            isPlaying: isPlaying,
            artworkURL: np.artworkURL
        )
    }

    func toggleShuffle() {
        shuffle.toggle()
        _ = Core.setShuffle(shuffle)
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        _ = Core.setRepeat(repeatMode != .off)
        _ = Core.setRepeatTrack(repeatMode == .one)
    }

    /// Appends to the active queue (right-click → Add to queue).
    func addToQueue(_ track: SpotifyClient.Track) {
        let rc = Core.addToQueue(track.uri)
        if rc == 0 {
            refreshQueueSoon()
        }
    }

    func seek(to fraction: Double) {
        _ = Core.seek(UInt32(fraction * Double(max(durationMs, 1))))
    }

    func setVolume(_ fraction: Double) {
        volume = fraction
        AudioRenderer.shared.volume = Float(fraction)
        _ = Core.setVolume(UInt16(fraction * 65_535))
    }

    func next() { _ = Core.next() }
    func prev() { _ = Core.prev() }

}
