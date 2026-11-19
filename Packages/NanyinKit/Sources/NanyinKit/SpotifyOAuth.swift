import AppKit
import Foundation

/// One of the two independent Spotify authorizations Nanyin holds.
///
/// - `webAPI`: the listener's own registered app (Client ID from the
///   developer dashboard). Carries library, catalogue and search. Spotify's
///   shared client IDs no longer admit new sign-ins and the desktop client ID
///   is answered "too many requests" on the Web API, so a personal app is the
///   only sustainable quota.
/// - `playback`: Spotify's keymaster client with the `streaming` scope only,
///   which librespot needs. Its token is used once, to obtain librespot's
///   reusable credential; it is never refreshed and never used on the Web API.
public struct OAuthGrant: Sendable, Equatable {
    public let clientID: String
    public let port: UInt16
    public let scopes: [String]
    /// Always show Spotify's consent page, so the user sees which account
    /// the grant is for.
    public let showDialog: Bool

    public static let redirectPath = "/login"
    public static let playbackClientID = "65b708073fc0480ea92a077233ca87bd"

    public var redirectURI: String { "http://127.0.0.1:\(port)\(Self.redirectPath)" }

    public static func webAPI(clientID: String) -> OAuthGrant {
        OAuthGrant(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            port: 8989,
            scopes: [
                "playlist-modify-private",
                "playlist-modify-public",
                "playlist-read-collaborative",
                "playlist-read-private",
                "user-follow-modify",
                "user-follow-read",
                "user-library-modify",
                "user-library-read",
                "user-read-private",
                "user-read-recently-played",
                "user-top-read",
            ],
            showDialog: false
        )
    }

    public static let playback = OAuthGrant(
        clientID: playbackClientID,
        port: 8898,
        scopes: ["streaming"],
        showDialog: true
    )

    /// Client IDs are 32 hexadecimal digits.
    public static func looksLikeClientID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.allSatisfy(\.isHexDigit)
    }

    func authorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ] + (showDialog ? [URLQueryItem(name: "show_dialog", value: "true")] : [])
        return components.url!
    }
}

/// An access token and the refresh token that renews it.
public struct OAuthToken: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var scope: String
    public var clientID: String

    /// Renew a little before Spotify would refuse it.
    public func isFresh(now: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(now) > 90
    }
}

public enum OAuthError: Error, Equatable, LocalizedError {
    /// The user declined in the browser, or Spotify refused the request.
    case denied(String)
    case stateMismatch
    /// Spotify rejected the refresh token: a new browser approval is needed.
    case grantRevoked
    case unknownClient
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .denied(let reason): "Spotify did not authorize Nanyin (\(reason))."
        case .stateMismatch: "The sign-in response did not match this request."
        case .grantRevoked: "Spotify no longer accepts the saved sign-in. Sign in again."
        case .unknownClient: "Spotify does not recognise this Client ID."
        case .http(let status, let message): "Spotify answered \(status): \(message)"
        }
    }
}

/// Spotify's accounts service: the PKCE authorization-code flow.
public struct SpotifyOAuth: Sendable {
    let session: URLSession
    let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Runs the browser journey for `grant`. `open` is called with the
    /// authorize URL once the loopback port is listening; it must only ever
    /// be reached from an explicit user action.
    public func authorize(
        _ grant: OAuthGrant,
        open: @Sendable (URL) async -> Void
    ) async throws -> OAuthToken {
        let pkce = PKCE()
        let receiver = try await LoopbackReceiver.start(port: grant.port, path: OAuthGrant.redirectPath)
        defer { receiver.cancel() }
        await open(grant.authorizeURL(pkce: pkce))
        let items = try await receiver.callback()
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") { throw OAuthError.denied(error) }
        guard value("state") == pkce.state else { throw OAuthError.stateMismatch }
        guard let code = value("code") else { throw OAuthError.denied("no code") }
        return try await requestToken(clientID: grant.clientID, previousRefresh: nil, form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": grant.redirectURI,
            "client_id": grant.clientID,
            "code_verifier": pkce.verifier,
        ])
    }

    /// `authorize` in the default browser. A cancelled wait surfaces as
    /// `CancellationError`, so callers only handle real failures.
    public func authorizeInBrowser(_ grant: OAuthGrant) async throws -> OAuthToken {
        do {
            return try await authorize(grant) { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
        } catch LoopbackReceiver.Failure.cancelled {
            throw CancellationError()
        }
    }

    /// Renews `token`. Spotify may return a replacement refresh token, after
    /// which the old one stops working: callers must persist the result
    /// before using it.
    public func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else { throw OAuthError.grantRevoked }
        return try await requestToken(clientID: token.clientID, previousRefresh: refreshToken, form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": token.clientID,
        ])
    }

    /// Whether Spotify knows `clientID`, asked with a code that cannot be
    /// valid: an unknown client is refused as such, a known one for the code.
    /// `nil` when the answer says neither.
    public func clientIsKnown(_ clientID: String) async -> Bool? {
        do {
            _ = try await requestToken(clientID: clientID, previousRefresh: nil, form: [
                "grant_type": "authorization_code",
                "code": "nanyin-probe",
                "redirect_uri": OAuthGrant.webAPI(clientID: clientID).redirectURI,
                "client_id": clientID,
                "code_verifier": PKCE().verifier,
            ])
            return true
        } catch OAuthError.unknownClient {
            return false
        } catch OAuthError.grantRevoked {
            return true
        } catch {
            return nil
        }
    }

    private func requestToken(
        clientID: String,
        previousRefresh: String?,
        form: [String: String]
    ) async throws -> OAuthToken {
        var request = URLRequest(url: tokenURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Self.error(status: status, body: data)
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthToken(
            accessToken: body.access_token,
            refreshToken: body.refresh_token ?? previousRefresh,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(body.expires_in)),
            scope: body.scope ?? "",
            clientID: clientID
        )
    }

    static func error(status: Int, body: Data) -> OAuthError {
        let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: body)
        switch decoded?.error {
        case "invalid_client": return .unknownClient
        case "invalid_grant": return .grantRevoked
        default:
            return .http(status, decoded?.error_description ?? decoded?.error ?? "")
        }
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let scope: String?
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let error_description: String?
    }
}
