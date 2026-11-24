import Foundation
import NanyinKit
import Observation

/// Owns every model and wires them together.
@MainActor
@Observable
final class AppModel {
    let proxy: ProxyManager
    let account: Account
    let session: PlaybackSession
    let player: Player
    let library: Library
    let stars: Stars
    let history: PlayHistoryStore
    let navigator = Navigator()
    let notices = Notices()
    /// The credits sheet on the main window, while open.
    var credits: TrackCredits?
    /// The Proxy Settings sheet, opened from the signed-in Account menu.
    var showProxySheet = false
    /// Shown once right after Web API sign-in on a Premium account that has no
    /// saved playback credential yet; cleared once playback connects or is skipped.
    private var showPlaybackOnboarding = false
    private let nowPlaying: NowPlayingBridge

    /// Step 2 of onboarding: right after Web API sign-in on a Premium account
    /// that has never set up playback on this Mac yet.
    var needsPlaybackOnboarding: Bool {
        showPlaybackOnboarding && !session.isReady
    }

    /// Whether the main library shell (sidebar, pages, player bar, full toolbar)
    /// should be shown instead of the onboarding/connecting flow.
    var showsLibrary: Bool {
        account.profile != nil && !needsPlaybackOnboarding
    }

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.environment["NANYIN_DEMO"] == "1"
        #else
        let demo = false
        #endif
        let bundleID = Bundle.main.bundleIdentifier ?? "com.cosmoss.nanyin"
        let secrets: any SecretStore = demo
            ? MemorySecretStore()
            : KeychainStore(service: bundleID + ".credentials")
        proxy = ProxyManager(secrets: secrets)
        ImageLoader.shared.transport = proxy.transport
        account = Account(secrets: secrets, transport: proxy.transport)
        session = PlaybackSession(secrets: secrets, transport: proxy.transport, proxyURL: proxy.playbackProxyURL)
        player = Player(session: session, notices: notices)
        stars = Stars(api: account.api)
        history = PlayHistoryStore(bundleID: bundleID)
        library = Library(api: account.api, stars: stars, session: session, history: history, notices: notices)
        nowPlaying = NowPlayingBridge(player: player)
        navigator.willShow = { [library] route in library.prepare(route) }
        proxy.onPlaybackProxyChanged = { [session] url in session.updateProxy(url) }
        #if DEBUG
        if demo {
            DemoContent.install(in: self)
            return
        }
        #endif
        player.onTrackCounted = { [weak self] track in
            guard let self else { return }
            history.record(Track(
                name: track.name,
                uri: track.uri,
                duration_ms: track.durationMs,
                explicit: track.explicit,
                artists: track.artists.map { ArtistRef(name: $0.name, uri: $0.uri) },
                album: AlbumRef(name: track.album, uri: track.albumURI)
            ))
            library.didRecordPlay()
        }
        account.onSignedIn = { [weak self] profile in
            guard let self else { return }
            history.load(for: profile.id)
            session.start(for: profile.id)
            showPlaybackOnboarding = profile.isPremium && !session.hasStoredCredentials
            library.signedIn(as: profile.id, showing: navigator.current)
        }
        session.onReady = { [weak self] in
            self?.showPlaybackOnboarding = false
        }
        Task { await account.restore() }
        // Spotify refused the saved grant during some request: sign out
        // everywhere, as if the user had.
        Task { [weak self, revocations = account.auth.revocations] in
            for await _ in revocations { await self?.signOut() }
        }
    }

    func skipPlaybackSetup() {
        session.cancelAuthorize()
        showPlaybackOnboarding = false
    }

    func showCredits(trackID: String, title: String, artists: String) {
        credits = TrackCredits(trackID: trackID, title: title, artists: artists, session: session)
    }

    func signOut() async {
        credits = nil
        showProxySheet = false
        showPlaybackOnboarding = false
        player.signOut()
        session.signOut()
        history.unload()
        library.signedOut()
        stars.reset()
        navigator.reset()
        await account.signOut()
    }
}
