import Foundation
import NanyinKit
import Observation

/// The Web API sign-in: the listener's own Client ID and its grant.
@MainActor
@Observable
final class Account {
    enum SignInProblem: Equatable {
        case malformedClientID
        case unknownClient
        case accountNotAllowed
        case expired
        case other(String)

        var message: String {
            switch self {
            case .malformedClientID:
                "That doesn't look like a Client ID. It is 32 hexadecimal characters on your app's page in the Spotify developer dashboard."
            case .unknownClient:
                "Spotify doesn't recognize this Client ID. Copy it again from your Spotify developer dashboard (make sure it isn't the Client Secret)."
            case .accountNotAllowed:
                "Spotify didn't let this account use this Client ID. Sign in with the Spotify account that created the app, and make sure it has Premium."
            case .expired:
                "Your Spotify sign-in expired. Sign in again to continue."
            case .other(let detail):
                detail
            }
        }

        /// Whether this error suggests the user should check their app registration steps.
        var needsSetupGuidance: Bool {
            switch self {
            case .malformedClientID, .unknownClient, .accountNotAllowed: true
            case .expired, .other: false
            }
        }
    }

    enum State: Equatable {
        /// Checking the Keychain for a saved sign-in at launch, so returning
        /// listeners never see the onboarding form flash by.
        case restoring
        case signedOut
        case checkingClient
        case waitingForBrowser(URL)
        case loadingProfile
        case signedIn(UserProfile)
        case failed(SignInProblem, canRetrySaved: Bool)
    }

    private(set) var state: State = .restoring {
        didSet {
            if case .signedIn(let profile) = state, oldValue != state { onSignedIn(profile) }
        }
    }
    var onSignedIn: (UserProfile) -> Void = { _ in }
    var clientID: String {
        didSet {
            let cleaned = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned != clientID { clientID = cleaned }
            UserDefaults.standard.set(cleaned, forKey: Self.clientIDKey)
        }
    }

    let auth: WebAPIAuth
    let api: SpotifyWebAPI
    private let oauth: SpotifyOAuth
    private var signInTask: Task<Void, Never>?
    private static let clientIDKey = "WebAPIClientID"

    var profile: UserProfile? {
        if case .signedIn(let profile) = state { profile } else { nil }
    }

    var isBusy: Bool {
        switch state {
        case .restoring, .checkingClient, .waitingForBrowser, .loadingProfile: true
        default: false
        }
    }

    init(secrets: any SecretStore, transport: HTTPTransport = .shared) {
        let saved = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        clientID = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        oauth = SpotifyOAuth(transport: transport)
        auth = WebAPIAuth(store: secrets, oauth: oauth)
        api = SpotifyWebAPI(auth: auth, transport: transport)
    }

    /// Restores a saved grant: one profile request, no browser.
    func restore() async {
        guard await auth.isSignedIn else {
            state = .signedOut
            return
        }
        await loadProfile(fromRestore: true)
    }

    /// Explicit retry of a saved sign-in after a transient failure.
    func retrySavedSignIn() {
        signInTask?.cancel()
        signInTask = Task { await restore() }
    }

    /// Explicit user action only: opens the browser.
    func signIn() {
        let id = clientID
        guard OAuthGrant.looksLikeClientID(id) else {
            state = .failed(.malformedClientID, canRetrySaved: false)
            return
        }
        signInTask?.cancel()
        state = .checkingClient
        signInTask = Task {
            do {
                if await oauth.clientIsKnown(id) == false {
                    throw OAuthError.unknownClient
                }
                let token = try await oauth.authorizeInBrowser(.webAPI(clientID: id)) { url in
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.state = .waitingForBrowser(url)
                        }
                    }
                }
                try await auth.signIn(with: token)
                await loadProfile(fromRestore: false)
            } catch is CancellationError {
            } catch OAuthError.unknownClient {
                state = .failed(.unknownClient, canRetrySaved: false)
            } catch {
                let hasSaved = await auth.isSignedIn
                state = .failed(.other(error.localizedDescription), canRetrySaved: hasSaved)
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
        signInTask = nil
        await auth.signOut()
        state = .signedOut
    }

    private func loadProfile(fromRestore: Bool) async {
        state = .loadingProfile
        do {
            let profile = try await api.me()
            guard !Task.isCancelled else { return }
            state = .signedIn(profile)
        } catch is CancellationError {
        } catch WebAPIError.http(403, _) {
            // Development Mode rejects accounts not added to the app or when
            // the app owner lacks Premium. Discard the unusable grant so the
            // listener can sign in with the right account.
            await auth.signOut()
            guard !Task.isCancelled else { return }
            state = .failed(.accountNotAllowed, canRetrySaved: false)
        } catch WebAPIError.signedOut, OAuthError.grantRevoked {
            guard !Task.isCancelled else { return }
            state = fromRestore ? .failed(.expired, canRetrySaved: false) : .signedOut
        } catch {
            guard !Task.isCancelled else { return }
            let hasSaved = await auth.isSignedIn
            state = .failed(.other(error.localizedDescription), canRetrySaved: hasSaved)
        }
    }
}

#if DEBUG
extension Account {
    func showDemo(_ profile: UserProfile) { state = .signedIn(profile) }
}
#endif
