//
//  FollowedArtistCache.swift
//  Nanyin
//

import Foundation

/// Pure followed-artist snapshot reconciler. AppModel owns write ordering and
/// expiry; this type keeps stale/partial cursor snapshots from overriding the
/// user's latest Follow/Unfollow intent.
struct FollowedArtistCache: Equatable {
    struct OverrideView: Equatable {
        let followed: Bool
        var countedInServerTotal: Bool
        let artist: SpotifyClient.Artist
    }

    private(set) var artists: [SpotifyClient.Artist] = []
    private(set) var confirmedIDs: Set<String> = []
    private(set) var knownIDs: Set<String> = []
    private(set) var serverTotal: Int?
    private(set) var isComplete = false

    var hasLoadedAnyData: Bool { serverTotal != nil || !artists.isEmpty }

    @discardableResult
    mutating func applyServerSnapshot(
        _ snapshot: [SpotifyClient.Artist],
        total: Int,
        complete: Bool,
        overrides: [String: OverrideView]
    ) -> Set<String> {
        let snapshot = Self.deduplicated(snapshot)
        let snapshotIDs = Set(snapshot.map(\.id))
        if complete {
            confirmedIDs = snapshotIDs
        } else {
            confirmedIDs.formUnion(snapshotIDs)
        }
        isComplete = complete
        knownIDs.formUnion(snapshotIDs)
        let canAdoptTotal = complete || overrides.allSatisfy { id, override in
            if override.followed { return snapshotIDs.contains(id) }
            return false
        }
        if canAdoptTotal {
            serverTotal = total
        }

        let confirmed = Set(overrides.compactMap { id, override in
            if override.followed { return snapshotIDs.contains(id) ? id : nil }
            return complete && !snapshotIDs.contains(id) ? id : nil
        })

        var display = complete ? snapshot : Self.merge(prefix: snapshot, cached: artists)
        for override in overrides.values {
            if override.followed {
                if let index = display.firstIndex(where: { $0.id == override.artist.id }) {
                    display[index] = override.artist
                } else {
                    display.append(override.artist)
                }
            } else {
                display.removeAll { $0.id == override.artist.id }
            }
        }
        artists = display
        return confirmed
    }

    private static func merge(
        prefix: [SpotifyClient.Artist],
        cached: [SpotifyClient.Artist]
    ) -> [SpotifyClient.Artist] {
        let prefixIDs = Set(prefix.map(\.id))
        return prefix + cached.filter { !prefixIDs.contains($0.id) }
    }

    static func rebasedOverrides(
        _ overrides: [String: OverrideView],
        snapshot: [SpotifyClient.Artist],
        complete: Bool
    ) -> [String: OverrideView] {
        let snapshotIDs = Set(snapshot.map(\.id))
        return overrides.mapValues { override in
            var override = override
            if snapshotIDs.contains(override.artist.id) {
                override.countedInServerTotal = true
            } else if complete {
                override.countedInServerTotal = false
            }
            return override
        }
    }

    static func isCompleteSnapshot(_ snapshot: [SpotifyClient.Artist], total: Int) -> Bool {
        snapshot.count == total && Set(snapshot.map(\.id)).count == snapshot.count
    }

    static func shouldRetainOverride(
        expiresAt: Date?,
        hasActiveMutation: Bool,
        refreshStartedAt: Date
    ) -> Bool {
        hasActiveMutation || expiresAt.map { $0 > refreshStartedAt } ?? true
    }

    mutating func noteProbe(_ artist: SpotifyClient.Artist, followed: Bool) {
        guard !isComplete else { return }
        knownIDs.insert(artist.id)
        if followed {
            confirmedIDs.insert(artist.id)
            insertOptimistic(artist)
        } else {
            confirmedIDs.remove(artist.id)
        }
    }

    mutating func insertOptimistic(_ artist: SpotifyClient.Artist) {
        knownIDs.insert(artist.id)
        artists.removeAll { $0.id == artist.id }
        artists.append(artist)
    }

    mutating func removeOptimistic(id: String) {
        knownIDs.insert(id)
        artists.removeAll { $0.id == id }
    }

    func followedState(
        _ id: String,
        overrides: [String: OverrideView] = [:]
    ) -> Bool? {
        if let override = overrides[id] { return override.followed }
        if isComplete { return confirmedIDs.contains(id) }
        guard knownIDs.contains(id) else { return nil }
        return confirmedIDs.contains(id)
    }

    func displayCount(overrides: [String: OverrideView]) -> Int {
        guard let serverTotal else { return artists.count }
        var count = serverTotal
        for override in overrides.values {
            if override.followed, !override.countedInServerTotal {
                count += 1
            } else if !override.followed, override.countedInServerTotal {
                count -= 1
            }
        }
        return max(0, count)
    }

    private static func deduplicated(_ artists: [SpotifyClient.Artist]) -> [SpotifyClient.Artist] {
        var seen: Set<String> = []
        return artists.filter { seen.insert($0.id).inserted }
    }
}
