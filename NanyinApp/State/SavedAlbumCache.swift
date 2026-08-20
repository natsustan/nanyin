//
//  SavedAlbumCache.swift
//  Nanyin
//

import Foundation

/// Pure saved-albums cache: server snapshots reconciled against optimistic
/// overrides (M4.3). Latest local intent always wins — a stale or partial
/// snapshot can never resurrect a row the user just removed, nor drop one
/// they just saved. AppModel owns the per-id `MembershipMutation` state
/// machines, active-writer tracking, and override expiry policy; this type
/// only derives display state, so every rule here is deterministically
/// testable.
struct SavedAlbumCache: Equatable {
    /// The override view the cache needs: the user's desired state plus the
    /// payload to display for an album the server data doesn't include yet.
    struct OverrideView: Equatable {
        let saved: Bool
        let album: SpotifyClient.SavedAlbum
    }

    /// Display list (server order — newest saved first — with optimistic
    /// edits applied).
    private(set) var albums: [SpotifyClient.SavedAlbum] = []
    /// IDs present in the most recently fetched server data. NOT accumulated
    /// across fetches: old confirmations must not mask a newer server state.
    private(set) var confirmedIDs: Set<String> = []
    /// IDs whose saved state is known from the server (in list, or a contains
    /// probe answered for them).
    private(set) var knownIDs: Set<String> = []
    /// Last server-reported library size (never adjusted by overrides).
    private(set) var serverTotal: Int?
    /// A complete snapshot (every saved album) has been applied at least once.
    private(set) var isComplete = false
    /// An override expired without server confirmation — the next refresh
    /// must re-page the full library instead of trusting a prefix probe.
    private(set) var needsFullReconciliation = false

    var hasLoadedAnyData: Bool { serverTotal != nil }

    // MARK: - Snapshot application

    /// Rebuilds the display list from a server snapshot with overrides
    /// layered on top, and reports which overrides this snapshot confirmed
    /// (save seen in server data, or remove absent from a *complete*
    /// snapshot) so the caller can clear them.
    ///
    /// A complete snapshot replaces the display list entirely; a prefix
    /// (first page of a longer library) merges onto the cached tail so the
    /// page paints immediately.
    @discardableResult
    mutating func applyServerSnapshot(
        _ snapshot: [SpotifyClient.SavedAlbum],
        total: Int,
        complete: Bool,
        overrides: [String: OverrideView]
    ) -> Set<String> {
        let snapshotIDs = Set(snapshot.map(\.id))
        confirmedIDs = snapshotIDs
        knownIDs.formUnion(snapshotIDs)
        serverTotal = total
        if complete {
            isComplete = true
            needsFullReconciliation = false
        }

        var display = complete ? snapshot : Self.merge(prefix: snapshot, cached: albums)
        var displayIDs = Set(display.map(\.id))
        // Unconfirmed saves pin to the very top: the user's newest local
        // intent must outrank a stale prefix merge. Confirmed saves keep
        // the server's position.
        let pinned = overrides
            .filter { $0.value.saved && !snapshotIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map(\.value.album)
        for album in pinned {
            display.removeAll { $0.id == album.id }
            displayIDs.remove(album.id)
        }
        for album in pinned.reversed() {
            display.insert(album, at: 0)
            displayIDs.insert(album.id)
        }
        for (id, override) in overrides where !override.saved {
            if displayIDs.contains(id) {
                display.removeAll { $0.id == id }
                displayIDs.remove(id)
            }
        }
        albums = display

        var confirmed: Set<String> = []
        for (id, override) in overrides where isConfirmed(override, id: id, snapshotIDs: snapshotIDs, complete: complete) {
            confirmed.insert(id)
        }
        return confirmed
    }

    /// Newest page on top; cached tail entries only pushed down, never lost.
    static func merge(
        prefix: [SpotifyClient.SavedAlbum],
        cached: [SpotifyClient.SavedAlbum]
    ) -> [SpotifyClient.SavedAlbum] {
        let prefixIDs = Set(prefix.map(\.id))
        return prefix + cached.filter { !prefixIDs.contains($0.id) }
    }

    private func isConfirmed(
        _ override: OverrideView,
        id: String,
        snapshotIDs: Set<String>,
        complete: Bool
    ) -> Bool {
        if override.saved {
            // Save visible in server data (a prefix already proves it).
            return snapshotIDs.contains(id)
        }
        // Removal is only proven absent by a snapshot covering the whole
        // library; a prefix can't see the tail.
        return complete && !snapshotIDs.contains(id)
    }

    // MARK: - Optimistic edits (immediate, snapshot-independent)

    mutating func insertOptimistic(_ album: SpotifyClient.SavedAlbum) {
        knownIDs.insert(album.id)
        if !albums.contains(where: { $0.id == album.id }) {
            albums.insert(album, at: 0)
        }
    }

    mutating func removeOptimistic(id: String) {
        knownIDs.insert(id)
        albums.removeAll { $0.id == id }
    }

    /// Records a contains-probe answer. Callers must not invoke this while an
    /// override for the id exists (AppModel guards that); a probe result
    /// arriving after a local intent would otherwise read as confirmation of
    /// a write the server may not have applied yet.
    mutating func noteProbe(_ album: SpotifyClient.SavedAlbum, saved: Bool) {
        knownIDs.insert(album.id)
        if saved {
            confirmedIDs.insert(album.id)
            if !albums.contains(where: { $0.id == album.id }) {
                albums.insert(album, at: 0)
            }
        } else {
            confirmedIDs.remove(album.id)
        }
    }

    mutating func markNeedsReconciliation() {
        needsFullReconciliation = true
    }

    // MARK: - Derived state

    /// Effective saved state for one album: override wins over any snapshot
    /// or probe; nil = unknown (callers probe before showing a toggle).
    func savedState(
        _ id: String,
        overrides: [String: OverrideView] = [:]
    ) -> Bool? {
        if let override = overrides[id] {
            return override.saved
        }
        if isComplete {
            return albums.contains { $0.id == id }
        }
        guard knownIDs.contains(id) else { return nil }
        return confirmedIDs.contains(id)
    }

    func isKnown(_ id: String, overrides: [String: OverrideView] = [:]) -> Bool {
        savedState(id, overrides: overrides) != nil
    }

    /// Sidebar count: server total adjusted by overrides the server data
    /// hasn't confirmed yet. Never negative.
    func displayCount(overrides: [String: OverrideView]) -> Int {
        var count = serverTotal ?? albums.count
        for (id, override) in overrides {
            let serverHas = confirmedIDs.contains(id)
            if override.saved, !serverHas {
                count += 1
            } else if !override.saved, serverHas {
                count -= 1
            }
        }
        return max(0, count)
    }
}
