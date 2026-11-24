import Foundation
import Network

/// How Nanyin routes its network requests (Web API, OAuth token exchange,
/// artwork, and—when an unauthenticated HTTP proxy is chosen—librespot).
public enum ProxyMode: String, CaseIterable, Codable, Sendable, Equatable {
    case system
    case off
    case http
    case socks5

    public var label: String {
        switch self {
        case .system: "System"
        case .off: "Off"
        case .http: "HTTP"
        case .socks5: "SOCKS5"
        }
    }

    public var isManual: Bool {
        self == .http || self == .socks5
    }
}

/// Persisted proxy preferences. The password is kept separately in Keychain
/// (`SecretStore`) and never serialized here.
public struct ProxySettings: Codable, Sendable, Equatable {
    public var mode: ProxyMode
    public var host: String
    public var port: String
    public var username: String

    public init(
        mode: ProxyMode = .system,
        host: String = "",
        port: String = "",
        username: String = ""
    ) {
        self.mode = mode
        self.host = host
        self.port = port
        self.username = username
    }

    /// Validated endpoint for manual proxy modes.
    public struct Endpoint: Sendable, Equatable {
        public let mode: ProxyMode
        public let host: String
        public let port: UInt16
        public let username: String?
        public let password: String?

        /// URL for librespot, which supports HTTP proxies without credentials.
        public var playbackProxyURL: String? {
            guard mode == .http, username == nil, password == nil else { return nil }
            let formattedHost = IPv6Address(host) != nil ? "[\(host)]" : host
            return "http://\(formattedHost):\(port)"
        }
    }

    /// Validates the settings and returns a manual endpoint if `mode.isManual`.
    public func validatedEndpoint(password: String = "") throws -> Endpoint? {
        guard mode.isManual else { return nil }
        let cleanHost = Self.normalizeHost(host)
        guard !cleanHost.isEmpty else {
            throw ProxyError.invalidHost("Enter a proxy host, such as 127.0.0.1.")
        }
        guard !cleanHost.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" || $0 == "?" || $0 == "#" }) else {
            throw ProxyError.invalidHost("Enter only the proxy host name or IP address, without http:// or a path.")
        }
        if cleanHost.contains(":"), IPv6Address(cleanHost) == nil {
            throw ProxyError.invalidHost("Enter the proxy host and port in separate fields.")
        }
        let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portNumber = UInt16(cleanPort), portNumber > 0 else {
            throw ProxyError.invalidPort("Enter a valid port number between 1 and 65535.")
        }
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUser = !cleanUser.isEmpty
        let hasPassword = !password.isEmpty
        if hasPassword && !hasUser {
            throw ProxyError.missingUsername("Enter a proxy username when a password is set.")
        }
        return Endpoint(
            mode: mode,
            host: cleanHost,
            port: portNumber,
            username: hasUser ? cleanUser : nil,
            password: hasPassword ? password : nil
        )
    }

    /// HTTP proxy URL for librespot, when applicable and valid.
    public func playbackProxyURL(password: String = "") -> String? {
        guard let endpoint = try? validatedEndpoint(password: password) else { return nil }
        return endpoint.playbackProxyURL
    }

    /// Strips accidental surrounding brackets on IPv6 literals and whitespace.
    private static func normalizeHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), value.hasSuffix("]"), value.count > 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Builds a `URLSession` honouring these proxy settings.
    public func makeURLSession(password: String = "") throws -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache.shared
        switch mode {
        case .system:
            break
        case .off:
            // Disable system proxy lookup explicitly.
            config.connectionProxyDictionary = [
                "HTTPEnable": 0,
                "HTTPSEnable": 0,
                "SOCKSEnable": 0,
                "ProxyAutoConfigEnable": 0,
                "ProxyAutoDiscoveryEnable": 0,
            ]
        case .http, .socks5:
            guard let endpoint = try validatedEndpoint(password: password) else {
                throw ProxyError.invalidHost("Enter a proxy host.")
            }
            guard let nwPort = NWEndpoint.Port(rawValue: endpoint.port) else {
                throw ProxyError.invalidPort("Enter a valid port number between 1 and 65535.")
            }
            let nwEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(endpoint.host), port: nwPort)
            let proxy: ProxyConfiguration = mode == .http
                ? ProxyConfiguration(httpCONNECTProxy: nwEndpoint)
                : ProxyConfiguration(socksv5Proxy: nwEndpoint)
            if let user = endpoint.username {
                proxy.applyCredential(username: user, password: endpoint.password ?? "")
            }
            config.proxyConfigurations = [proxy]
        }
        return URLSession(configuration: config)
    }
}

public enum ProxyError: Error, Equatable, LocalizedError {
    case invalidHost(String)
    case invalidPort(String)
    case missingUsername(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let message),
             .invalidPort(let message),
             .missingUsername(let message):
            message
        }
    }
}

/// Shared, replaceable HTTP transport. Updating the proxy replaces the
/// underlying `URLSession` for OAuth, the Web API, and artwork without a
/// restart. An invalid proxy blocks requests rather than silently bypassing
/// the configured proxy.
public final class HTTPTransport: @unchecked Sendable {
    public static let shared = HTTPTransport(session: .shared)

    private let lock = NSLock()
    private var state: Result<URLSession, ProxyError>
    private var ownsSession: Bool

    public init(session: URLSession = .shared) {
        self.state = .success(session)
        self.ownsSession = false
    }

    public func currentSession() throws -> URLSession {
        try lock.withLock { try state.get() }
    }

    /// Rebuilds the `URLSession` from `settings`.
    ///
    /// By default (`blockOnFailure == false`), a rejected manual draft leaves
    /// the existing working session intact and throws so the UI can report the
    /// validation error. At startup (`blockOnFailure == true`), an invalid saved
    /// configuration blocks requests rather than silently bypassing the proxy.
    public func apply(
        _ settings: ProxySettings,
        password: String = "",
        blockOnFailure: Bool = false
    ) throws {
        do {
            let session = try settings.makeURLSession(password: password)
            let previous: URLSession? = lock.withLock {
                let old = ownsSession ? (try? state.get()) : nil
                state = .success(session)
                ownsSession = true
                return old
            }
            previous?.finishTasksAndInvalidate()
        } catch let error as ProxyError {
            if blockOnFailure {
                let previous: URLSession? = lock.withLock {
                    let old = ownsSession ? (try? state.get()) : nil
                    state = .failure(error)
                    ownsSession = false
                    return old
                }
                previous?.finishTasksAndInvalidate()
            }
            throw error
        }
    }
}
