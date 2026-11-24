import Foundation
import Testing
@testable import NanyinKit

/// Answers requests from a per-test handler, keyed by a header the session
/// adds, so parallel tests do not see each other's traffic.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, [String: String], Data)
    nonisolated(unsafe) static var handlers: [String: Handler] = [:]
    static let lock = NSLock()

    static func session(_ handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Stub": id]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub") ?? ""
        let handler = Self.lock.withLock { Self.handlers[id] }!
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class MemoryCooldown: CooldownStore, @unchecked Sendable {
    var saved: Date?
    func load() -> Date? { saved }
    func save(_ until: Date?) { saved = until }
}

struct SpotifyWebAPITests {
    private func signedIn(refresher: @escaping @Sendable (OAuthToken) async throws -> OAuthToken = { _ in throw OAuthError.grantRevoked }) async throws -> WebAPIAuth {
        let auth = WebAPIAuth(store: MemorySecretStore(), refresher: refresher)
        try await auth.signIn(with: OAuthToken(accessToken: "a1", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: "c"))
        return auth
    }

    @Test func rateLimitHoldsEveryRequestAndPersists() async throws {
        let calls = Counter()
        let session = StubProtocol.session { _ in
            calls.increment()
            return (429, ["Retry-After": "120"], Data())
        }
        let cooldown = MemoryCooldown()
        let api = SpotifyWebAPI(auth: try await signedIn(), session: session, cooldownStore: cooldown)
        await #expect(throws: WebAPIError.self) { try await api.send("GET", "/me") }
        await #expect(throws: WebAPIError.self) { try await api.send("GET", "/me") }
        #expect(calls.value == 1)
        let saved = try #require(cooldown.saved)
        #expect(saved.timeIntervalSinceNow > 100)

        // A new client (a relaunch) still honours the saved hold.
        let relaunched = SpotifyWebAPI(auth: try await signedIn(), session: session, cooldownStore: cooldown)
        await #expect(throws: WebAPIError.rateLimited(until: saved)) { try await relaunched.send("GET", "/me") }
        #expect(calls.value == 1)
    }

