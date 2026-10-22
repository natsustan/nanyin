import Foundation

/// Real client requests, intercepted before any network or credential access.
private final class PlaylistFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pages: [String] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    nonisolated(unsafe) private static var holdResponse = false

    static func reset(_ replies: [String], holdResponse: Bool = false) {
        lock.withLock { pages = replies; seen = []; self.holdResponse = holdResponse }
    }
    static var requests: [URLRequest] { lock.withLock { seen } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.lock.withLock {
            Self.seen.append(request)
            precondition(!Self.pages.isEmpty, "Unexpected extra playlist request")
            return Self.pages.removeFirst()
        }
        // A held request can only finish through client cancellation.
        if Self.lock.withLock({ Self.holdResponse }) { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private enum PlaylistReadTests {
    private static func track(_ id: String, extra: String = "") -> String {
        """
        {"id":"\(id)","uri":"spotify:track:\(id)","name":"Song \(id)"\(extra)}
        """
    }

    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaylistFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = SpotifyClient(accessToken: "synthetic-web-token",
            transport: SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil)))

        // Modern and legacy shapes, duplicate songs, nulls, local files,
        // unavailable songs and episodes must not shift the selected offset.
        PlaylistFixture.reset([
            """
            {"offset":0,"total":100,"next":"https://api.spotify.com/v1/playlists/p/items?offset=8",
             "items":[null,{"item":null},{"item":\(track("A"))},
               {"track":\(track("B"))}, {"item":\(track("C", extra: ",\"is_playable\":false"))},
               {"is_local":true,"item":\(track("local"))},
               {"item":{"id":"ep","uri":"spotify:episode:ep","name":"Podcast"}},
               {"item":\(track("A"))}]}
            """,
            """
            {"offset":8,"total":100,"next":null,"items":[
              {"item":\(track("D")),"track":\(track("old"))},
              {"item":null,"track":\(track("E"))}]}
            """
        ])
        let tracks = try await client.playlistTracks("p")
        assert(tracks.map(\.id) == ["A", "B", "A", "D", "E"])
        assert(tracks.map { $0.contextPosition?.index } == [2, 3, 7, 8, 9])
        assert(tracks.allSatisfy { $0.contextPosition?.source == "spotify:playlist:p" })
        assert(PlaylistFixture.requests.count == 2, "next=null wins over an outdated total")
        let queries = PlaylistFixture.requests.map {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!
        }
        assert(queries[1].first { $0.name == "offset" }?.value == "8")
        assert(PlaylistFixture.requests.allSatisfy {
            $0.url?.path == "/v1/playlists/p/items" &&
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-web-token"
        })

        // A fully filtered first page is not the end of the playlist.
        PlaylistFixture.reset([
            """
            {"offset":0,"next":"next","items":[null,{"item":null}]}
            """,
            """
            {"offset":2,"next":null,"items":[{"item":\(track("F"))}]}
            """
        ])
        let filtered = try await client.playlistTracks("filtered")
        assert(filtered.count == 1 && filtered[0].contextPosition?.index == 2)

        // Albums often embed fewer than 50 rows. Do not skip the middle of
        // an album, and keep original positions through metadata enrichment.
        PlaylistFixture.reset([
            """
            {"id":"album","name":"Album","tracks":{"offset":0,"total":4,
              "next":"next","items":[\(track("A")),null,\(track("B"))]}}
            """,
            """
            {"offset":3,"total":4,"next":null,"items":[\(track("C"))]}
            """
        ])
        let album = try await client.albumTracks("album")
        assert(album.map(\.id) == ["A", "B", "C"])
        assert(album.map { $0.contextPosition?.index } == [0, 2, 3])
        assert(album.allSatisfy {
            $0.contextPosition?.source == "spotify:album:album" && $0.albumName == "Album"
        })
        let albumNext = URLComponents(url: PlaylistFixture.requests[1].url!,
            resolvingAgainstBaseURL: false)!.queryItems!
        assert(albumNext.first { $0.name == "offset" }?.value == "3")

        // Liked Songs continues from raw slots, not visible songs or pageSize.
        PlaylistFixture.reset([
            """
            {"offset":0,"total":5,"next":"next","items":[null,
              {"track":\(track("L"))},{"track":null}]}
            """,
            """
            {"offset":3,"total":5,"next":null,"items":[
              {"track":\(track("M"))},{"track":\(track("N"))}]}
            """
        ])
        let likedPrefix = try await client.likedTracksPrefix()
        assert(likedPrefix.rawCount == 3 && likedPrefix.nextOffset == 3)
        let liked = try await client.likedTracks(after: likedPrefix)
        assert(liked.map(\.id) == ["L", "M", "N"])
        assert(liked.map { $0.contextPosition?.index } == [1, 3, 4])
        assert(liked.allSatisfy { $0.contextPosition?.source == "liked" })
        let likedNext = URLComponents(url: PlaylistFixture.requests[1].url!,
            resolvingAgainstBaseURL: false)!.queryItems!
        assert(likedNext.first { $0.name == "offset" }?.value == "3")
        assert(LikedTrackPositions.prefixMatches(cached: liked, page: likedPrefix))
        var moved = liked[0]
        moved.contextPosition = .init(source: "liked", index: 0)
        let changed = SpotifyClient.LikedTracksPage(tracks: [moved], total: 5, nextOffset: 1, rawCount: 1)
        assert(!LikedTrackPositions.prefixMatches(cached: liked, page: changed))
        let merged = LikedTrackPositions.mergePrefix(cached: liked, prefix: [moved])
        assert(merged.map(\.id) == ["L", "M", "N"])
        assert(merged[0].contextPosition?.index == 0)
        assert(merged.dropFirst().allSatisfy { $0.contextPosition == nil },
               "A fresh prefix cannot confirm cached tail positions")
        let unavailablePrefix = SpotifyClient.LikedTracksPage(tracks: [], total: 5, nextOffset: 3, rawCount: 3)
        assert(!LikedTrackPositions.prefixMatches(cached: liked, page: unavailablePrefix))
        PlaylistFixture.reset([
            """
            {"offset":3,"total":6,"next":null,"items":[{"track":\(track("O"))}]}
            """
        ])
        do {
            _ = try await client.likedTracks(after: likedPrefix)
            assertionFailure("A changing collection must not publish as a complete snapshot")
        } catch SpotifyClient.APIError.http(0, _) {}
        assert(PlaylistFixture.requests.count == 1)

        // Library null slots and both count field names, no redundant tail reads.
        PlaylistFixture.reset([
            """
            {"offset":0,"total":3,"next":"next","items":[null,
              {"id":"p","name":"Modern","items":{"total":10},"tracks":{"total":1}}]}
            """,
            """
            {"offset":2,"total":500,"next":null,"items":[
              {"id":"q","name":"Classic","tracks":{"total":4}}]}
            """
        ])
        let playlists = try await client.playlists()
        assert(playlists.map(\.id) == ["p", "q"])
        assert(playlists.map(\.trackCount) == [10, 4])
        assert(PlaylistFixture.requests.count == 2)

        for body in [
            "{\"offset\":0,\"next\":\"next\",\"items\":[]}",
            "{\"offset\":50,\"next\":null,\"items\":[]}"
        ] {
            PlaylistFixture.reset([body])
            do {
                _ = try await client.playlistTracks("broken")
                assertionFailure("Non-progressing/mismatched page must fail without replay")
            } catch SpotifyClient.APIError.http(0, _) {}
            assert(PlaylistFixture.requests.count == 1)
        }

        PlaylistFixture.reset(["unused"], holdResponse: true)
        let abandoned = Task { try await client.playlistTracks("abandoned") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while PlaylistFixture.requests.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        assert(PlaylistFixture.requests.count == 1)
        abandoned.cancel()
        do {
            _ = try await abandoned.value
            assertionFailure("Cancelled playlist read must not return a partial success")
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {}
        assert(PlaylistFixture.requests.count == 1, "Cancelled reads never request another page")
        try await testSessionBridge()
        print("Playlist read tests passed")
    }
    private static func testSessionBridge() async throws {
        func page(offset: Int, total: Int = 51, revision: String = "one", count: Int) throws -> Data {
            let song: [String: Any] = ["id": "song", "uri": "spotify:track:song", "name": "Song"]
            let items: [[String: Any]] = (0..<count).map { index in
                ["item": index == 0 ? song : NSNull()]
            }
            return try JSONSerialization.data(withJSONObject: ["offset": offset, "total": total,
                "snapshot_id": revision, "items": items,
                "next": offset + count < total ? "next" : NSNull()])
        }
        var offsets: [Int] = []
        let tracks = try await SpotifyClient.sessionPlaylistTracks("external") { offset in
            offsets.append(offset)
            return try page(offset: offset, count: offset == 0 ? 50 : 1)
        }
        assert(offsets == [0, 50])
        assert(tracks.map(\.id) == ["song", "song"])
        assert(tracks.map { $0.contextPosition?.index } == [0, 50])
        assert(tracks.allSatisfy { $0.contextPosition?.source == "spotify:playlist:external" })
        // An all-unavailable page still consumes raw slots; no fabricated song.
        let empty = try JSONSerialization.data(withJSONObject: ["offset": 0, "total": 2,
            "snapshot_id": "one", "items": [["item": NSNull()], ["item": NSNull()]], "next": NSNull()])
        let unavailable = try await SpotifyClient.sessionPlaylistTracks("external") { _ in empty }
        assert(unavailable.isEmpty)
        for code in ["rate_limited", "forbidden", "not_found", "account_mismatch", "unavailable", "cancelled"] {
            var calls = 0
            do {
                _ = try await SpotifyClient.sessionPlaylistTracks("external") { _ in
                    calls += 1
                    return try JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": "fixture"]])
                }
                assertionFailure("A failed session read must not become an empty playlist")
            } catch is CancellationError {
                assert(code == "cancelled")
            } catch let error as SpotifyClient.SessionLibraryError {
                assert(error.code == code)
            }
            assert(calls == 1, "No automatic replay or Web OAuth retry")
        }
        for change in ["revision", "total", "truncated"] {
            var calls = 0
            do {
                _ = try await SpotifyClient.sessionPlaylistTracks("external") { offset in
                    calls += 1
                    if offset == 0 { return try page(offset: 0, count: 50) }
                    return try page(offset: 50, total: change == "total" ? 52 : 51,
                        revision: change == "revision" ? "two" : "one", count: change == "truncated" ? 0 : 1)
                }
                assertionFailure("A mixed or truncated snapshot must not be published")
            } catch is SpotifyClient.SessionLibraryError {}
            assert(calls == 2)
        }
    }

}
