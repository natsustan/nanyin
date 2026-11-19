import Foundation

/// The Web API grant: hands out access tokens and renews them.
///
/// Renewal discipline, because refresh storms are the kind of traffic that
/// gets an account looked at:
/// - a token is renewed only when it is about to expire, or after Spotify
///   answered 401 to that exact token;
/// - concurrent callers share one renewal;
/// - a replacement refresh token is saved before the new access token is
///   handed out, since the old one may already be dead;
/// - signing out wins: a renewal that finishes afterwards is discarded.
public actor WebAPIAuth {
    public static let tokenKey = "web-api-token"

    public enum Failure: Error, Equatable {
        case signedOut
    }

    private let store: any SecretStore
    private let refresher: @Sendable (OAuthToken) async throws -> OAuthToken
    private var loaded = false
    private var stored: OAuthToken?
    private var renewal: Task<OAuthToken, Error>?
    private var epoch = 0
    private let revokedContinuation: AsyncStream<Void>.Continuation

    /// Yields when Spotify rejects the saved grant and it is discarded, so
    /// the app can tear down everything that depended on it.
    public nonisolated let revocations: AsyncStream<Void>

    /// Read from the Keychain on first use, off the main thread.
    private var token: OAuthToken? {
        get {
            if !loaded {
                loaded = true
                stored = try? store.readValue(OAuthToken.self, Self.tokenKey)
            }
            return stored
        }
        set {
            loaded = true
            stored = newValue
        }
    }

    public init(store: any SecretStore, oauth: SpotifyOAuth = SpotifyOAuth()) {
        self.init(store: store, refresher: { try await oauth.refresh($0) })
    }

    init(store: any SecretStore, refresher: @escaping @Sendable (OAuthToken) async throws -> OAuthToken) {
        self.store = store
        self.refresher = refresher
        (revocations, revokedContinuation) = AsyncStream.makeStream()
    }

    public var isSignedIn: Bool { token != nil }

    public func signIn(with token: OAuthToken) throws {
        epoch += 1
        renewal?.cancel()
        renewal = nil
        try store.writeValue(token, for: Self.tokenKey)
        self.token = token
    }

    public func signOut() {
        epoch += 1
        renewal?.cancel()
        renewal = nil
        token = nil
        try? store.delete(Self.tokenKey)
    }

    /// A usable access token, renewed first if it is about to expire.
    public func accessToken() async throws -> String {
        guard let token else { throw Failure.signedOut }
        if token.isFresh() { return token.accessToken }
        return try await renew(token).accessToken
    }

    /// Spotify answered 401 to `rejected`. Renews unless another caller
    /// already did, and returns the token to retry with.
    public func tokenAfterRejection(of rejected: String) async throws -> String {
        guard let token else { throw Failure.signedOut }
        if token.accessToken != rejected { return token.accessToken }
        return try await renew(token).accessToken
    }

    private func renew(_ current: OAuthToken) async throws -> OAuthToken {
        if let renewal { return try await renewal.value }
        let started = epoch
        let refresher = refresher
        let task = Task { try await refresher(current) }
        renewal = task
        defer { if epoch == started { renewal = nil } }
        do {
            let renewed = try await task.value
            guard epoch == started else { throw Failure.signedOut }
            try store.writeValue(renewed, for: Self.tokenKey)
            token = renewed
            return renewed
        } catch OAuthError.grantRevoked where epoch == started {
            signOut()
            revokedContinuation.yield()
            throw OAuthError.grantRevoked
        }
    }
}
