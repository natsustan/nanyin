//
//  SpotifyAuth.swift
//  Nanyin
//

import AppKit
import CryptoKit
import Darwin
import Foundation
import Network

/// Spotify OAuth (Authorization Code + PKCE) against a local loopback redirect.
///
/// Two chained flows in ONE browser journey (cliamp's dual-client strategy):
///   1. Web API access via ncspot's production-approved client (own quota —
///      the keymaster pool is globally rate-limited).
///   2. Playback credential via the librespot keymaster client (accepted by
///      login5).
enum SpotifyAuth {
    enum TokenKind: String {
        case web // ncspot client — Web API
        case playback // keymaster client — librespot session

        var clientId: String {
            switch self {
            case .web: SpotifyConfig.webApiClientId
            case .playback: SpotifyConfig.playbackClientId
            }
        }

        var scopes: [String] {
            switch self {
            case .web: SpotifyConfig.webApiScopes
            case .playback: SpotifyConfig.playbackScopes
            }
        }

        var keychainKey: String {
            switch self {
            case .web: "web_refresh_token"
            case .playback: "playback_refresh_token"
            }
        }
    }

    struct Token: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    enum AuthError: Error, LocalizedError {
        case loopbackListenerFailed(String)
        case noAuthorizationCode
        case tokenExchangeFailed(String)
        case userCancelled
        case refreshFailed(String)
        /// The stored refresh token was rejected (revoked/expired). The
        /// credential is dead — only an interactive re-auth recovers.
        case refreshTokenRevoked(cleanupError: String?)

        var errorDescription: String? {
            switch self {
            case let .loopbackListenerFailed(msg): "Loopback listener failed: \(msg)"
            case .noAuthorizationCode: "No authorization code received"
            case let .tokenExchangeFailed(msg): "Token exchange failed: \(msg)"
            case .userCancelled: "Sign-in cancelled"
            case let .refreshFailed(msg): "Token refresh failed: \(msg)"
            case let .refreshTokenRevoked(cleanupError):
                if let cleanupError {
                    "Session expired and its stored credential could not be removed: \(cleanupError)"
                } else {
                    "Session expired — sign in again"
                }
            }
        }
    }

    // MARK: - Token persistence

    static func storedRefreshToken(for kind: TokenKind) throws -> String? {
        // Migrate: the original single-flow keymaster token (all scopes incl.
        // streaming) works as the playback refresh token.
        if kind == .playback, try KeychainStore.string(forKey: kind.keychainKey) == nil {
            if let legacy = try KeychainStore.string(forKey: "refresh_token") {
                try KeychainStore.setString(legacy, forKey: kind.keychainKey)
                try KeychainStore.delete(forKey: "refresh_token")
                return legacy
            }
        }
        return try KeychainStore.string(forKey: kind.keychainKey)
    }

    static func setRefreshToken(_ token: String?, for kind: TokenKind) throws {
        if let token {
            try KeychainStore.setString(token, forKey: kind.keychainKey)
        } else {
            try KeychainStore.delete(forKey: kind.keychainKey)
        }
    }

    /// Refreshes the access token of the given kind (no browser).
    static func refreshAccessToken(for kind: TokenKind) async throws -> Token {
        if kind == .playback {
            return try await withPlaybackRefreshLock {
                try await refreshAccessTokenUnlocked(for: kind)
            }
        }
        return try await refreshAccessTokenUnlocked(for: kind)
    }

