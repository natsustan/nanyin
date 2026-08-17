//
//  SpotifyAuth.swift
//  Nanyin
//

import AppKit
import CryptoKit
import Foundation
import Network

/// Spotify OAuth (Authorization Code + PKCE) against a local loopback redirect.
/// Single flow with the keymaster client: the resulting token works for both
/// the Web API and librespot playback (same strategy as cliamp).
enum SpotifyAuth {
    struct Token: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date // derived: now + expires_in
    }

    enum AuthError: Error, LocalizedError {
        case loopbackListenerFailed(String)
        case noAuthorizationCode
        case tokenExchangeFailed(String)
        case userCancelled
        case refreshFailed(String)

        var errorDescription: String? {
            switch self {
            case let .loopbackListenerFailed(msg): "Loopback listener failed: \(msg)"
            case .noAuthorizationCode: "No authorization code received"
            case let .tokenExchangeFailed(msg): "Token exchange failed: \(msg)"
            case .userCancelled: "Sign-in cancelled"
            case let .refreshFailed(msg): "Token refresh failed: \(msg)"
            }
        }
    }

    // MARK: - Token persistence (refresh token in Keychain)

    static var storedRefreshToken: String? {
        get { KeychainStore.string(forKey: "refresh_token") }
        set {
            if let newValue {
                KeychainStore.setString(newValue, forKey: "refresh_token")
            } else {
                KeychainStore.delete(forKey: "refresh_token")
            }
        }
    }

    /// Refreshes the access token with the stored refresh token (no browser).
    static func refreshAccessToken() async throws -> Token {
        guard let refreshToken = storedRefreshToken else {
            throw AuthError.refreshFailed("no stored refresh token")
        }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SpotifyConfig.clientId,
        ]
        .map { "\($0)=\(escape($1))" }
        .joined(separator: "&")
        req.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.refreshFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }
        return try decodeToken(data)
    }

    // MARK: - Interactive flow

    /// Runs the full PKCE flow: opens the browser, listens on the loopback
    /// redirect, exchanges the code. Returns the token.
    static func signIn() async throws -> Token {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()

        // 1. Start the loopback listener before opening the browser.
        let waiter = try LoopbackWaiter(port: SpotifyConfig.loopbackPort)

        // 2. Build the authorize URL and open it.
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: SpotifyConfig.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: SpotifyConfig.redirectUri),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "scope", value: SpotifyConfig.scopes.joined(separator: " ")),
        ]
        guard let url = components.url else {
            throw AuthError.loopbackListenerFailed("bad authorize URL")
        }
        NSWorkspace.shared.open(url)

        // 3. Wait for the callback (browser hits 127.0.0.1:19873/login).
        let callback = try await waiter.waitForCallback()

        guard callback.state == state else {
            throw AuthError.loopbackListenerFailed("state mismatch")
        }
        guard let code = callback.code else {
            throw AuthError.noAuthorizationCode
        }

        // 4. Exchange the code for tokens.
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectUri,
            "client_id": SpotifyConfig.clientId,
            "code_verifier": verifier,
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
        let expiresAt = Date().addingTimeInterval(TimeInterval(r.expires_in))
        if let refresh = r.refresh_token {
            storedRefreshToken = refresh
        }
        return Token(accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: expiresAt)
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

// MARK: - Loopback listener

/// Listens on 127.0.0.1:port, accepts a single /login callback, replies with a
/// small success page, then stops.
private final class LoopbackWaiter {
    struct Callback {
        let code: String?
        let state: String?
    }

    private let listener: NWListener
    private var continuation: CheckedContinuation<Callback, Error>?

    init(port: UInt16) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.continuation?.resume(throwing: SpotifyAuth.AuthError.loopbackListenerFailed(error.localizedDescription))
                    self?.continuation = nil
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self, error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first
            else {
                connection.cancel()
                return
            }

            // "GET /login?code=...&state=... HTTP/1.1"
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }
            let path = String(parts[1])

            // Respond with a minimal success page.
            let body = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>nanyin</title></head>
            <body style="font-family:system-ui;background:#121212;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;margin:0">
            <h2>✅ Signed in to nanyin</h2>
            <script>setTimeout(function(){window.close()},1500)</script>
            </body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
                self.listener.cancel()
            })

            // Parse query params.
            guard let queryStart = path.firstIndex(of: "?") else { return }
            let query = String(path[path.index(after: queryStart)...])
            var params: [String: String] = [:]
            for pair in query.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    params[String(kv[0]).removingPercentEncoding ?? String(kv[0])] =
                        String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }

            if let cont = continuation {
                continuation = nil
                cont.resume(returning: Callback(code: params["code"], state: params["state"]))
            }
        }
    }
}
