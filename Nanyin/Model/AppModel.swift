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
        let secrets = KeychainStore(service: (Bundle.main.bundleIdentifier ?? "com.cosmoss.nanyin") + ".credentials")
        account = Account(secrets: secrets)
        session = PlaybackSession(secrets: secrets)
        player = Player(session: session)
        library = Library(api: account.api)
        account.onSignedIn = { [weak self] profile in
            self?.session.start(for: profile.id)
            self?.library.signedIn(as: profile.id)
        }
        Task { await account.restore() }
    }

    func signOut() async {
        session.signOut()
        library.signedOut()
        await account.signOut()
    }
}
