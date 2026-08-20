import Foundation

@main
private enum StateReducerTests {
    static func main() {
        testSingleFailedLikeRollsBack()
        testObsoleteFailureAfterToggleBackNeedsNoSecondWrite()
        testLatestFailureRollsBackToSuccessfulOlderWrite()
        testTwoSuccessfulWritesSettleOnLatestIntent()
        testRepeatedIntentAfterTwoFailuresRollsBackToServer()
        testRepeatedIntentAfterFailureThenSuccessSettles()
        testNewerServerObservationWinsOverFailedWrite()
        testSignOutRejectsLateCredentialPersistence()

        testSaveOverrideInsertsAtTopAndBumpsCount()
        testRemoveOverrideDropsConfirmedRowAndCount()
        testStalePrefixCannotResurrectRemovedAlbum()
        testUnknownRemoveOverrideDoesNotChangeCount()
        testSaveBeforeFirstSnapshotDoesNotDoubleCount()
        testCompleteSnapshotRebasesRapidToggleCount()
        testPrefixMergeKeepsCachedTailWithoutDuplicates()
        testPrefixRefreshKeepsOverrideCountBaseline()
        testCompleteSnapshotValidationRejectsPaginationDrift()
        testCompleteSnapshotReplacesDisplayAndClearsReconciliationFlag()
        testSaveOverrideConfirmedBySnapshotReportsForClearing()
        testRemoveOverrideNeedsCompleteSnapshotToConfirm()
        testProbeResultRecordsKnownState()
        testPartialPrefixPreservesPositiveProbe()
        testCompleteSnapshotRejectsOlderProbe()
        testChangedPrefixRejectsMixedPaginationSnapshot()
        testPartialPrefixDoesNotDoubleAdjustRemovalCount()
        testRollbackRestoresOriginalAlbumPosition()
        testConcurrentRemovalRollbacksRestoreOriginalOrder()
        testNewlySavedAlbumRollbackRestoresAtTop()
        testRollbackUsesNewerCanonicalOrder()
        testExpiryMarkingForcesFullReconciliation()
        print("State reducer tests passed")
    }

    // MARK: - MembershipMutation (track likes + album saves)

