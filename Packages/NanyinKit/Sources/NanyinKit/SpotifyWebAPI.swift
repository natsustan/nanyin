import Foundation

public enum WebAPIError: Error, Equatable, LocalizedError {
    /// Spotify asked to wait. Nothing is sent before `until`.
    case rateLimited(until: Date)
    case signedOut
    case http(Int, String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .rateLimited(let until):
            "Spotify asked Nanyin to slow down. Try again \(until.formatted(.relative(presentation: .named)))."
        case .signedOut: "Not signed in to Spotify."
        case .http(let status, let message): "Spotify answered \(status)\(message.isEmpty ? "" : ": \(message)")."
        case .decoding(let detail): "Unexpected answer from Spotify (\(detail))."
        }
    }
}

/// Remembers a `Retry-After` hold across launches: relaunching must not be a
/// way around it.
public protocol CooldownStore: Sendable {
    func load() -> Date?
    func save(_ until: Date?)
}

public struct DefaultsCooldownStore: CooldownStore, @unchecked Sendable {
    let defaults: UserDefaults
    let key: String

    public init(defaults: UserDefaults = .standard, key: String = "WebAPICooldownUntil") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Date? { defaults.object(forKey: key) as? Date }
    public func save(_ until: Date?) { defaults.set(until, forKey: key) }
}

/// The Spotify Web API over the listener's own app.
///
/// Traffic rules: at most `maxConcurrent` requests in flight; a 429 stops
/// every request until its `Retry-After` has passed (never replayed
/// automatically); a 401 renews the token once and retries once.
public actor SpotifyWebAPI {
    public static let baseURL = URL(string: "https://api.spotify.com/v1")!
    /// Spotify sometimes sends hours. Respect it, but a value beyond a day is
    /// treated as a day so a bad header cannot lock the app forever.
    static let longestCooldown: TimeInterval = 24 * 3600

    private let auth: WebAPIAuth
    private let session: URLSession
    private let cooldownStore: any CooldownStore
    private let maxConcurrent: Int
    private var inFlight = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var cooldownUntil: Date?

    public init(
        auth: WebAPIAuth,
        session: URLSession = .shared,
        cooldownStore: any CooldownStore = DefaultsCooldownStore(),
        maxConcurrent: Int = 4
    ) {
        self.auth = auth
        self.session = session
        self.cooldownStore = cooldownStore
        self.maxConcurrent = maxConcurrent
        cooldownUntil = cooldownStore.load()
    }

    public var cooldown: Date? {
        guard let cooldownUntil, cooldownUntil > .now else { return nil }
        return cooldownUntil
    }

    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        let data = try await send("GET", path, query: query, body: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WebAPIError.decoding("\(path): \(error)")
        }
    }

    @discardableResult
    public func send(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> Data {
        var request = URLRequest(url: Self.url(path, query: query), timeoutInterval: 20)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let cooldown { throw WebAPIError.rateLimited(until: cooldown) }
        await enterSlot()
        defer { leaveSlot() }
        if let cooldown { throw WebAPIError.rateLimited(until: cooldown) }

        var token = try await accessToken()
        var (data, response) = try await perform(request, token: token)
        if response.statusCode == 401 {
            token = try await auth.tokenAfterRejection(of: token)
            (data, response) = try await perform(request, token: token)
        }
        switch response.statusCode {
        case 200 ..< 300:
            return data
        case 429:
            let until = Date.now.addingTimeInterval(Self.retryAfter(response))
            if until > (cooldownUntil ?? .distantPast) {
                cooldownUntil = until
                cooldownStore.save(until)
            }
            throw WebAPIError.rateLimited(until: until)
        default:
            throw WebAPIError.http(response.statusCode, Self.message(in: data))
        }
    }

    /// At most `maxConcurrent` requests in flight, first come first served.
    private func enterSlot() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func leaveSlot() {
        if waiting.isEmpty {
            inFlight -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    private func accessToken() async throws -> String {
        do {
            return try await auth.accessToken()
        } catch WebAPIAuth.Failure.signedOut {
            throw WebAPIError.signedOut
        }
    }

    private func perform(_ request: URLRequest, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebAPIError.http(0, "no HTTP response")
        }
        return (data, http)
    }

    static func url(_ path: String, query: [String: String]) -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval {
        let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 30
        return min(max(seconds, 1), longestCooldown)
    }

    static func message(in data: Data) -> String {
        struct Body: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error?.message ?? ""
    }
}
