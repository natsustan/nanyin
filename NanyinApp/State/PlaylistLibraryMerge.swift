//
//  PlaylistLibraryMerge.swift
//  Nanyin
//

import Foundation

/// Pure reducer reconciling the sidebar playlist list with confirmed local
/// mutations (M4.5). Spotify reads may briefly lag a successful write, so
/// snapshots confirm mutations by content rather than request ordering.
struct PlaylistLibraryMerge {
    /// One server-confirmed local write, tagged with the serial it was
    /// confirmed under.
    struct ConfirmedMutation: Equatable {
        enum Kind: Equatable {
            /// A playlist created locally — must survive in the list.
            case created(SpotifyClient.PlaylistInfo)
            /// A track add confirmed by the server. `localCount` is the
            /// playlist count the UI already shows after the add; a stale
            /// snapshot below it must not pull the count back down.
            case trackAdded(playlistID: String, localCount: Int)
        }

        let serial: Int
        let kind: Kind
        /// Bound stale-read protection so a later server-side delete or
        /// count decrease eventually wins even if it cannot confirm this
        /// mutation by content.
        var staleSnapshotsRemaining = 2
    }

    /// Applies one confirmed mutation to a list (the local update path —
    /// also the per-mutation step of `merge`).
    static func apply(
        _ mutation: ConfirmedMutation,
        to playlists: [SpotifyClient.PlaylistInfo]
    ) -> [SpotifyClient.PlaylistInfo] {
        var result = playlists
        switch mutation.kind {
        case let .created(info):
            if !result.contains(where: { $0.id == info.id }) {
                result.insert(info, at: 0)
            }
        case let .trackAdded(playlistID, localCount):
            if let index = result.firstIndex(where: { $0.id == playlistID }) {
                // The snapshot's fetch may or may not include this add —
                // never double-count: keep the larger of the two values.
                result[index].trackCount = max(result[index].trackCount, localCount)
            }
            // A target missing from the snapshot (deleted by another
            // client) is left out — server truth wins for existence.
        }
        return result
    }

    /// Merges a server snapshot with pending confirmed writes. A mutation
    /// retires when the snapshot visibly includes it, its target disappears,
    /// or its bounded stale-read allowance is exhausted.
    static func merge(
        snapshot: [SpotifyClient.PlaylistInfo],
        mutations: [ConfirmedMutation]
    ) -> (playlists: [SpotifyClient.PlaylistInfo], pending: [ConfirmedMutation]) {
        var result = snapshot
        var pending: [ConfirmedMutation] = []
        for mutation in mutations.sorted(by: { $0.serial < $1.serial }) {
            switch mutation.kind {
            case let .created(info):
                // Keep the newer snapshot object when the playlist is now
                // visible; it may already have artwork or a newer count.
                guard !snapshot.contains(where: { $0.id == info.id }) else { continue }
            case let .trackAdded(playlistID, localCount):
                if let serverPlaylist = snapshot.first(where: { $0.id == playlistID }) {
                    guard serverPlaylist.trackCount < localCount else { continue }
                } else {
                    // A locally-created playlist may still be hidden by the
                    // same stale snapshot. Any other missing target was
                    // deleted elsewhere, so server truth wins immediately.
                    guard result.contains(where: { $0.id == playlistID }) else { continue }
                }
            }

            guard mutation.staleSnapshotsRemaining > 0 else { continue }
            result = apply(mutation, to: result)
            var retained = mutation
            retained.staleSnapshotsRemaining -= 1
            pending.append(retained)
        }
        return (result, pending)
    }
}