    private static func testSingleFailedLikeRollsBack() {
        for initiallySaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: initiallySaved,
                desiredSaved: !initiallySaved
            )
            let attempt = mutation.nextAttempt()
            expect(
                mutation.resolve(attempt, succeeded: false) == .rollback(to: initiallySaved),
                "single failed write must roll back to the confirmed state"
            )
        }
    }

    private static func testObsoleteFailureAfterToggleBackNeedsNoSecondWrite() {
        for initiallySaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: initiallySaved,
                desiredSaved: !initiallySaved
            )
            let obsoleteAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallySaved)
            expect(
                mutation.resolve(obsoleteAttempt, succeeded: false)
                    == .settled(maskServerLag: false),
                "an obsolete failure must settle when latest intent already matches the server"
            )
        }
    }

    private static func testLatestFailureRollsBackToSuccessfulOlderWrite() {
        for initiallySaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: initiallySaved,
                desiredSaved: !initiallySaved
            )
            let firstAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallySaved)
            expect(
                mutation.resolve(firstAttempt, succeeded: true) == .persistLatest,
                "a newer intent must be persisted after an older success"
            )

            let latestAttempt = mutation.nextAttempt()
            expect(
                mutation.resolve(latestAttempt, succeeded: false)
                    == .rollback(to: !initiallySaved),
                "latest failure must roll back to the last successful write"
            )
        }
    }

    private static func testTwoSuccessfulWritesSettleOnLatestIntent() {
        for initiallySaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: initiallySaved,
                desiredSaved: !initiallySaved
            )
            let firstAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallySaved)
            expect(
                mutation.resolve(firstAttempt, succeeded: true) == .persistLatest,
                "the second intent must survive the first success"
            )
            let secondAttempt = mutation.nextAttempt()
            expect(
                mutation.resolve(secondAttempt, succeeded: true)
                    == .settled(maskServerLag: true),
                "the final successful write must mask read-after-write lag"
            )
            expect(
                mutation.confirmedSaved == initiallySaved,
                "latest successful state must be confirmed"
            )
        }
    }

    private static func testRepeatedIntentAfterTwoFailuresRollsBackToServer() {
        for initiallySaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: initiallySaved,
                desiredSaved: !initiallySaved
            )
            let obsoleteAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallySaved)
            mutation.setDesired(!initiallySaved)
            expect(
                mutation.resolve(obsoleteAttempt, succeeded: false) == .persistLatest,
                "the repeated latest intent must survive an obsolete failure"
            )

            let latestAttempt = mutation.nextAttempt()
            expect(
                mutation.resolve(latestAttempt, succeeded: false)
                    == .rollback(to: initiallySaved),
                "two failed writes must return to the original server state"
            )
        }
    }

    private static func testRepeatedIntentAfterFailureThenSuccessSettles() {
        for initiallySaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: initiallySaved,
                desiredSaved: !initiallySaved
            )
            let obsoleteAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallySaved)
            mutation.setDesired(!initiallySaved)
            expect(
                mutation.resolve(obsoleteAttempt, succeeded: false) == .persistLatest,
                "the writer must retry a repeated latest intent"
            )

            let latestAttempt = mutation.nextAttempt()
            expect(
                mutation.resolve(latestAttempt, succeeded: true)
                    == .settled(maskServerLag: true),
                "a successful retry must settle on the latest intent"
            )
            expect(
                mutation.confirmedSaved == !initiallySaved,
                "the successful retry must become the confirmed state"
            )
        }
    }

    private static func testNewerServerObservationWinsOverFailedWrite() {
        for observedSaved in [false, true] {
            var mutation = MembershipMutation(
                confirmedSaved: !observedSaved,
                desiredSaved: observedSaved
            )
            let attempt = mutation.nextAttempt()

            mutation.observeConfirmedState(observedSaved)

            expect(
                mutation.resolve(attempt, succeeded: false)
                    == .settled(maskServerLag: false),
                "a failed write must not roll back a newer server observation"
            )
            expect(
                mutation.confirmedSaved == observedSaved,
                "the newer server observation must remain authoritative"
            )
        }
    }

    private static func testSignOutRejectsLateCredentialPersistence() {
        var state = CredentialPersistenceState()
        let refreshRevision = state.beginRefresh()
        expect(refreshRevision != nil, "an active session must allow refresh")

        // Deterministic ordering: HTTP 200 has completed, sign-out begins,
        // then the suspended refresh continuation attempts persistence.
        state.beginClear()
        expect(
            !state.acceptsRefresh(refreshRevision!),
            "sign-out must reject a replacement token from an older refresh"
        )
        expect(state.beginRefresh() == nil, "a clearing session must reject new refreshes")

        state.installNewSession()
        expect(
            state.beginRefresh() != nil,
            "an explicit new sign-in must receive a usable revision"
        )

        let signInRevision = state.beginNewSession()
        state.beginClear()
        expect(
            !state.acceptsRefresh(signInRevision),
            "sign-out must reject a token exchange from an older interactive sign-in"
        )
    }

    // MARK: - SavedAlbumCache (M4.3)

    private static func album(_ id: String, name: String = "Album", artist: String = "Artist") -> SpotifyClient.SavedAlbum {
        SpotifyClient.SavedAlbum(
            album: .init(
                id: id, name: name, artistName: artist, group: "album",
                year: "2020", trackCount: 10, artworkURL: nil
            ),
            addedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private static func override(
        _ album: SpotifyClient.SavedAlbum,
        saved: Bool,
        countedInServerTotal: Bool
    ) -> [String: SavedAlbumCache.OverrideView] {
        [album.id: .init(
            saved: saved,
            countedInServerTotal: countedInServerTotal,
            album: album
        )]
    }

    private static func testSaveOverrideInsertsAtTopAndBumpsCount() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a"), album("b")], total: 2, complete: true, overrides: [:])
        let newAlbum = album("new")
        cache.insertOptimistic(newAlbum)

        let confirmed = cache.applyServerSnapshot(
            [album("a"), album("b")], total: 2, complete: false,
            overrides: override(newAlbum, saved: true, countedInServerTotal: false)
        )
        expect(
            !confirmed.contains(newAlbum.id),
            "a save the server data has not shown yet must not count as confirmed"
        )
        expect(
            cache.albums.map(\.id) == ["new", "a", "b"],
            "saved override must sit at the top of Recently Added"
        )
        expect(
            cache.displayCount(overrides: override(newAlbum, saved: true, countedInServerTotal: false)) == 3,
            "unconfirmed save must bump the count above the server total"
        )
        expect(
            cache.savedState("new", overrides: override(newAlbum, saved: true, countedInServerTotal: false)) == true,
            "override must answer the saved state"
        )
    }

    private static func testRemoveOverrideDropsConfirmedRowAndCount() {
        var cache = SavedAlbumCache()
        let snapshot = [album("a"), album("b")]
        cache.applyServerSnapshot(snapshot, total: 2, complete: true, overrides: [:])

        let removed = snapshot[0]
        let overrides = override(removed, saved: false, countedInServerTotal: true)
        cache.applyServerSnapshot(snapshot, total: 2, complete: false, overrides: overrides)

        expect(
            cache.albums.map(\.id) == ["b"],
            "remove override must drop the row even when stale server data still lists it"
        )
        expect(
            cache.displayCount(overrides: overrides) == 1,
            "removing a server-confirmed album must decrement the count"
        )
        expect(
            cache.savedState(removed.id, overrides: overrides) == false,
            "remove override must answer the saved state"
        )
    }

    private static func testStalePrefixCannotResurrectRemovedAlbum() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a"), album("b"), album("c")], total: 3, complete: true, overrides: [:])

        // User removes "a"; a lagged prefix snapshot still contains it.
        let removed = album("a")
        let overrides = override(removed, saved: false, countedInServerTotal: true)
        cache.removeOptimistic(id: removed.id)
        cache.applyServerSnapshot([album("a"), album("b")], total: 3, complete: false, overrides: overrides)

        expect(
            !cache.albums.contains { $0.id == "a" },
            "a stale snapshot must never resurrect a just-removed album"
        )
        expect(
            cache.savedState("a", overrides: overrides) == false,
            "the local intent must keep answering state over the stale snapshot"
        )
    }

    private static func testUnknownRemoveOverrideDoesNotChangeCount() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a")], total: 1, complete: true, overrides: [:])

        // Removing an album the server data never mentioned (saved and
        // removed before any refresh saw it) must not decrement the count.
        let ghost = album("ghost")
        let overrides = override(ghost, saved: false, countedInServerTotal: false)
        cache.applyServerSnapshot([album("a")], total: 1, complete: true, overrides: overrides)

        expect(cache.displayCount(overrides: overrides) == 1, "unknown removal must not change the count")
    }

    private static func testSaveBeforeFirstSnapshotDoesNotDoubleCount() {
        var cache = SavedAlbumCache()
        let saved = album("saved")
        cache.insertOptimistic(saved)
        let overrides = override(saved, saved: true, countedInServerTotal: false)

        expect(
            cache.displayCount(overrides: overrides) == 1,
            "an optimistic save before the first server total must count exactly once"
        )
    }

    private static func testCompleteSnapshotRebasesRapidToggleCount() {
        var cache = SavedAlbumCache()
        let saved = album("saved")
        cache.applyServerSnapshot([saved], total: 1, complete: true, overrides: [:])

        // Remove succeeded, then the user saved again while a snapshot that
        // observes the intermediate removal arrived. The latest save stays
        // optimistic, but its count baseline must follow that snapshot.
        var overrides = override(saved, saved: true, countedInServerTotal: true)
        overrides = SavedAlbumCache.rebasedOverrides(overrides, snapshot: [], complete: true)
        cache.applyServerSnapshot([], total: 0, complete: true, overrides: overrides)

        expect(cache.albums.map(\.id) == [saved.id], "latest save intent must remain visible")
        expect(
            cache.displayCount(overrides: overrides) == 1,
            "a complete intermediate snapshot must rebase the latest intent count"
        )

        // The inverse Save -> Remove sequence must rebase in the other
        // direction when the intermediate save appears in the snapshot.
        cache = SavedAlbumCache()
        cache.applyServerSnapshot([], total: 0, complete: true, overrides: [:])
        overrides = override(saved, saved: false, countedInServerTotal: false)
        overrides = SavedAlbumCache.rebasedOverrides(overrides, snapshot: [saved], complete: true)
        cache.applyServerSnapshot([saved], total: 1, complete: true, overrides: overrides)

        expect(cache.albums.isEmpty, "latest remove intent must remain hidden")
        expect(
            cache.displayCount(overrides: overrides) == 0,
            "the inverse intermediate snapshot must rebase the latest remove count"
        )
    }

    private static func testPrefixMergeKeepsCachedTailWithoutDuplicates() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a"), album("b"), album("c")], total: 3, complete: true, overrides: [:])

        // Another client saved "x": the new prefix shifts the old head down.
        cache.applyServerSnapshot([album("x"), album("a")], total: 4, complete: false, overrides: [:])

        expect(
            cache.albums.map(\.id) == ["x", "a", "b", "c"],
            "prefix merge must keep the cached tail exactly once, no duplicates"
        )
        expect(cache.displayCount(overrides: [:]) == 4, "server total must replace the stale one")
    }

    private static func testPrefixRefreshKeepsOverrideCountBaseline() {
        var cache = SavedAlbumCache()
        let snapshot = [album("a"), album("b"), album("c")]
        cache.applyServerSnapshot(snapshot, total: 3, complete: true, overrides: [:])

        let removed = snapshot[2]
        let overrides = override(removed, saved: false, countedInServerTotal: true)
        cache.removeOptimistic(id: removed.id)
        cache.applyServerSnapshot([snapshot[0]], total: 3, complete: false, overrides: overrides)

        expect(
            cache.displayCount(overrides: overrides) == 2,
            "a prefix refresh must not forget the confirmed baseline for a tail removal"
        )
    }

    private static func testCompleteSnapshotValidationRejectsPaginationDrift() {
        let duplicate = [album("a"), album("a"), album("b")]
        expect(
            !SavedAlbumCache.isCompleteSnapshot(duplicate, total: 3),
            "a cross-page duplicate must invalidate a complete snapshot"
        )
        expect(
            !SavedAlbumCache.isCompleteSnapshot([album("a"), album("b")], total: 3),
            "a short pagination result must invalidate a complete snapshot"
        )
        expect(
            SavedAlbumCache.isCompleteSnapshot([album("a"), album("b")], total: 2),
            "a unique result matching the server total must be complete"
        )
    }

    private static func testCompleteSnapshotReplacesDisplayAndClearsReconciliationFlag() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a"), album("b")], total: 2, complete: true, overrides: [:])
        cache.markNeedsReconciliation()

        // "b" was removed by another client; the complete snapshot is truth.
        cache.applyServerSnapshot([album("a")], total: 1, complete: true, overrides: [:])

        expect(cache.albums.map(\.id) == ["a"], "a complete snapshot must replace the display list")
        expect(!cache.needsFullReconciliation, "a complete snapshot must clear the reconciliation flag")
        expect(cache.isComplete, "completeness is sticky")
    }

    private static func testSaveOverrideConfirmedBySnapshotReportsForClearing() {
        var cache = SavedAlbumCache()
        let saved = album("saved")
        cache.insertOptimistic(saved)

        let confirmed = cache.applyServerSnapshot(
            [saved, album("a")], total: 2, complete: false,
            overrides: override(saved, saved: true, countedInServerTotal: false)
        )

        expect(
            confirmed.contains(saved.id),
            "a save visible in fetched server data must be reported for override clearing"
        )
        expect(
            cache.displayCount(overrides: [:]) == 2,
            "after clearing the confirmed override, count matches the server total"
        )
    }

    private static func testRemoveOverrideNeedsCompleteSnapshotToConfirm() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a"), album("b")], total: 3, complete: false, overrides: [:])
        let removed = album("b")
        let overrides = override(removed, saved: false, countedInServerTotal: true)

        let prefixConfirmed = cache.applyServerSnapshot(
            [album("a")], total: 3, complete: false, overrides: overrides
        )
        expect(
            !prefixConfirmed.contains(removed.id),
            "a prefix snapshot cannot prove an album is gone (it may sit in the tail)"
        )

        let completeConfirmed = cache.applyServerSnapshot(
            [album("a")], total: 1, complete: true, overrides: overrides
        )
        expect(
            completeConfirmed.contains(removed.id),
            "a complete snapshot must confirm the removal"
        )
    }

    private static func testProbeResultRecordsKnownState() {
        var cache = SavedAlbumCache()

        // Probe says unsaved: known, not in the list.
        cache.noteProbe(album("gone"), saved: false)
        expect(cache.savedState("gone") == false, "a negative probe must answer known-unsaved")
        expect(!cache.isKnown("other"), "unprobed ids must stay unknown")

        // Probe says saved: known and visible in the list.
        cache.noteProbe(album("here"), saved: true)
        expect(cache.savedState("here") == true, "a positive probe must answer known-saved")
        expect(
            cache.albums.map(\.id) == ["here"],
            "a positive probe must insert the row for display"
        )
    }

    private static func testPartialPrefixPreservesPositiveProbe() {
        var cache = SavedAlbumCache()
        let tailAlbum = album("tail")
        cache.noteProbe(tailAlbum, saved: true)

        cache.applyServerSnapshot(
            [album("head")], total: 2, complete: false, overrides: [:]
        )

        expect(
            cache.savedState(tailAlbum.id) == true,
            "a partial prefix must not overturn a positive probe for a tail album"
        )
    }

    private static func testCompleteSnapshotRejectsOlderProbe() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("head")], total: 1, complete: true, overrides: [:])

        // This result represents a contains request that started before the
        // complete snapshot and returned afterward.
        cache.noteProbe(album("stale"), saved: true)

        expect(
            cache.savedState("stale") == false,
            "an older probe must not overwrite a newer complete snapshot"
        )
        expect(
            cache.albums.map(\.id) == ["head"],
            "an older positive probe must not resurrect a row"
        )
    }

    private static func testChangedPrefixRejectsMixedPaginationSnapshot() {
        let originalPrefix = [album("a"), album("b")]
        let mixedSnapshot = originalPrefix + [album("c"), album("d")]

        expect(
            !SavedAlbumCache.prefixMatches(
                [album("x"), album("a")],
                total: 4,
                snapshot: mixedSnapshot
            ),
            "a changed head must reject a snapshot assembled from older pages"
        )
        expect(
            SavedAlbumCache.prefixMatches(
                originalPrefix,
                total: 4,
                snapshot: mixedSnapshot
            ),
            "an unchanged head and total must validate the assembled snapshot"
        )
    }

    private static func testPartialPrefixDoesNotDoubleAdjustRemovalCount() {
        var cache = SavedAlbumCache()
        let snapshot = [album("a"), album("b"), album("tail")]
        cache.applyServerSnapshot(snapshot, total: 3, complete: true, overrides: [:])

        let removed = snapshot[2]
        let overrides = override(removed, saved: false, countedInServerTotal: true)
        cache.removeOptimistic(id: removed.id)

        // The server total already reflects the removal, but a prefix cannot
        // prove that this tail album is gone. Keep the previous total until a
        // complete snapshot can rebase and confirm the override.
        cache.applyServerSnapshot([snapshot[0]], total: 2, complete: false, overrides: overrides)

        expect(
            cache.displayCount(overrides: overrides) == 2,
            "a partial prefix must not subtract a tail removal twice"
        )
    }

    private static func testRollbackRestoresOriginalAlbumPosition() {
        var cache = SavedAlbumCache()
        let snapshot = [album("a"), album("b"), album("c")]
        cache.applyServerSnapshot(snapshot, total: 3, complete: true, overrides: [:])
        let placement = cache.placement(for: "b")
        expect(placement != nil, "a cached album must expose its confirmed placement")

        cache.removeOptimistic(id: "b")
        cache.restoreOptimistic(placement!)

        expect(
            cache.albums.map(\.id) == ["a", "b", "c"],
            "a failed removal must restore the album at its original index"
        )
    }

    private static func testConcurrentRemovalRollbacksRestoreOriginalOrder() {
        var cache = SavedAlbumCache()
        let snapshot = [album("a"), album("b"), album("c")]
        cache.applyServerSnapshot(snapshot, total: 3, complete: true, overrides: [:])

        let bPlacement = cache.placement(for: "b")!
        cache.removeOptimistic(id: "b")
        let aPlacement = cache.placement(for: "a")!
        cache.removeOptimistic(id: "a")

        // Complete in the order that broke absolute display indexes.
        cache.restoreOptimistic(bPlacement)
        cache.restoreOptimistic(aPlacement)

        expect(
            cache.albums.map(\.id) == ["a", "b", "c"],
            "concurrent failed removals must restore the exact server order"
        )
    }

    private static func testNewlySavedAlbumRollbackRestoresAtTop() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a"), album("b")], total: 2, complete: true, overrides: [:])

        let saved = album("new")
        cache.insertOptimistic(saved)
        let placement = cache.placement(for: saved.id)!
        cache.removeOptimistic(id: saved.id)
        cache.restoreOptimistic(placement)

        expect(
            cache.albums.map(\.id) == ["new", "a", "b"],
            "a confirmed local save must return to the top when a later removal fails"
        )
    }

    private static func testRollbackUsesNewerCanonicalOrder() {
        var cache = SavedAlbumCache()
        let b = album("b")
        cache.applyServerSnapshot([album("a"), b, album("c")], total: 3, complete: true, overrides: [:])
        let placement = cache.placement(for: b.id)!
        cache.removeOptimistic(id: b.id)

        let overrides = override(b, saved: false, countedInServerTotal: true)
        cache.applyServerSnapshot([b, album("c")], total: 2, complete: true, overrides: overrides)
        cache.restoreOptimistic(placement)

        expect(
            cache.albums.map(\.id) == ["b", "c"],
            "a failed removal must follow a newer complete server ordering"
        )
    }

    private static func testExpiryMarkingForcesFullReconciliation() {
        var cache = SavedAlbumCache()
        cache.applyServerSnapshot([album("a")], total: 1, complete: true, overrides: [:])
        expect(!cache.needsFullReconciliation, "fresh cache needs no reconciliation")

        cache.markNeedsReconciliation()
        expect(cache.needsFullReconciliation, "expiry marking must force full re-paging")
    }

    // MARK: - Harness

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
            exit(1)
        }
    }
}
