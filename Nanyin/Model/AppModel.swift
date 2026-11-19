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
    let navigator = Navigator()

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.environment["NANYIN_DEMO"] == "1"
        #else
        let demo = false
        #endif
        let secrets: any SecretStore = demo
            ? MemorySecretStore()
            : KeychainStore(service: (Bundle.main.bundleIdentifier ?? "com.cosmoss.nanyin") + ".credentials")
        account = Account(secrets: secrets)
        session = PlaybackSession(secrets: secrets)
        player = Player(session: session)
        library = Library(api: account.api)
        navigator.willShow = { [library] route in library.prepare(route) }
        #if DEBUG
        if demo {
            DemoContent.install(in: self)
            return
        }
        #endif
        account.onSignedIn = { [weak self] profile in
            guard let self else { return }
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

    func signOut() async {
        session.signOut()
        library.signedOut()
        navigator.reset()
        await account.signOut()
    }
}
