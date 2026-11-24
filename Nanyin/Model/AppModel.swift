import Foundation
import NanyinKit
import Observation

/// Owns every model and wires them together.
@MainActor
@Observable
final class AppModel {
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
    private let nowPlaying: NowPlayingBridge

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
        account = Account(secrets: secrets)
        session = PlaybackSession(secrets: secrets)
        player = Player(session: session, notices: notices)
        stars = Stars(api: account.api)
        history = PlayHistoryStore(bundleID: bundleID)
        library = Library(api: account.api, stars: stars, session: session, history: history, notices: notices)
        nowPlaying = NowPlayingBridge(player: player)
        navigator.willShow = { [library] route in library.prepare(route) }
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
            library.signedIn(as: profile.id, showing: navigator.current)
        }
        Task { await account.restore() }
        // Spotify refused the saved grant during some request: sign out
        // everywhere, as if the user had.
        Task { [weak self, revocations = account.auth.revocations] in
            for await _ in revocations { await self?.signOut() }
        }
    }

    func showCredits(trackID: String, title: String, artists: String) {
        credits = TrackCredits(trackID: trackID, title: title, artists: artists, session: session)
    }

    func signOut() async {
        credits = nil
        player.signOut()
        session.signOut()
        history.unload()
        library.signedOut()
        stars.reset()
        navigator.reset()
        await account.signOut()
    }
}
