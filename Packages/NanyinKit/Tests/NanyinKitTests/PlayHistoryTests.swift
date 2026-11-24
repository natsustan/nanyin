import Foundation
import Testing
@testable import NanyinKit

struct PlayHistoryTests {
    private func play(_ uri: String, at: String, durationMs: Int = 200_000) -> PlayHistory {
        PlayHistory(
            track: Track(name: uri, uri: uri, duration_ms: durationMs, artists: [ArtistRef(name: "Artist")]),
            played_at: at
        )
    }

    @Test func countsAfterThreshold() {
        #expect(PlayHistoryMerger.countsAfter(durationMs: 240_000) == 30)
        #expect(PlayHistoryMerger.countsAfter(durationMs: 40_000) == 20)
        #expect(PlayHistoryMerger.countsAfter(durationMs: 0) == 1)
    }

    @Test func interleavesLocalAndRemoteNewestFirst() {
        let local = [
            play("spotify:track:late", at: "2026-11-24T15:00:00Z"),
            play("spotify:track:early", at: "2026-11-24T09:00:00Z"),
        ]
        let remote = [
            play("spotify:track:phone", at: "2026-11-24T12:00:00.456Z"),
        ]
        let merged = PlayHistoryMerger.merge(local: local, remote: remote)
        #expect(merged.map(\.track.uri) == [
            "spotify:track:late",
            "spotify:track:phone",
            "spotify:track:early",
        ])
    }

    @Test func deduplicatesSamePlayWhenSpotifyDatesAtEnd() {
        let local = [
            play("spotify:track:a", at: "2026-11-24T01:03:50Z", durationMs: 200_000),
            play("spotify:track:a", at: "2026-11-24T01:00:30Z", durationMs: 200_000),
        ]
        let remote = [
            play("spotify:track:a", at: "2026-11-24T01:06:40Z", durationMs: 200_000),
            play("spotify:track:a", at: "2026-11-24T01:03:20Z", durationMs: 200_000),
        ]
        #expect(PlayHistoryMerger.merge(local: local, remote: remote).count == 2)

        let later = [play("spotify:track:a", at: "2026-11-24T01:15:00Z", durationMs: 200_000)]
        #expect(PlayHistoryMerger.merge(local: [local[1]], remote: later).count == 2)
    }

    @Test func preservesSeparatePlaysFromOneSource() {
        let local = [
            play("spotify:track:short", at: "2026-11-24T15:00:40Z", durationMs: 40_000),
            play("spotify:track:short", at: "2026-11-24T15:00:00Z", durationMs: 40_000),
        ]
        #expect(PlayHistoryMerger.merge(local: local, remote: []).count == 2)
        #expect(PlayHistoryMerger.merge(local: [], remote: local).count == 2)
    }

    @Test @MainActor func storePersistsAndCapsEntriesWithPrivatePermissions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "nanyin-history-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PlayHistoryStore(directory: dir)
        store.load(for: "alice/user")
        let base = Date(timeIntervalSince1970: 1_795_000_000)
        for index in 0 ..< PlayHistoryStore.maxEntries + 5 {
            let track = Track(
                name: "Song \(index)",
                uri: "spotify:track:\(index)",
                duration_ms: 180_000,
                artists: [ArtistRef(name: "Artist")]
            )
            store.record(track, at: base.addingTimeInterval(Double(index)))
        }
        #expect(store.plays.count == PlayHistoryStore.maxEntries)
        #expect(store.plays.first?.track.uri == "spotify:track:\(PlayHistoryStore.maxEntries + 4)")

        let reloaded = PlayHistoryStore(directory: dir)
        reloaded.load(for: "alice/user")
        #expect(reloaded.plays.count == PlayHistoryStore.maxEntries)
        #expect(reloaded.plays.first?.track.uri == store.plays.first?.track.uri)

        let file = dir.appending(path: PlayHistoryStore.filename(for: "alice/user"))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        let perms = (attrs[.posixPermissions] as? Int ?? 0) & 0o777
        #expect(perms == 0o600)

        reloaded.unload()
        reloaded.record(Track(name: "Ignored", uri: "spotify:track:ignored", duration_ms: 180_000, artists: []))
        #expect(reloaded.plays.isEmpty)
    }

    @Test @MainActor func storeIsolatesAccountsDifferingOnlyInPunctuation() {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "nanyin-history-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PlayHistoryStore(directory: dir)
        store.load(for: "alice-bob")
        store.record(Track(name: "A", uri: "spotify:track:a", duration_ms: 180_000, artists: []))

        store.load(for: "alice_bob")
        #expect(store.plays.isEmpty)
        store.record(Track(name: "B", uri: "spotify:track:b", duration_ms: 180_000, artists: []))

        store.load(for: "alice-bob")
        #expect(store.plays.map(\.track.uri) == ["spotify:track:a"])
        store.load(for: "alice_bob")
        #expect(store.plays.map(\.track.uri) == ["spotify:track:b"])
    }
}