    private static func refreshAccessTokenUnlocked(for kind: TokenKind) async throws -> Token {
        guard let refreshToken = try storedRefreshToken(for: kind) else {
            throw AuthError.refreshFailed("no stored refresh token")
        }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": kind.clientId,
        ]
        .map { "\($0)=\(escape($1))" }
        .joined(separator: "&")
        req.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            if body.contains("invalid_grant") {
                // Preserve the rejected-token diagnosis even if Keychain
                // cleanup fails, while surfacing that failure to the caller.
                var cleanupError: String?
                do {
                    try setRefreshToken(nil, for: kind)
                } catch {
                    cleanupError = error.localizedDescription
                }
                throw AuthError.refreshTokenRevoked(cleanupError: cleanupError)
            }
            throw AuthError.refreshFailed(body)
        }
        return try decodeToken(data, for: kind)
    }

    // MARK: - Interactive flow (two chained authorizations, one browser tab)

    /// Runs both flows: opens the browser once; after the first callback the
    /// page redirects to the second authorization; returns both tokens.
    static func signIn() async throws -> (web: Token, playback: Token) {
        let webFlow = Flow(kind: .web)
        let playbackFlow = Flow(kind: .playback)

        let waiter = try LoopbackWaiter(port: SpotifyConfig.loopbackPort, flows: [webFlow, playbackFlow])

        NSWorkspace.shared.open(URL(string: webFlow.authorizeURL)!)

        let callbacks = try await waiter.waitForCallbacks()
        guard callbacks.count == 2 else {
            throw AuthError.noAuthorizationCode
        }

        let webToken = try await exchange(callbacks[0], flow: webFlow)
        let playbackToken = try await exchange(callbacks[1], flow: playbackFlow)
        return (webToken, playbackToken)
    }

    struct Flow {
        let kind: TokenKind
        let verifier: String
        let state: String

        init(kind: TokenKind) {
            self.kind = kind
            verifier = Self.generateCodeVerifier()
            state = Self.generateCodeVerifier()
        }

        var authorizeURL: String {
            var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            components.queryItems = [
                .init(name: "client_id", value: kind.clientId),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: SpotifyConfig.redirectUri),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "code_challenge", value: Self.generateCodeChallenge(from: verifier)),
                .init(name: "state", value: state),
                .init(name: "scope", value: kind.scopes.joined(separator: " ")),
            ]
            return components.url!.absoluteString
        }

        static func generateCodeVerifier() -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return base64URLEncode(Data(bytes))
        }

        static func generateCodeChallenge(from verifier: String) -> String {
            base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
        }

        static func base64URLEncode(_ data: Data) -> String {
            data.base64EncodedString()
                .replacing("+", with: "-")
                .replacing("/", with: "_")
                .replacing("=", with: "")
        }
    }

    private static func exchange(_ callback: LoopbackWaiter.Callback, flow: Flow) async throws -> Token {
        guard callback.state == flow.state else {
            throw AuthError.loopbackListenerFailed("state mismatch")
        }
        guard let code = callback.code else {
            throw AuthError.noAuthorizationCode
        }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectUri,
            "client_id": flow.kind.clientId,
            "code_verifier": flow.verifier,
        ]
        .map { "\($0)=\(escape($1))" }
        .joined(separator: "&")
        req.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }
        return try decodeToken(data, for: flow.kind)
    }

    // MARK: - Helpers

    private static func decodeToken(_ data: Data, for kind: TokenKind) throws -> Token {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        if let refresh = r.refresh_token {
            try setRefreshToken(refresh, for: kind)
        }
        return Token(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(r.expires_in))
        )
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    /// Shares a BSD file lock with dealer_probe.sh so only one process can
    /// read, refresh, and persist the rotating playback credential at a time.
    private static func withPlaybackRefreshLock<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nanyin-playback-refresh.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw AuthError.refreshFailed("could not open playback refresh lock")
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else {
            throw AuthError.refreshFailed("could not acquire playback refresh lock")
        }
        defer { flock(fd, LOCK_UN) }
        return try await operation()
    }
}

// MARK: - Loopback listener (chained redirects)

/// Listens on 127.0.0.1:port; drives a chain of OAuth callbacks: each
/// intermediate callback gets a 302 to the next flow's authorize URL, the
/// last one gets the success page.
private final class LoopbackWaiter: @unchecked Sendable {
    // All mutable state (received, continuation, listener) is confined to
    // `queue`; NWConnection/timeout closures capture self only onto it.
    struct Callback {
        let code: String?
        let state: String?
    }

    private let listener: NWListener
    private let flows: [SpotifyAuth.Flow]
    private var received: [Callback] = []
    private var continuation: CheckedContinuation<[Callback], Error>?
    private let queue = DispatchQueue(label: "com.nanyin.auth.loopback")

    init(port: UInt16, flows: [SpotifyAuth.Flow]) throws {
        self.flows = flows
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    func waitForCallbacks() async throws -> [Callback] {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.fail(SpotifyAuth.AuthError.loopbackListenerFailed(error.localizedDescription))
                }
            }
            listener.start(queue: queue)
            // Safety timeout: never hang forever if the browser journey stalls.
            queue.asyncAfter(deadline: .now() + 300) { [weak self] in
                guard let self, self.continuation != nil else { return }
                self.fail(SpotifyAuth.AuthError.userCancelled)
            }
        }
    }

    private func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first
            else {
                connection.cancel()
                return
            }
            self.handleRequest(String(firstLine), connection: connection)
        }
    }

    private func handleRequest(_ firstLine: String, connection: NWConnection) {
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let path = String(parts[1])

        guard let queryStart = path.firstIndex(of: "?") else {
            connection.cancel()
            return
        }
        var params: [String: String] = [:]
        for pair in String(path[path.index(after: queryStart)...]).split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0]).removingPercentEncoding ?? String(kv[0])] =
                    String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }

        let callback = Callback(code: params["code"], state: params["state"])

        // Respond: redirect to next flow, or final success page.
        let response: String
        if received.count + 1 < flows.count, callback.code != nil {
            response = """
            HTTP/1.1 302 Found\r\nLocation: \(flows[received.count + 1].authorizeURL)\r\nConnection: close\r\n\r\n
            """
        } else {
            let body = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>nanyin</title></head>
            <body style="font-family:system-ui;background:#121212;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;margin:0">
            <h2>✅ Signed in to nanyin</h2>
            <script>setTimeout(function(){window.close()},1500)</script>
            </body></html>
            """
            response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        }

        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            // Only tear down the listener once ALL expected callbacks arrived
            // (cancelling early would refuse the chained flow's redirect back).
            if self.received.count >= self.flows.count {
                self.listener.cancel()
            }
        })

        // Only record callbacks whose state matches the expected flow.
        if let state = callback.state, flows[received.count].state == state {
            received.append(callback)
            if received.count == flows.count {
                continuation?.resume(returning: received)
                continuation = nil
            }
        } else if callback.code == nil {
            // Error callback (user denied) — fail the flow.
            fail(SpotifyAuth.AuthError.noAuthorizationCode)
        }
    }
}
