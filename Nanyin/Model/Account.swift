import Foundation
import NanyinKit
import Observation

/// The Web API sign-in: the listener's own Client ID and its grant.
@MainActor
@Observable
final class Account {
    enum State: Equatable {
        case signedOut
        case signingIn
        case loadingProfile
        case signedIn(UserProfile)
        case failed(String)
    }

    private(set) var state: State = .signedOut {
        didSet {
            if case .signedIn(let profile) = state, oldValue != state { onSignedIn(profile) }
        }
    }
    var onSignedIn: (UserProfile) -> Void = { _ in }
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Self.clientIDKey) }
    }

    let auth: WebAPIAuth
    let api: SpotifyWebAPI
    private let oauth = SpotifyOAuth()
    private var signInTask: Task<Void, Never>?
    private static let clientIDKey = "WebAPIClientID"

    var profile: UserProfile? {
        if case .signedIn(let profile) = state { profile } else { nil }
    }

    init(secrets: any SecretStore) {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        auth = WebAPIAuth(store: secrets)
        api = SpotifyWebAPI(auth: auth)
    }

    /// Restores a saved grant: one profile request, no browser.
    func restore() async {
        guard await auth.isSignedIn else { return }
        await loadProfile()
    }

    /// Explicit user action only: opens the browser.
    func signIn() {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OAuthGrant.looksLikeClientID(clientID) else {
            state = .failed("A Client ID is 32 letters and digits, from your app in the Spotify developer dashboard.")
            return
        }
        signInTask?.cancel()
        state = .signingIn
        signInTask = Task {
            do {
                if await oauth.clientIsKnown(clientID) == false {
                    throw OAuthError.unknownClient
                }
                try await auth.signIn(with: oauth.authorizeInBrowser(.webAPI(clientID: clientID)))
                await loadProfile()
            } catch is CancellationError {
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        state = .signedOut
    }

    func signOut() async {
        signInTask?.cancel()
        await auth.signOut()
        state = .signedOut
    }

    private func loadProfile() async {
        state = .loadingProfile
        do {
            state = .signedIn(try await api.me())
        } catch WebAPIError.signedOut, OAuthError.grantRevoked {
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

#if DEBUG
extension Account {
    func showDemo(_ profile: UserProfile) { state = .signedIn(profile) }
}
#endif
