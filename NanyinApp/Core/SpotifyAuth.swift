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
    enum TokenKind: String, Sendable {
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

    struct Token: Codable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    enum AuthError: Error, LocalizedError {
        case loopbackListenerFailed(String)
        case noAuthorizationCode
        case tokenExchangeFailed(String)
        case userCancelled
        case noStoredCredential
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
            case .noStoredCredential: "No stored credential"
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

    /// Serializes refresh and persistence for one credential kind. The actor
    /// deliberately yields during the HTTP request, so `clear()` can advance
    /// the revision immediately; the late response then fails its persistence
    /// fence instead of resurrecting a signed-out credential.
    private actor TokenCoordinator {
        private let kind: TokenKind
        private var persistenceState = CredentialPersistenceState()
        private var inFlight: (id: UUID, task: Task<Token, Error>)?

        init(kind: TokenKind) {
            self.kind = kind
        }

        func refresh(
            request: @escaping @Sendable (String) async throws -> Token
        ) async throws -> Token {
            guard let expectedRevision = persistenceState.beginRefresh() else {
                throw AuthError.refreshFailed("credential was cleared")
            }
            if let inFlight {
                return try await inFlight.task.value
            }

            let id = UUID()
            let task = Task<Token, Error> {
                if self.kind == .playback {
                    return try await SpotifyAuth.withPlaybackRefreshLock {
                        try await self.performRefresh(
                            expectedRevision: expectedRevision,
                            request: request
                        )
                    }
                }
                return try await self.performRefresh(
                    expectedRevision: expectedRevision,
                    request: request
                )
            }
            inFlight = (id, task)

            do {
                let token = try await task.value
                clearInFlight(id: id)
                return token
            } catch {
                clearInFlight(id: id)
                throw error
            }
        }

        func beginInteractiveSession() -> UInt64 {
            inFlight?.task.cancel()
            inFlight = nil
            return persistenceState.beginNewSession()
        }

        func install(_ token: String?, expectedRevision: UInt64) throws {
            guard persistenceState.acceptsRefresh(expectedRevision) else {
                throw CancellationError()
            }
            guard let token else { return }
            try SpotifyAuth.setRefreshTokenUncoordinated(token, for: kind)
        }

        func clear() throws {
            invalidateRefreshes()
            try deleteCredential()
        }

        func invalidateRefreshes() {
            persistenceState.beginClear()
            inFlight?.task.cancel()
            inFlight = nil
        }

        func deleteCredential() throws {
            try SpotifyAuth.setRefreshTokenUncoordinated(nil, for: kind)
            if kind == .playback {
                try KeychainStore.delete(forKey: "refresh_token")
            }
        }

        func deleteCredential(expectedRevision: UInt64) throws {
            guard persistenceState.acceptsRefresh(expectedRevision) else {
                throw CancellationError()
            }
            try deleteCredential()
        }

        private func persistReplacement(
            _ token: String?,
            expectedRevision: UInt64
        ) throws {
            guard persistenceState.acceptsRefresh(expectedRevision) else {
                throw CancellationError()
            }
            if let token {
                try SpotifyAuth.setRefreshTokenUncoordinated(token, for: kind)
            }
        }

        private func performRefresh(
            expectedRevision: UInt64,
            request: @escaping @Sendable (String) async throws -> Token
        ) async throws -> Token {
            guard persistenceState.acceptsRefresh(expectedRevision) else {
                throw CancellationError()
            }
            guard let storedToken = try SpotifyAuth.storedRefreshTokenUncoordinated(for: kind) else {
                throw AuthError.noStoredCredential
            }
            let token = try await request(storedToken)
            try persistReplacement(
                token.refreshToken,
                expectedRevision: expectedRevision
            )
            return token
        }

        private func clearInFlight(id: UUID) {
            if inFlight?.id == id {
                inFlight = nil
            }
        }
    }

    private static let webTokenCoordinator = TokenCoordinator(kind: .web)
    private static let playbackTokenCoordinator = TokenCoordinator(kind: .playback)
    private static let interactiveSignInLock = NSLock()
    nonisolated(unsafe) private static var interactiveSignInID: UUID?

    private static func beginInteractiveSignIn() -> UUID {
        interactiveSignInLock.lock()
        defer { interactiveSignInLock.unlock() }
        let id = UUID()
        interactiveSignInID = id
        return id
    }

    private static func acceptsInteractiveSignIn(_ id: UUID) -> Bool {
        interactiveSignInLock.lock()
        defer { interactiveSignInLock.unlock() }
        return interactiveSignInID == id
    }

    static func invalidateInteractiveSignIn() {
        interactiveSignInLock.lock()
        interactiveSignInID = nil
        interactiveSignInLock.unlock()
    }

    // MARK: - Token persistence

    private static func storedRefreshTokenUncoordinated(for kind: TokenKind) throws -> String? {
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

    private static func setRefreshTokenUncoordinated(
        _ token: String?,
        for kind: TokenKind
    ) throws {
        if let token {
            try KeychainStore.setString(token, forKey: kind.keychainKey)
        } else {
            try KeychainStore.delete(forKey: kind.keychainKey)
        }
    }

    /// Invalidates any in-flight refresh before deleting its credential, so a
    /// late replacement token cannot be persisted after sign-out.
    static func clearRefreshToken(for kind: TokenKind) async throws {
        if kind == .playback {
            let coordinator = coordinator(for: kind)
            await coordinator.invalidateRefreshes()
            return try await withPlaybackRefreshLock {
                try await coordinator.deleteCredential()
            }
        }
        try await coordinator(for: kind).clear()
    }

    /// Refreshes the access token of the given kind (no browser).
    static func refreshAccessToken(for kind: TokenKind) async throws -> Token {
        let request: @Sendable (String) async throws -> Token = { refreshToken in
            try await requestRefreshAccessToken(for: kind, refreshToken: refreshToken)
        }
        do {
            return try await coordinator(for: kind).refresh(request: request)
        } catch {
            guard case AuthError.refreshTokenRevoked = error else { throw error }
            var cleanupError: String?
            do {
                try await clearRefreshToken(for: kind)
            } catch {
                cleanupError = error.localizedDescription
            }
            throw AuthError.refreshTokenRevoked(cleanupError: cleanupError)
        }
    }

    private static func requestRefreshAccessToken(
        for kind: TokenKind,
        refreshToken: String
    ) async throws -> Token {
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
                // The coordinator owns cleanup so refresh and sign-out share
                // one serialized persistence boundary.
                throw AuthError.refreshTokenRevoked(cleanupError: nil)
            }
            throw AuthError.refreshFailed(body)
        }
        return try decodeToken(data)
    }

    // MARK: - Interactive flow (two chained authorizations, one browser tab)

    /// Runs both flows in one browser journey. Publishes the Web token as soon
    /// as it is safely persisted; playback authorization remains independent.
    static func signIn(
        onWebToken: @escaping @MainActor (Token) -> Void
    ) async throws -> Token {
        try Task.checkCancellation()
        let signInID = beginInteractiveSignIn()
        let webRevision = await webTokenCoordinator.beginInteractiveSession()
        let playbackRevision = await playbackTokenCoordinator.beginInteractiveSession()
        let webFlow = Flow(kind: .web)
        let playbackFlow = Flow(kind: .playback)

        let waiter = try LoopbackWaiter(port: SpotifyConfig.loopbackPort, flows: [webFlow, playbackFlow])
        return try await withTaskCancellationHandler {
            defer { waiter.cancel() }

            NSWorkspace.shared.open(URL(string: webFlow.authorizeURL)!)

            let webCallback = try await waiter.waitForCallback(at: 0)
            let webToken = try await exchange(webCallback, flow: webFlow)
            guard acceptsInteractiveSignIn(signInID) else { throw CancellationError() }
            try await deletePlaybackRefreshToken(expectedRevision: playbackRevision)
            try await installRefreshToken(
                webToken.refreshToken,
                for: .web,
                expectedRevision: webRevision
            )
            await onWebToken(webToken)

            let playbackCallback = try await waiter.waitForCallback(at: 1)
            let playbackToken = try await exchange(playbackCallback, flow: playbackFlow)
            guard acceptsInteractiveSignIn(signInID) else { throw CancellationError() }
            try await installRefreshToken(
                playbackToken.refreshToken,
                for: .playback,
                expectedRevision: playbackRevision
            )
            return playbackToken
        } onCancel: {
            waiter.cancel()
        }
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
        return try decodeToken(data)
    }

    // MARK: - Helpers

    private static func decodeToken(_ data: Data) throws -> Token {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return Token(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(r.expires_in))
        )
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func coordinator(for kind: TokenKind) -> TokenCoordinator {
        switch kind {
        case .web: webTokenCoordinator
        case .playback: playbackTokenCoordinator
        }
    }

    private static func installRefreshToken(
        _ token: String?,
        for kind: TokenKind,
        expectedRevision: UInt64
    ) async throws {
        if kind == .playback {
            return try await withPlaybackRefreshLock {
                try await coordinator(for: kind).install(
                    token,
                    expectedRevision: expectedRevision
                )
            }
        }
        try await coordinator(for: kind).install(
            token,
            expectedRevision: expectedRevision
        )
    }

    private static func deletePlaybackRefreshToken(
        expectedRevision: UInt64
    ) async throws {
        try await withPlaybackRefreshLock {
            try await playbackTokenCoordinator.deleteCredential(
                expectedRevision: expectedRevision
            )
        }
    }

    /// Serializes playback credential access across GUI and headless-probe
    /// Nanyin processes so a rotating replacement is persisted exactly once.
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
    private var continuation: CheckedContinuation<Callback, Error>?
    private var waitingIndex: Int?
    private var terminalError: Error?
    private var started = false
    private let queue = DispatchQueue(label: "com.nanyin.auth.loopback")

    init(port: UInt16, flows: [SpotifyAuth.Flow]) throws {
        self.flows = flows
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    func waitForCallback(at index: Int) async throws -> Callback {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                if let terminalError {
                    cont.resume(throwing: terminalError)
                    return
                }
                if index < received.count {
                    cont.resume(returning: received[index])
                    return
                }
                guard index == received.count, continuation == nil else {
                    cont.resume(throwing: SpotifyAuth.AuthError.loopbackListenerFailed(
                        "unexpected callback order"
                    ))
                    return
                }

                continuation = cont
                waitingIndex = index
                guard !started else { return }
                started = true
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
                    guard let self, self.terminalError == nil,
                          self.received.count < self.flows.count else { return }
                    self.fail(SpotifyAuth.AuthError.userCancelled)
                }
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.received.count < self.flows.count, self.terminalError == nil {
                self.fail(CancellationError())
            } else {
                self.listener.cancel()
            }
        }
    }

    private func fail(_ error: Error) {
        terminalError = error
        continuation?.resume(throwing: error)
        continuation = nil
        waitingIndex = nil
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
        guard received.count < flows.count else {
            connection.cancel()
            return
        }
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
            let callbackIndex = received.count
            received.append(callback)
            if waitingIndex == callbackIndex {
                continuation?.resume(returning: callback)
                continuation = nil
                waitingIndex = nil
            }
        } else if callback.code == nil {
            // Error callback (user denied) — fail the flow.
            fail(SpotifyAuth.AuthError.noAuthorizationCode)
        }
    }
}
