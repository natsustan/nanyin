import Foundation
import Testing
@testable import NanyinKit

@Suite("LyricsStore")
struct LyricsStoreTests {
    @Test func parsesSyncedLRCAndFindsActiveLine() throws {
        let lrc = """
        [ti:Example]
        [00:05.50]First line
        [00:12.125]Second line
        [00:20.00][00:40.00]Repeated chorus
        [00:25.00]♪
        """
        let lyrics = try #require(Lyrics.parseLRC(lrc))
        #expect(lyrics.synced)
        #expect(lyrics.lines.count == 4)
        #expect(lyrics.lines.map(\.startTimeMs) == [5500, 12125, 20000, 40000])
        #expect(lyrics.lines.map(\.text) == ["First line", "Second line", "Repeated chorus", "Repeated chorus"])

        #expect(lyrics.activeLineIndex(at: 0) == nil)
        #expect(lyrics.activeLineIndex(at: 5499) == nil)
        #expect(lyrics.activeLineIndex(at: 5500) == 0)
        #expect(lyrics.activeLineIndex(at: 12124) == 0)
        #expect(lyrics.activeLineIndex(at: 12125) == 1)
        #expect(lyrics.activeLineIndex(at: 45000) == 3)
    }

    @Test func cleansEditionSuffixesForLookup() {
        #expect(LRCLIBClient.cleanTitle("Heroes (2017 Remaster)") == "Heroes")
        #expect(LRCLIBClient.cleanTitle("Dreams - Remastered 2004") == "Dreams")
        #expect(LRCLIBClient.cleanTitle("Bohemian Rhapsody [Deluxe Edition]") == "Bohemian Rhapsody")
        #expect(LRCLIBClient.cleanTitle("Time (Pink Floyd)") == "Time (Pink Floyd)")
    }

    @Test func fetchesFromLRCLIBExactAndFallsBackToSearch() async throws {
        let session = StubProtocol.session { request in
            if request.url?.path.hasSuffix("/get") == true {
                return (404, [:], Data())
            }
            let body = """
            [
              {"duration": 210.0, "plainLyrics": "Plain only"},
              {"duration": 200.5, "syncedLyrics": "[00:01.00]Matched synced"},
              {"duration": 350.0, "syncedLyrics": "[00:01.00]Wrong length"}
            ]
            """
            return (200, [:], Data(body.utf8))
        }
        let client = LRCLIBClient(session: session)
        let query = LyricsQuery(
            trackURI: "spotify:track:abc",
            title: "Song (Remastered)",
            artist: "Artist",
            album: "Album",
            durationMs: 200_000
        )
        let found = try #require(try await client.fetch(query))
        #expect(found.synced)
        #expect(found.lines.first?.text == "Matched synced")
    }

    @Test func diskCacheHonoursTTLsForHitsAndMisses() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nanyin-lyrics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = LyricsDiskCache(directory: dir, foundTTL: 100, missTTL: 20)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sample = Lyrics(lines: [LyricsLine(startTimeMs: 1000, text: "Hello")], synced: true, source: "Spotify")

        cache.save(trackURI: "spotify:track:hit", lyrics: sample, now: now)
        cache.save(trackURI: "spotify:track:miss", lyrics: nil, now: now)

        #expect(cache.load(trackURI: "spotify:track:hit", now: now.addingTimeInterval(50)) == .found(sample))
        #expect(cache.load(trackURI: "spotify:track:hit", now: now.addingTimeInterval(101)) == nil)

        #expect(cache.load(trackURI: "spotify:track:miss", now: now.addingTimeInterval(10)) == .notFound)
        #expect(cache.load(trackURI: "spotify:track:miss", now: now.addingTimeInterval(25)) == nil)

        cache.clear()
        #expect(cache.load(trackURI: "spotify:track:hit", now: now) == nil)
    }
}