    @Test func unauthorizedRenewsOnceAndRetriesOnce() async throws {
        let session = StubProtocol.session { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer a2"
                ? (200, [:], Data(#"{"id":"u1","display_name":"U","product":"premium"}"#.utf8))
                : (401, [:], Data())
        }
        let auth = try await signedIn { _ in
            OAuthToken(accessToken: "a2", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: "c")
        }
        let api = SpotifyWebAPI(auth: auth, session: session, cooldownStore: MemoryCooldown())
        let me = try await api.get("/me", as: UserProfile.self)
        #expect(me.id == "u1" && me.isPremium)
    }

    @Test func errorsCarrySpotifysMessage() async throws {
        let session = StubProtocol.session { _ in (403, [:], Data(#"{"error":{"status":403,"message":"Forbidden"}}"#.utf8)) }
        let api = SpotifyWebAPI(auth: try await signedIn(), session: session, cooldownStore: MemoryCooldown())
        await #expect(throws: WebAPIError.http(403, "Forbidden")) { try await api.send("GET", "/me") }
    }

    @Test func buildsURLs() {
        #expect(SpotifyWebAPI.url("/me/tracks", query: ["offset": "50", "limit": "50"]).absoluteString
            == "https://api.spotify.com/v1/me/tracks?limit=50&offset=50")
    }

    @Test func decodesPlaylistItemsInBothShapes() throws {
        let json = #"{"items":[{"added_at":null,"item":{"id":"a","name":"One","uri":"spotify:track:a","duration_ms":1000,"artists":[{"name":"X"}]}},{"track":{"id":"b","name":"Two","uri":"spotify:track:b","duration_ms":2000,"artists":[]}},{"item":null}],"total":3}"#
        let page = try JSONDecoder().decode(Paging<PlaylistItem>.self, from: Data(json.utf8))
        #expect(page.items.compactMap(\.playable?.name) == ["One", "Two"])
    }

    @Test func requestsTopArtistsAndTracksWithTimeRange() async throws {
        let seen = Requests()
        let session = StubProtocol.session { request in
            seen.append(request)
            if request.url?.path.hasSuffix("/me/top/artists") == true {
                return (200, [:], Data(#"{"items":[{"id":"ar1","name":"Artist","uri":"spotify:artist:ar1"}],"total":1}"#.utf8))
            }
            return (200, [:], Data(#"{"items":[{"name":"Song","uri":"spotify:track:t1","duration_ms":180000,"artists":[{"name":"Artist"}]}],"total":1}"#.utf8))
        }
        let api = SpotifyWebAPI(auth: try await signedIn(), session: session, cooldownStore: MemoryCooldown())
        let artists = try await api.topArtists(timeRange: .mediumTerm, limit: 20)
        let tracks = try await api.topTracks(timeRange: .longTerm, limit: 100)
        #expect(artists.items.map(\.name) == ["Artist"])
        #expect(tracks.items.map(\.name) == ["Song"])
        #expect(seen.all.map { $0.url?.absoluteString } == [
            "https://api.spotify.com/v1/me/top/artists?limit=20&time_range=medium_term",
            "https://api.spotify.com/v1/me/top/tracks?limit=50&time_range=long_term",
        ])
    }

    @Test func picksBestImageIncludingUnsizedPlaylistCovers() {
        let sized = [
            SpotifyImage(url: URL(string: "https://i.scdn.co/640")!, width: 640),
            SpotifyImage(url: URL(string: "https://i.scdn.co/300")!, width: 300),
            SpotifyImage(url: URL(string: "https://i.scdn.co/60")!, width: 60),
        ]
        #expect(sized.best(minimum: 200)?.absoluteString == "https://i.scdn.co/300")
        #expect(sized.best(minimum: 700)?.absoluteString == "https://i.scdn.co/640")

        let unsized = [
            SpotifyImage(url: URL(string: "https://i.scdn.co/large")!, width: nil),
            SpotifyImage(url: URL(string: "https://i.scdn.co/small")!, width: nil),
        ]
        #expect(unsized.best(minimum: 200)?.absoluteString == "https://i.scdn.co/large")
        #expect([SpotifyImage]().best(minimum: 200) == nil)
    }

    @Test func stripsHTMLAndDecodesEntitiesInPlaylistDescription() throws {
        let json = #"{"id":"p1","name":"Mix","uri":"spotify:playlist:p1","description":"Cover: <a href=\"spotify:artist:1\">Artist</a> &amp; Friends &#x27;26 & B &amp;lt;3","owner":{"id":"u1","display_name":"Spike"}}"#
        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
        #expect(playlist.plainDescription == "Cover: Artist & Friends '26 & B &lt;3")
        #expect(playlist.ownerName == "Spike")
    }

    @Test func fetchesPlaylistImages() async throws {
        let session = StubProtocol.session { request in
            #expect(request.url?.path == "/v1/playlists/p1/images")
            return (200, [:], Data(#"[{"url":"https://mosaic.scdn.co/640/abc","width":null}]"#.utf8))
        }
        let api = SpotifyWebAPI(auth: try await signedIn(), session: session, cooldownStore: MemoryCooldown())
        let images = try await api.playlistImages("p1")
        #expect(images.best(minimum: 200)?.absoluteString == "https://mosaic.scdn.co/640/abc")
    }
}

struct PlaylistEditingTests {
    @Test func createsAndRenamesPlaylists() async throws {
        let seen = Requests()
        let session = StubProtocol.session { request in
            seen.append(request)
            if request.httpMethod == "POST" {
                return (201, [:], Data(#"{"id":"p1","name":"Mix","uri":"spotify:playlist:p1","owner":{"id":"u1"}}"#.utf8))
            }
            return (200, [:], Data())
        }
        let auth = WebAPIAuth(store: MemorySecretStore(), refresher: { _ in throw OAuthError.grantRevoked })
        try await auth.signIn(with: OAuthToken(accessToken: "a1", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: "c"))
        let api = SpotifyWebAPI(auth: auth, session: session, cooldownStore: MemoryCooldown())

        let created = try await api.createPlaylist(name: "Mix")
        #expect(created.id == "p1" && created.name == "Mix")
        try await api.renamePlaylist("p1", to: "Evening")

        let requests = seen.all
        #expect(requests.map(\.httpMethod) == ["POST", "PUT"])
        #expect(requests.map { $0.url?.path } == ["/v1/me/playlists", "/v1/playlists/p1"])
        let body = try #require(requests[1].bodyData)
        #expect(String(decoding: body, as: UTF8.self) == #"{"name":"Evening"}"#)
    }

    @Test func updatesDetailsAndRemovesItems() async throws {
        let seen = Requests()
        let session = StubProtocol.session { request in
            seen.append(request)
            return (200, [:], Data())
        }
        let auth = WebAPIAuth(store: MemorySecretStore(), refresher: { _ in throw OAuthError.grantRevoked })
        try await auth.signIn(with: OAuthToken(accessToken: "a1", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: "c"))
        let api = SpotifyWebAPI(auth: auth, session: session, cooldownStore: MemoryCooldown())

        try await api.updatePlaylist("p1", name: "Night", description: "Quiet songs")
        try await api.removeFromPlaylist("p1", uris: ["spotify:track:t1", "spotify:track:t2"])

        let requests = seen.all
        #expect(requests.map(\.httpMethod) == ["PUT", "DELETE"])
        #expect(requests.map { $0.url?.path } == ["/v1/playlists/p1", "/v1/playlists/p1/items"])
        let deleteBody = try #require(requests[1].bodyData)
        #expect(String(decoding: deleteBody, as: UTF8.self) == #"{"items":[{"uri":"spotify:track:t1"},{"uri":"spotify:track:t2"}]}"#)
    }
}

final class Requests: @unchecked Sendable {
    private var requests: [URLRequest] = []
    private let lock = NSLock()
    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}

private extension URLRequest {
    /// URLProtocol sees the body as a stream.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
