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

        testLocalPlaybackSnapshotRoundTrips()
        testLocalPlaybackSnapshotRejectsAnotherAccount()
        testCompletedLocalPlaybackRestartsFromBeginning()
        testLocalPlaybackRestoreStateKeepsSnapshotWhileStarting()
        testLateSnapshotDoesNotOverwriteLivePlayback()
        testIdleLocalPlaybackRestoreAcceptsCurrentExternalPlayback()
        testLocalPlaybackOwnershipTransfersToExpectedSuccessor()
        testLocalPlaybackOwnershipRejectsUnexpectedReplacement()

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

        testFollowedArtistsSnapshotPreservesCursorOrderAndCounts()
        testFollowedArtistsCursorPageDecodes()
        testFollowedArtistsPaginationCompletesPastFifty()
        testFollowedArtistsCompleteSnapshotReplacesPartialFallback()
        testFollowedArtistsPartialFallbackInvalidatesCompleteness()
        testStaleFollowedArtistsPrefixCannotUndoUnfollow()
        testFollowedArtistsPartialTotalDoesNotDoubleAdjustUnfollow()
        testFollowedArtistsRollbackRetainsCountCompensation()
        testFollowedArtistsRefreshCannotExpireANewerOverride()
        testOptimisticFollowAdjustsCountAndConfirms()
        testCompleteFollowedArtistsSnapshotConvergesToRemoteChanges()

        testPlaybackStallDetectorClassifiesDownloaderStall()
        testPlaybackStallDetectorClassifiesDecoderStall()
        testPlaybackStallDetectorClassifiesPCMStall()
        testPlaybackStallDetectorClassifiesRendererStall()
        testPlaybackStallDetectorIgnoresPausedAndProgressingPlayback()
        testPlaybackStallDetectorIgnoresInterruptedObservation()
        testPlaybackStallDetectorRecoversOnlyOncePerPlayRequest()
        testPlaybackStallRecoveryRequiresActualProgress()

        testPendingPlayIntentReplaysOnlyOnce()
        testPendingPlayIntentExpires()
        testPendingPlayIntentRejectsAnotherAccountEpoch()
        testPendingPlayIntentKeepsOriginalContextCall()
        testPendingPlayIntentMatchesPlayingEvent()
        testPendingPlayIntentIdentifiesPreviousRequestEvents()

        testReconnectDefersWhileAudioIsProgressing()
        testReconnectDoesNotDeferWhenPlaybackNeedsControlPlane()

        testRecentlyPlayedDecodesTracksAndContexts()
        testRecentlyPlayedSkipsUnplayableAndContextlessAlbumEntries()
        testHomePagesRequireItemsArray()
        testTopTimeRangeAndLimitEncoding()
        testRecentAlbumContextUsesTrackAlbum()
        testPlaylistContextResolvesAgainstUserPlaylists()
        testUnknownPlaylistContextFallsBackToTrackAlbum()
        testArtistContextPrefersMatchingTrackArtist()
        testRecentCardsDedupeAndCap()
        testContextRefIDRejectsMismatchedKind()

        testCreatedPlaylistDecodesWithOwnership()
        testPlaylistSummaryPrefersItemsTotal()
        testCreateBodyCarriesExplicitEmptyDescription()
        testCreateMutationInsertsAtSidebarTop()
        testStaleRefreshCannotDropCreatedPlaylist()
        testStaleRefreshCannotRevertAddCount()
        testRefreshIncludingAddDoesNotDoubleCount()
        testRefreshRetiresVisibleCreateWithoutReplacingSnapshot()
        testStaleProtectionExpiresToServerTruth()
        testCreateThenAddBeforeStaleRefreshKeepsBoth()
        testAddMutationSkipsMissingPlaylist()
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

    // MARK: - FollowedArtistCache (M4.9)

    private static func followedArtist(_ id: String, name: String) -> SpotifyClient.Artist {
        SpotifyClient.Artist(id: id, name: name, artworkURL: nil)
    }

    private static func testFollowedArtistsSnapshotPreservesCursorOrderAndCounts() {
        var cache = FollowedArtistCache()
        cache.applyServerSnapshot(
            [followedArtist("b", name: "Björk"), followedArtist("a", name: "Air")],
            total: 2,
            complete: true,
            overrides: [:]
        )
        expect(
            cache.artists.map(\.id) == ["b", "a"],
            "artist library preserves Spotify cursor order"
        )
        expect(cache.displayCount(overrides: [:]) == 2, "artist count uses server total")
    }

    private static func testFollowedArtistsCursorPageDecodes() {
        let page = try! SpotifyClient.decodeFollowedArtistsPage(Data(#"""
        {
          "artists": {
            "items": [{"id":"a","name":"Air","images":[{"url":"https://example.com/a.jpg"}]}],
            "cursors": {"after":"cursor-a"},
            "next": "https://api.spotify.com/v1/me/following?after=cursor-a",
            "total": 51
          }
        }
        """#.utf8))
        expect(page.artists.map(\.id) == ["a"], "cursor page decodes artist items")
        expect(page.after == "cursor-a", "nonterminal cursor page retains after")
        expect(page.total == 51, "cursor page retains server total")

        let terminal = try! SpotifyClient.decodeFollowedArtistsPage(Data(#"""
        {
          "artists": {"items":[],"cursors":{"after":"ignored"},"next":null,"total":0}
        }
        """#.utf8))
        expect(terminal.after == nil, "terminal cursor page ignores its trailing cursor")
    }

    private static func testFollowedArtistsPaginationCompletesPastFifty() {
        let artists = (0..<55).map {
            followedArtist("\($0)", name: String(format: "Artist %02d", $0))
        }
        var cache = FollowedArtistCache()
        cache.applyServerSnapshot(
            Array(artists.prefix(50)), total: 55, complete: false, overrides: [:]
        )
        expect(cache.artists.count == 50, "a failed tail can retain the first cursor page")
        expect(cache.hasLoadedAnyData, "a partial fallback is usable library data")
        expect(
            FollowedArtistCache.isCompleteSnapshot(artists, total: 55),
            "a unique 55-item cursor snapshot is complete"
        )
        cache.applyServerSnapshot(artists, total: 55, complete: true, overrides: [:])
        expect(cache.artists.count == 55, "tail pagination publishes every artist")
        expect(
            !FollowedArtistCache.isCompleteSnapshot(artists + [artists[0]], total: 56),
            "duplicate cursor items cannot form a complete snapshot"
        )
    }

    private static func testFollowedArtistsCompleteSnapshotReplacesPartialFallback() {
        var cache = FollowedArtistCache()
        let firstPage = [
            followedArtist("b", name: "Björk"),
            followedArtist("c", name: "Coldplay"),
        ]
        cache.applyServerSnapshot(firstPage, total: 3, complete: false, overrides: [:])
        expect(cache.artists.map(\.id) == ["b", "c"], "partial fallback retains cursor order")
        cache.applyServerSnapshot(
            firstPage + [followedArtist("a", name: "Air")],
            total: 3,
            complete: true,
            overrides: [:]
        )
        expect(
            cache.artists.map(\.id) == ["b", "c", "a"],
            "completion publishes cursor order without an intermediate reorder"
        )
    }

    private static func testFollowedArtistsPartialFallbackInvalidatesCompleteness() {
        var cache = FollowedArtistCache()
        let artists = [
            followedArtist("a", name: "Air"),
            followedArtist("b", name: "Björk"),
        ]
        cache.applyServerSnapshot(artists, total: 2, complete: true, overrides: [:])
        cache.applyServerSnapshot([artists[0]], total: 2, complete: false, overrides: [:])

        expect(!cache.isComplete, "a failed tail must invalidate snapshot completeness")
        expect(cache.artists.map(\.id) == ["a", "b"], "a partial fallback retains the cached tail")
    }

    private static func testStaleFollowedArtistsPrefixCannotUndoUnfollow() {
        var cache = FollowedArtistCache()
        let artist = followedArtist("a", name: "Air")
        cache.applyServerSnapshot([artist], total: 1, complete: true, overrides: [:])
        cache.removeOptimistic(id: artist.id)
        let overrides = [artist.id: FollowedArtistCache.OverrideView(
            followed: false,
            countedInServerTotal: true,
            artist: artist
        )]
        cache.applyServerSnapshot([artist], total: 1, complete: false, overrides: overrides)
        expect(cache.artists.isEmpty, "a stale cursor prefix cannot resurrect an unfollowed artist")
        expect(cache.displayCount(overrides: overrides) == 0, "optimistic unfollow adjusts count")
    }

    private static func testFollowedArtistsPartialTotalDoesNotDoubleAdjustUnfollow() {
        var cache = FollowedArtistCache()
        let removed = followedArtist("removed", name: "Removed")
        let retained = followedArtist("retained", name: "Retained")
        cache.applyServerSnapshot([removed, retained], total: 2, complete: true, overrides: [:])
        cache.removeOptimistic(id: removed.id)
        let overrides = [removed.id: FollowedArtistCache.OverrideView(
            followed: false,
            countedInServerTotal: true,
            artist: removed
        )]
        cache.applyServerSnapshot([retained], total: 1, complete: false, overrides: overrides)
        expect(
            cache.displayCount(overrides: overrides) == 1,
            "partial total cannot double-count an unconfirmed unfollow"
        )
    }

    private static func testFollowedArtistsRollbackRetainsCountCompensation() {
        let artist = followedArtist("a", name: "Air")

        var followMutation = MembershipMutation(confirmedSaved: false, desiredSaved: true)
        let followAttempt = followMutation.nextAttempt()
        followMutation.setDesired(false)
        expect(
            followMutation.resolve(followAttempt, succeeded: true) == .persistLatest,
            "a successful older follow persists the newer unfollow intent"
        )
        let failedUnfollow = followMutation.nextAttempt()
        expect(
            followMutation.resolve(failedUnfollow, succeeded: false) == .rollback(to: true),
            "a failed latest unfollow rolls back to the confirmed follow"
        )
        followMutation.setDesired(followMutation.confirmedSaved)
        var followedCache = FollowedArtistCache()
        followedCache.applyServerSnapshot([], total: 0, complete: true, overrides: [:])
        followedCache.insertOptimistic(artist)
        let followedOverride = [artist.id: FollowedArtistCache.OverrideView(
            followed: followMutation.desiredSaved,
            countedInServerTotal: false,
            artist: artist
        )]
        expect(
            followedCache.displayCount(overrides: followedOverride) == 1,
            "rollback to a confirmed follow retains its positive count compensation"
        )

        var unfollowMutation = MembershipMutation(confirmedSaved: true, desiredSaved: false)
        let unfollowAttempt = unfollowMutation.nextAttempt()
        unfollowMutation.setDesired(true)
        expect(
            unfollowMutation.resolve(unfollowAttempt, succeeded: true) == .persistLatest,
            "a successful older unfollow persists the newer follow intent"
        )
        let failedFollow = unfollowMutation.nextAttempt()
        expect(
            unfollowMutation.resolve(failedFollow, succeeded: false) == .rollback(to: false),
            "a failed latest follow rolls back to the confirmed unfollow"
        )
        unfollowMutation.setDesired(unfollowMutation.confirmedSaved)
        var unfollowedCache = FollowedArtistCache()
        unfollowedCache.applyServerSnapshot([artist], total: 1, complete: true, overrides: [:])
        unfollowedCache.removeOptimistic(id: artist.id)
        let unfollowedOverride = [artist.id: FollowedArtistCache.OverrideView(
            followed: unfollowMutation.desiredSaved,
            countedInServerTotal: true,
            artist: artist
        )]
        expect(
            unfollowedCache.displayCount(overrides: unfollowedOverride) == 0,
            "rollback to a confirmed unfollow retains its negative count compensation"
        )
    }

    private static func testFollowedArtistsRefreshCannotExpireANewerOverride() {
        let refreshStartedAt = Date(timeIntervalSince1970: 100)
        expect(
            FollowedArtistCache.shouldRetainOverride(
                expiresAt: Date(timeIntervalSince1970: 110),
                hasActiveMutation: false,
                refreshStartedAt: refreshStartedAt
            ),
            "a refresh retains an override created or settled after it started"
        )
        expect(
            !FollowedArtistCache.shouldRetainOverride(
                expiresAt: Date(timeIntervalSince1970: 90),
                hasActiveMutation: false,
                refreshStartedAt: refreshStartedAt
            ),
            "a refresh may reconcile an override that expired before it started"
        )
        expect(
            FollowedArtistCache.shouldRetainOverride(
                expiresAt: Date(timeIntervalSince1970: 90),
                hasActiveMutation: true,
                refreshStartedAt: refreshStartedAt
            ),
            "an active mutation always wins over a refresh snapshot"
        )
    }

    private static func testOptimisticFollowAdjustsCountAndConfirms() {
        var cache = FollowedArtistCache()
        cache.applyServerSnapshot([], total: 0, complete: true, overrides: [:])
        let artist = followedArtist("new", name: "New Artist")
        cache.insertOptimistic(artist)
        let overrides = [artist.id: FollowedArtistCache.OverrideView(
            followed: true,
            countedInServerTotal: false,
            artist: artist
        )]
        expect(cache.displayCount(overrides: overrides) == 1, "optimistic follow bumps count")
        let confirmed = cache.applyServerSnapshot(
            [artist], total: 1, complete: true, overrides: overrides
        )
        expect(confirmed == [artist.id], "full snapshot confirms the follow")
    }

    private static func testCompleteFollowedArtistsSnapshotConvergesToRemoteChanges() {
        var cache = FollowedArtistCache()
        cache.applyServerSnapshot(
            [followedArtist("a", name: "Air")], total: 1, complete: true, overrides: [:]
        )
        cache.applyServerSnapshot(
            [followedArtist("b", name: "Björk")], total: 1, complete: true, overrides: [:]
        )
        expect(cache.artists.map(\.id) == ["b"], "complete refresh adopts remote membership")
        expect(cache.followedState("a") == false, "complete refresh proves remote unfollow")
    }

    // MARK: - Local playback

    private static func testLocalPlaybackSnapshotRoundTrips() {
        let suite = "com.nanyin.tests.local-playback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = LocalPlaybackSnapshot(
            accountID: "account-a",
            uri: "spotify:track:abc",
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumId: "album-id",
            artworkURL: URL(string: "https://example.com/cover.jpg"),
            durationMs: 180_000,
            positionMs: 42_000
        )

        LocalPlaybackStore.save(snapshot, to: defaults)
        expect(
            LocalPlaybackStore.load(for: "account-a", from: defaults) == snapshot,
            "local playback snapshot must round-trip through UserDefaults"
        )
        LocalPlaybackStore.clear(from: defaults)
        expect(
            LocalPlaybackStore.load(for: "account-a", from: defaults) == nil,
            "clearing local playback must remove the persisted snapshot"
        )
    }

    private static func testCompletedLocalPlaybackRestartsFromBeginning() {
        let snapshot = LocalPlaybackSnapshot(
            accountID: "account-a",
            uri: "spotify:track:abc",
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumId: nil,
            artworkURL: nil,
            durationMs: 180_000,
            positionMs: 180_000
        )
        expect(
            snapshot.playablePositionMs == 0,
            "completed playback must restart instead of seeking to the end"
        )
        expect(
            snapshot.withPosition(176_000).playablePositionMs == 0,
            "near-complete playback must restart instead of ending immediately"
        )
        expect(
            snapshot.withPosition(42_000).playablePositionMs == 42_000,
            "playback with meaningful time remaining must resume its saved position"
        )
    }

    private static func testLocalPlaybackSnapshotRejectsAnotherAccount() {
        let suite = "com.nanyin.tests.local-playback-account.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = LocalPlaybackSnapshot(
            accountID: "account-a",
            uri: "spotify:track:abc",
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumId: nil,
            artworkURL: nil,
            durationMs: 100,
            positionMs: 50
        )

        LocalPlaybackStore.save(snapshot, to: defaults)
        expect(
            LocalPlaybackStore.load(for: "account-b", from: defaults) == nil,
            "a snapshot from another Spotify account must not be restored"
        )
        expect(
            LocalPlaybackStore.load(for: "account-a", from: defaults) == nil,
            "an account mismatch must remove the stale snapshot"
        )
    }

    private static func testLocalPlaybackRestoreStateKeepsSnapshotWhileStarting() {
        let snapshot = LocalPlaybackSnapshot(
            accountID: "account-a",
            uri: "spotify:track:abc",
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumId: nil,
            artworkURL: nil,
            durationMs: 100,
            positionMs: 50
        )
        let idle = LocalPlaybackRestoreState.idle(snapshot)
        let starting = LocalPlaybackRestoreState.starting(snapshot)

        expect(!idle.isStarting, "a restored snapshot must begin idle")
        expect(starting.isStarting, "an explicit restored play must enter starting state")
        expect(
            starting.snapshot == snapshot,
            "starting playback must retain the snapshot until Playing confirms it"
        )
    }

    private static func testLateSnapshotDoesNotOverwriteLivePlayback() {
        expect(
            LocalPlaybackRestoreState.canApplySnapshot(
                hasNowPlaying: false,
                playRequestID: CorePlaybackProgress.noPlayRequest
            ),
            "startup may restore a snapshot before live playback is accepted"
        )
        expect(
            !LocalPlaybackRestoreState.canApplySnapshot(
                hasNowPlaying: true,
                playRequestID: 10
            ),
            "a late snapshot must not overwrite accepted live playback"
        )
        expect(
            !LocalPlaybackRestoreState.canApplySnapshot(
                hasNowPlaying: false,
                playRequestID: 10
            ),
            "an active core request must fence snapshot restoration before metadata arrives"
        )
    }

    private static func testIdleLocalPlaybackRestoreAcceptsCurrentExternalPlayback() {
        let restore = LocalPlaybackRestoreState.idle(localPlaybackSnapshot())

        expect(
            restore.playingDisposition(
                isCurrentRequest: true,
                confirmsRestore: false
            ) == .discardRestore,
            "current external playback must replace an idle local snapshot"
        )
        expect(
            restore.playingDisposition(
                isCurrentRequest: false,
                confirmsRestore: false
            ) == .ignore,
            "a stale Playing event must not replace an idle local snapshot"
        )
    }

    private static func testLocalPlaybackOwnershipTransfersToExpectedSuccessor() {
        let ownership = LocalPlaybackOwnership.current(requestID: 10)
            .expectingSuccessor(after: 10)

        expect(
            ownership.currentRequestID == 10,
            "the current track must remain snapshot-eligible while its successor is loading"
        )
        expect(
            ownership.confirmingPlaying(requestID: 11) == .current(requestID: 11),
            "skip and auto-advance must transfer snapshot ownership to the confirmed successor"
        )
        expect(
            ownership.confirmingPlaying(
                requestID: CorePlaybackProgress.noPlayRequest
            ) == nil,
            "an event without a play request must never acquire snapshot ownership"
        )
    }

    private static func testLocalPlaybackOwnershipRejectsUnexpectedReplacement() {
        let ownership = LocalPlaybackOwnership.current(requestID: 10)

        expect(
            ownership.expectingSuccessor(after: 9) == ownership,
            "a stale EndOfTrack event must not authorize an ownership transfer"
        )
        expect(
            ownership.confirmingPlaying(requestID: 11) == nil,
            "an unexpected external request must not inherit local snapshot ownership"
        )
    }

    private static func localPlaybackSnapshot() -> LocalPlaybackSnapshot {
        LocalPlaybackSnapshot(
            accountID: "account-a",
            uri: "spotify:track:abc",
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumId: nil,
            artworkURL: nil,
            durationMs: 100,
            positionMs: 50
        )
    }

    // MARK: - PlaybackStallDetector

    private static func playbackSnapshot(
        request: UInt64 = 0,
        decoder: UInt64 = 0,
        pcm: UInt64 = 0,
        waiters: UInt64 = 0,
        accepted: UInt64 = 0,
        callbacks: UInt64 = 0,
        rendered: UInt64 = 0,
        position: UInt32 = 42_000
    ) -> PlaybackPipelineSnapshot {
        PlaybackPipelineSnapshot(
            core: CorePlaybackProgress(
                playRequestID: request,
                decoderPackets: decoder,
                pcmWrites: pcm,
                downloadWaiters: waiters,
                confirmedPositionMs: position
            ),
            renderer: RendererPlaybackProgress(
                acceptedSamples: accepted,
                renderCallbacks: callbacks,
                renderedSamples: rendered
            )
        )
    }

    private static func detectStall(
        from baseline: PlaybackPipelineSnapshot,
        to current: PlaybackPipelineSnapshot
    ) -> PlaybackStallDetector.Recovery? {
        var detector = PlaybackStallDetector(stallThresholdMs: 10)
        expect(
            detector.observe(
                baseline, generation: 1, nowMs: 0, expectsPlayback: true
            ) == nil,
            "the first progress sample must establish a baseline"
        )
        return detector.observe(
            current, generation: 1, nowMs: 10, expectsPlayback: true
        )
    }

    private static func testPlaybackStallDetectorClassifiesDownloaderStall() {
        let recovery = detectStall(
            from: playbackSnapshot(callbacks: 1),
            to: playbackSnapshot(waiters: 1, callbacks: 2)
        )
        expect(recovery?.stage == .downloader, "a blocked range read must be a downloader stall")
        expect(recovery?.positionMs == 42_000, "recovery must use confirmed decoder position")
    }

    private static func testPlaybackStallDetectorClassifiesDecoderStall() {
        let recovery = detectStall(
            from: playbackSnapshot(callbacks: 1),
            to: playbackSnapshot(callbacks: 2)
        )
        expect(recovery?.stage == .decoder, "no decoder progress outside a range wait must be a decoder stall")
    }

    private static func testPlaybackStallDetectorClassifiesPCMStall() {
        let recovery = detectStall(
            from: playbackSnapshot(callbacks: 1),
            to: playbackSnapshot(decoder: 1, callbacks: 2)
        )
        expect(recovery?.stage == .pcm, "decoded packets without PCM writes must be a PCM stall")
    }

    private static func testPlaybackStallDetectorClassifiesRendererStall() {
        let stoppedCallback = detectStall(
            from: playbackSnapshot(callbacks: 1),
            to: playbackSnapshot(decoder: 1, pcm: 1, accepted: 1, callbacks: 1)
        )
        expect(stoppedCallback?.stage == .renderer, "a stopped render callback must be a renderer stall")

        let stoppedConsumption = detectStall(
            from: playbackSnapshot(callbacks: 1),
            to: playbackSnapshot(decoder: 1, pcm: 1, accepted: 1, callbacks: 2)
        )
        expect(stoppedConsumption?.stage == .renderer, "unconsumed accepted PCM must be a renderer stall")
    }

    private static func testPlaybackStallDetectorIgnoresPausedAndProgressingPlayback() {
        var detector = PlaybackStallDetector(stallThresholdMs: 10)
        let baseline = playbackSnapshot(callbacks: 1)
        _ = detector.observe(baseline, generation: 1, nowMs: 0, expectsPlayback: true)
        expect(
            detector.observe(
                baseline, generation: 1, nowMs: 20, expectsPlayback: false
            ) == nil,
            "paused playback must disarm stall detection"
        )
        expect(
            detector.observe(
                playbackSnapshot(rendered: 1),
                generation: 1,
                nowMs: 40,
                expectsPlayback: true
            ) == nil,
            "rendered PCM must establish a fresh grace period"
        )
    }

    private static func testPlaybackStallDetectorIgnoresInterruptedObservation() {
        var detector = PlaybackStallDetector(
            stallThresholdMs: 10,
            maxObservationGapMs: 20
        )
        let baseline = playbackSnapshot(callbacks: 1)
        _ = detector.observe(baseline, generation: 1, nowMs: 0, expectsPlayback: true)
        expect(
            detector.observe(
                playbackSnapshot(callbacks: 2),
                generation: 1,
                nowMs: 30,
                expectsPlayback: true
            ) == nil,
            "sleep or a suspended watchdog must start a fresh grace period"
        )
    }

    private static func testPlaybackStallDetectorRecoversOnlyOncePerPlayRequest() {
        var detector = PlaybackStallDetector(stallThresholdMs: 10)
        let baseline = playbackSnapshot(callbacks: 1)
        let stalled = playbackSnapshot(waiters: 1, callbacks: 2)
        _ = detector.observe(baseline, generation: 1, nowMs: 0, expectsPlayback: true)
        expect(
            detector.observe(
                stalled, generation: 1, nowMs: 10, expectsPlayback: true
            ) != nil,
            "the first stall must request local recovery"
        )
        expect(
            detector.observe(
                stalled, generation: 1, nowMs: 20, expectsPlayback: true
            ) == nil,
            "one play request must never create a recovery storm"
        )

        let replacement = playbackSnapshot(request: 2, callbacks: 2)
        _ = detector.observe(replacement, generation: 1, nowMs: 30, expectsPlayback: true)
        expect(
            detector.observe(
                playbackSnapshot(request: 2, waiters: 1, callbacks: 3),
                generation: 1,
                nowMs: 40,
                expectsPlayback: true
            ) != nil,
            "a new play request must receive an independent recovery budget"
        )

        _ = detector.observe(baseline, generation: 2, nowMs: 50, expectsPlayback: true)
        expect(
            detector.observe(
                stalled, generation: 2, nowMs: 60, expectsPlayback: true
            ) != nil,
            "a replacement generation must not inherit an old recovery budget"
        )
    }

    private static func testPlaybackStallRecoveryRequiresActualProgress() {
        let baseline = playbackSnapshot(rendered: 10, position: 42_000)
        expect(
            !PlaybackStallDetector.recoveryMadeProgress(
                from: baseline,
                to: playbackSnapshot(rendered: 10, position: 42_000)
            ),
            "an accepted seek without audio or decoder progress must escalate"
        )
        expect(
            PlaybackStallDetector.recoveryMadeProgress(
                from: baseline,
                to: playbackSnapshot(rendered: 11, position: 42_000)
            ),
            "rendered PCM must confirm local recovery"
        )
        expect(
            !PlaybackStallDetector.recoveryMadeProgress(
                from: baseline,
                to: playbackSnapshot(rendered: 10, position: 42_001)
            ),
            "decoder progress without rendered PCM must still escalate"
        )
    }

    // MARK: - PendingPlayIntent

    private static func testPendingPlayIntentReplaysOnlyOnce() {
        var intent = pendingPlayIntent()
        expect(
            intent.markReplayedIfEligible(
                accountEpoch: 7,
                previousPlayRequestID: 20
            ),
            "an unconfirmed current intent must receive one replay"
        )
        expect(
            !intent.markReplayedIfEligible(
                accountEpoch: 7,
                previousPlayRequestID: 21
            ),
            "an intent must never replay more than once"
        )
    }

    private static func testPendingPlayIntentExpires() {
        let createdAt = ContinuousClock.now
        var intent = pendingPlayIntent(createdAt: createdAt)
        expect(
            !intent.markReplayedIfEligible(
                accountEpoch: 7,
                previousPlayRequestID: 20,
                now: createdAt.advanced(by: .seconds(61))
            ),
            "a stale intent must not replay after its 60-second lifetime"
        )
    }

    private static func testPendingPlayIntentRejectsAnotherAccountEpoch() {
        var intent = pendingPlayIntent()
        expect(
            !intent.markReplayedIfEligible(
                accountEpoch: 8,
                previousPlayRequestID: 20
            ),
            "sign-out or account replacement must fence a late replay"
        )
    }

    private static func testPendingPlayIntentKeepsOriginalContextCall() {
        let intent = pendingPlayIntent()
        expect(
            intent.call == .context(uri: "spotify:playlist:abc", index: 12),
            "replay must retain the original server-resolved context and index"
        )
        expect(
            intent.trackURI == "spotify:track:def",
            "the best-effort confirmation URI must survive reconnect"
        )

        let restored = PendingPlayIntent(
            call: .trackAt(uri: "spotify:track:def", positionMs: 42_000),
            trackURI: "spotify:track:def",
            accountEpoch: 7,
            previousPlayRequestID: 10
        )
        expect(
            restored.call == .trackAt(uri: "spotify:track:def", positionMs: 42_000),
            "restored playback must retain its URI and position for one replay"
        )
    }

    private static func testPendingPlayIntentMatchesPlayingEvent() {
        let trackIntent = pendingPlayIntent()
        expect(
            trackIntent.isConfirmed(
                byPlayingURI: "spotify:track:def",
                playRequestID: 11
            ),
            "Playing for the requested track must confirm the pending intent"
        )
        expect(
            !trackIntent.isConfirmed(
                byPlayingURI: "spotify:track:old",
                playRequestID: 11
            ),
            "Playing from an older stream must not confirm a different requested track"
        )
        expect(
            !trackIntent.isConfirmed(
                byPlayingURI: "spotify:track:def",
                playRequestID: 10
            ),
            "a delayed Playing event from the previous request must not confirm a new intent"
        )

        let albumIntent = PendingPlayIntent(
            call: .context(uri: "spotify:album:abc", index: 0),
            trackURI: nil,
            accountEpoch: 7,
            previousPlayRequestID: 10
        )
        expect(
            !albumIntent.isConfirmed(
                byPlayingURI: "spotify:track:old",
                playRequestID: 10
            ),
            "an unknown context track must reject Playing from the previous request"
        )
        expect(
            albumIntent.isConfirmed(
                byPlayingURI: "spotify:track:any",
                playRequestID: 11
            ),
            "an unknown context track must accept Playing from its new request"
        )
    }

    private static func testPendingPlayIntentIdentifiesPreviousRequestEvents() {
        let intent = pendingPlayIntent()
        expect(
            intent.isEventFromPreviousRequest(playRequestID: 10),
            "a terminal event from the previous request must not cancel the pending intent"
        )
        expect(
            !intent.isEventFromPreviousRequest(playRequestID: 11),
            "a terminal event from the new request must be handled normally"
        )
    }

    private static func pendingPlayIntent(
        createdAt: ContinuousClock.Instant = .now
    ) -> PendingPlayIntent {
        PendingPlayIntent(
            call: .context(uri: "spotify:playlist:abc", index: 12),
            trackURI: "spotify:track:def",
            accountEpoch: 7,
            previousPlayRequestID: 10,
            createdAt: createdAt
        )
    }

    // MARK: - PlaybackReconnectPolicy

    private static func testReconnectDefersWhileAudioIsProgressing() {
        expect(
            PlaybackReconnectPolicy.shouldDeferRebuild(
                isPlaying: true,
                isBuffering: false,
                hasPendingPlay: false
            ),
            "a control-plane outage must not rebuild a player with progressing audio"
        )
    }

    private static func testReconnectDoesNotDeferWhenPlaybackNeedsControlPlane() {
        for state in [
            (isPlaying: false, isBuffering: false, hasPendingPlay: false),
            (isPlaying: true, isBuffering: true, hasPendingPlay: false),
            (isPlaying: true, isBuffering: false, hasPendingPlay: true),
        ] {
            expect(
                !PlaybackReconnectPolicy.shouldDeferRebuild(
                    isPlaying: state.isPlaying,
                    isBuffering: state.isBuffering,
                    hasPendingPlay: state.hasPendingPlay
                ),
                "paused, buffering, and pending-play states must rebuild the control plane"
            )
        }
    }

    // MARK: - Personalized home (SpotifyClient decode + HomeFeed)

    private static func trackJSON(
        id: String,
        name: String = "Track",
        albumID: String? = "al1",
        albumName: String = "Album One",
        artistID: String = "ar1",
        artistName: String = "Artist One",
        playable: Bool = true
    ) -> String {
        """
        {
          "id": "\(id)",
          "uri": "spotify:track:\(id)",
          "name": "\(name)",
          "duration_ms": 200000,
          "is_playable": \(playable ? "true" : "false"),
          "artists": [{"id": "\(artistID)", "name": "\(artistName)"}],
          "album": {"id": \(albumID.map { "\"" + $0 + "\"" } ?? "null"), "name": "\(albumName)", "images": [{"url": "https://i.scdn.co/image/al1"}]}
        }
        """
    }

    private static func decodeJSON(_ json: String) -> Data {
        Data(json.utf8)
    }

    private static func testRecentlyPlayedDecodesTracksAndContexts() {
        let json = """
        {
          "items": [
            {
              "track": \(trackJSON(id: "t1")),
              "played_at": "2026-08-20T10:00:00Z",
              "context": {"uri": "spotify:album:al1", "type": "album"}
            },
            {
              "track": \(trackJSON(id: "t2", name: "Two", albumID: "al2", albumName: "Album Two")),
              "played_at": "2026-08-20T09:00:00Z",
              "context": {"uri": "spotify:playlist:pl9", "type": "playlist"}
            }
          ],
          "cursors": {"after": "x"}, "limit": 20, "href": "https://api.spotify.com/v1/me/player/recently-played"
        }
        """
        let items = try! SpotifyClient.decodeRecentlyPlayed(decodeJSON(json))
        expect(items.count == 2, "recently-played decodes both items")
        expect(items[0].track.id == "t1" && items[0].track.albumId == "al1", "first item carries the track")
        expect(items[0].contextURI == "spotify:album:al1" && items[0].contextType == "album", "album context decodes")
        expect(items[1].contextType == "playlist" && items[1].contextURI == "spotify:playlist:pl9", "playlist context decodes")
        expect(items[1].track.albumName == "Album Two", "track album name decodes")
    }

    private static func testRecentlyPlayedSkipsUnplayableAndContextlessAlbumEntries() {
        let json = """
        {"items": [
          {"track": \(trackJSON(id: "t1", playable: false)), "context": null},
          {"track": \(trackJSON(id: "t2", albumID: "__none__")), "context": {"uri": "spotify:album:al1", "type": "album"}}
        ]}
        """
            .replacingOccurrences(of: "\"__none__\"", with: "null")
        let items = try! SpotifyClient.decodeRecentlyPlayed(decodeJSON(json))
        expect(items.count == 1 && items[0].track.id == "t2", "unplayable entries are dropped at decode time")
        expect(items[0].track.albumId == nil, "tracks without an album decode with nil albumId")
    }

    private static func testHomePagesRequireItemsArray() {
        let tracks = try! SpotifyClient.decodeTopTracks(decodeJSON(
            "{\"items\": [\(trackJSON(id: "t1")), \(trackJSON(id: "t2"))], \"total\": 2, \"limit\": 10}"
        ))
        expect(tracks.map(\.id) == ["t1", "t2"], "top tracks decode in order")

        let artists = try! SpotifyClient.decodeTopArtists(decodeJSON("""
        {"items": [{"id": "a1", "name": "Artist", "images": [{"url": "https://i.scdn.co/image/a1"}]}], "total": 1}
        """))
        expect(artists.count == 1 && artists[0].name == "Artist" && artists[0].artworkURL != nil, "top artists decode with portraits")

        let emptyTracks = try! SpotifyClient.decodeTopTracks(decodeJSON("{\"items\": []}"))
        let emptyArtists = try! SpotifyClient.decodeTopArtists(decodeJSON("{\"items\": []}"))
        let emptyHistory = try! SpotifyClient.decodeRecentlyPlayed(decodeJSON("{\"items\": []}"))
        expect(emptyTracks.isEmpty && emptyArtists.isEmpty && emptyHistory.isEmpty, "explicitly empty item pages decode to empty arrays")

        expectDecodeFailure("top tracks without items must fail") {
            _ = try SpotifyClient.decodeTopTracks(decodeJSON("{}"))
        }
        expectDecodeFailure("top artists without items must fail") {
            _ = try SpotifyClient.decodeTopArtists(decodeJSON("{}"))
        }
        expectDecodeFailure("recent history without items must fail") {
            _ = try SpotifyClient.decodeRecentlyPlayed(decodeJSON("{}"))
        }
    }

    private static func testTopTimeRangeAndLimitEncoding() {
        expect(SpotifyClient.TopTimeRange.shortTerm.rawValue == "short_term", "short-term window encodes")
        expect(SpotifyClient.TopTimeRange.mediumTerm.rawValue == "medium_term", "medium-term window encodes")
        expect(SpotifyClient.TopTimeRange.longTerm.rawValue == "long_term", "long-term window encodes")
        expect(SpotifyClient.clampedLimit(50) == 50 && SpotifyClient.clampedLimit(20) == 20, "in-range limits pass through")
        expect(SpotifyClient.clampedLimit(100) == 50, "limits clamp to the endpoint max")
        expect(SpotifyClient.clampedLimit(0) == 1, "zero/negative limits clamp to 1")
    }

    private static func historyTrack(id: String, albumID: String?, artists: [SpotifyClient.Artist]) -> SpotifyClient.Track {
        SpotifyClient.Track(
            id: id, uri: "spotify:track:\(id)", name: "Track \(id)", durationMs: 1000,
            artists: artists, artistDisplayText: nil, albumName: albumID != nil ? "Album \(id)" : "",
            albumId: albumID, artworkURL: nil
        )
    }

    private static func testRecentAlbumContextUsesTrackAlbum() {
        let item = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t1", albumID: "al1", artists: [.init(id: "ar1", name: "A", artworkURL: nil)]),
            contextURI: "spotify:album:al1",
            contextType: "album"
        )
        let card = HomeFeed.card(for: item, playlists: [])
        expect(card?.kind == .album && card?.refID == "al1", "album context maps to an album card")
        expect(card?.title == "Album t1", "album card title comes from the track's album")

        let noContext = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t2", albumID: "al2", artists: []),
            contextURI: nil, contextType: nil
        )
        expect(HomeFeed.card(for: noContext, playlists: [])?.kind == .album, "missing context falls back to the track's album")
    }

    private static func testPlaylistContextResolvesAgainstUserPlaylists() {
        let item = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t1", albumID: "al1", artists: []),
            contextURI: "spotify:playlist:pl1",
            contextType: "playlist"
        )
        let playlists = [SpotifyClient.PlaylistInfo(id: "pl1", name: "My Mix", trackCount: 30, artworkURL: nil)]
        let card = HomeFeed.card(for: item, playlists: playlists)
        expect(card?.kind == .playlist && card?.refID == "pl1", "playlist context maps to a playlist card")
        expect(card?.title == "My Mix", "playlist card title resolves from the user's playlist list")
    }

    private static func testUnknownPlaylistContextFallsBackToTrackAlbum() {
        // Editorial mixes (Daily Mix, Discover Weekly…) appear in play
        // history but never in /v1/me/playlists — no name is available.
        let item = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t1", albumID: "al1", artists: []),
            contextURI: "spotify:playlist:37i9dQZF1Eabc",
            contextType: "playlist"
        )
        let card = HomeFeed.card(for: item, playlists: [])
        expect(card?.kind == .album && card?.refID == "al1", "unknown playlist context falls back to the track album")
    }

    private static func testArtistContextPrefersMatchingTrackArtist() {
        let artists = [
            SpotifyClient.Artist(id: "ar1", name: "Featured", artworkURL: nil),
            SpotifyClient.Artist(id: "ar2", name: "Main", artworkURL: nil),
        ]
        let matching = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t1", albumID: "al1", artists: artists),
            contextURI: "spotify:artist:ar2",
            contextType: "artist"
        )
        let card = HomeFeed.card(for: matching, playlists: [])
        expect(card?.kind == .artist && card?.refID == "ar2" && card?.title == "Main", "artist context resolves the matching track artist")

        let mismatch = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t2", albumID: "al2", artists: artists),
            contextURI: "spotify:artist:zz",
            contextType: "artist"
        )
        let fallback = HomeFeed.card(for: mismatch, playlists: [])
        expect(fallback?.kind == .album && fallback?.refID == "al2", "unmatched artist context falls back to the track album")

        let noArtists = SpotifyClient.PlayHistoryItem(
            track: historyTrack(id: "t3", albumID: "al3", artists: []),
            contextURI: "spotify:artist:ar9",
            contextType: "artist"
        )
        expect(HomeFeed.card(for: noArtists, playlists: [])?.kind == .album, "artist context without track artists falls back to the album")
    }

    private static func testRecentCardsDedupeAndCap() {
        func item(_ id: String, albumID: String?) -> SpotifyClient.PlayHistoryItem {
            SpotifyClient.PlayHistoryItem(
                track: historyTrack(id: id, albumID: albumID, artists: []),
                contextURI: nil, contextType: nil
            )
        }
        let history = [
            item("t1", albumID: "al1"),
            item("t2", albumID: "al1"), // same album → deduped
            item("t3", albumID: "al2"),
            item("t4", albumID: nil), // episodes/local tracks → no card
            item("t5", albumID: "al3"),
        ]
        let cards = HomeFeed.recentlyPlayedCards(from: history, playlists: [], limit: 2)
        expect(cards.map(\.id) == ["album:al1", "album:al2"], "cards dedupe by context and cap at the limit")

        let all = HomeFeed.recentlyPlayedCards(from: history, playlists: [])
        expect(all.count == 3, "cap-free derivation keeps every distinct context")
    }

    private static func testContextRefIDRejectsMismatchedKind() {
        expect(HomeFeed.contextRefID("spotify:album:al1", kind: .album) == "al1", "matching prefix extracts the id")
        expect(HomeFeed.contextRefID("spotify:playlist:pl1", kind: .album) == nil, "mismatched kind prefix is rejected")
        expect(HomeFeed.contextRefID(nil, kind: .artist) == nil, "missing uri is rejected")
        expect(HomeFeed.contextRefID("spotify:artist:", kind: .artist) == nil, "empty id is rejected")
        expect(HomeFeed.contextKind("album") == .album && HomeFeed.contextKind("playlist") == .playlist, "known context types map")
        expect(HomeFeed.contextKind("show") == nil && HomeFeed.contextKind(nil) == nil, "unknown context types map to nothing")
    }

    // MARK: - Playlist writes (M4.5)

    private static func playlist(
        _ id: String,
        name: String = "Playlist",
        count: Int = 0,
        owner: String? = "user1"
    ) -> SpotifyClient.PlaylistInfo {
        SpotifyClient.PlaylistInfo(
            id: id, name: name, trackCount: count, artworkURL: nil, ownerId: owner
        )
    }

    private static func testCreatedPlaylistDecodesWithOwnership() {
        let json = """
        {
          "id": "pl1", "name": "Road Trip", "public": false,
          "snapshot_id": "abc",
          "owner": {"id": "user1", "display_name": "Spike"},
          "tracks": {"total": 0, "href": "x"},
          "images": [{"url": "https://i.scdn.co/image/pl1"}]
        }
        """
        let info = try! SpotifyClient.decodeCreatedPlaylist(decodeJSON(json))
        expect(info.id == "pl1" && info.name == "Road Trip", "created playlist decodes id and name")
        expect(info.ownerId == "user1", "created playlist carries the owner id")
        expect(info.trackCount == 0, "a new playlist decodes with zero tracks")
        expect(info.artworkURL != nil, "created playlist decodes artwork when present")

        // Tolerant minimal payload: no owner, no tracks, no images.
        let bare = try! SpotifyClient.decodeCreatedPlaylist(
            decodeJSON(#"{"id": "pl2", "name": "Bare"}"#)
        )
        expect(
            bare.ownerId == nil && bare.trackCount == 0 && bare.artworkURL == nil,
            "owner-less minimal create responses decode with nil ownership"
        )
    }

    private static func testPlaylistSummaryPrefersItemsTotal() {
        let json = """
        {
          "id": "pl1", "name": "Current Shape",
          "items": {"total": 42},
          "tracks": {"total": 7}
        }
        """
        let info = try! SpotifyClient.decodeCreatedPlaylist(decodeJSON(json))
        expect(info.trackCount == 42, "current items.total takes precedence over deprecated tracks.total")
    }

    private static func testCreateMutationInsertsAtSidebarTop() {
        let list = [playlist("a", count: 5)]
        let created = playlist("new", name: "New", count: 0)
        let result = PlaylistLibraryMerge.apply(
            .init(serial: 1, kind: .created(created)), to: list
        )
        expect(result.map(\.id) == ["new", "a"], "a created playlist inserts at the sidebar top")

        // Re-applying the same create is idempotent.
        let newerServerRow = playlist("new", name: "New", count: 3)
        let again = PlaylistLibraryMerge.apply(
            .init(serial: 2, kind: .created(created)),
            to: [newerServerRow, list[0]]
        )
        expect(again.map(\.id) == ["new", "a"], "re-applying a create must not duplicate the row")
        expect(again[0].trackCount == 3, "a create payload must not replace a newer existing row")
    }

    private static func testStaleRefreshCannotDropCreatedPlaylist() {
        // A read started after the write may still lag and omit it.
        let mutations = [PlaylistLibraryMerge.ConfirmedMutation(
            serial: 1, kind: .created(playlist("new", name: "New"))
        )]
        let merged = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a")], mutations: mutations
        )
        expect(
            merged.playlists.map(\.id) == ["new", "a"],
            "a stale refresh must not drop a newer created playlist"
        )
        expect(
            merged.pending.count == 1,
            "the create stays pending until a snapshot visibly includes it"
        )
    }

    private static func testStaleRefreshCannotRevertAddCount() {
        // Local count is 11 after the add; the stale snapshot still says 10.
        let mutations = [PlaylistLibraryMerge.ConfirmedMutation(
            serial: 1, kind: .trackAdded(playlistID: "a", localCount: 11)
        )]
        let merged = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 10)], mutations: mutations
        )
        expect(
            merged.playlists.first { $0.id == "a" }?.trackCount == 11,
            "a stale snapshot must not pull the count back below the confirmed add"
        )
    }

    private static func testRefreshIncludingAddDoesNotDoubleCount() {
        // The snapshot's fetch happened after the write landed server-side:
        // its count already includes the add (and possibly other clients').
        let mutations = [PlaylistLibraryMerge.ConfirmedMutation(
            serial: 1, kind: .trackAdded(playlistID: "a", localCount: 11)
        )]
        let exact = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 11)], mutations: mutations
        )
        expect(
            exact.playlists.first { $0.id == "a" }?.trackCount == 11,
            "a snapshot that already includes the add must not double-count it"
        )
        expect(exact.pending.isEmpty, "a visible add retires its pending override")

        let withOthers = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 13)], mutations: mutations
        )
        expect(
            withOthers.playlists.first { $0.id == "a" }?.trackCount == 13,
            "a newer server count (add + other clients) must win"
        )
    }

    private static func testRefreshRetiresVisibleCreateWithoutReplacingSnapshot() {
        let pendingCreate = PlaylistLibraryMerge.ConfirmedMutation(
            serial: 1, kind: .created(playlist("new"))
        )
        let merged = PlaylistLibraryMerge.merge(
            snapshot: [playlist("new", count: 3), playlist("a")],
            mutations: [pendingCreate]
        )
        expect(
            merged.playlists.map(\.id) == ["new", "a"],
            "the snapshot ordering is kept for baked-in mutations"
        )
        expect(merged.playlists[0].trackCount == 3, "the snapshot row must not be replaced by the create response")
        expect(merged.pending.isEmpty, "a visible create retires after the refresh lands")
    }

    private static func testStaleProtectionExpiresToServerTruth() {
        let mutation = PlaylistLibraryMerge.ConfirmedMutation(
            serial: 1, kind: .trackAdded(playlistID: "a", localCount: 11)
        )
        let first = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 10)], mutations: [mutation]
        )
        let second = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 10)], mutations: first.pending
        )
        let third = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 10)], mutations: second.pending
        )
        expect(first.playlists[0].trackCount == 11, "the first stale snapshot keeps the confirmed count")
        expect(second.playlists[0].trackCount == 11, "the second stale snapshot keeps the confirmed count")
        expect(third.playlists[0].trackCount == 10, "bounded protection eventually yields to server truth")
        expect(third.pending.isEmpty, "an expired override retires")
    }

    private static func testCreateThenAddBeforeStaleRefreshKeepsBoth() {
        // Create + add confirm while a pre-create refresh is in flight; the
        // arriving snapshot predates both.
        let mutations = [
            PlaylistLibraryMerge.ConfirmedMutation(
                serial: 1, kind: .created(playlist("new", name: "New"))
            ),
            PlaylistLibraryMerge.ConfirmedMutation(
                serial: 2, kind: .trackAdded(playlistID: "new", localCount: 1)
            ),
        ]
        let merged = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a", count: 7)], mutations: mutations
        )
        expect(
            merged.playlists.map(\.id) == ["new", "a"],
            "the created playlist survives the stale refresh"
        )
        expect(
            merged.playlists.first { $0.id == "new" }?.trackCount == 1,
            "the confirmed add count survives the stale refresh"
        )
        expect(merged.pending.count == 2, "both mutations stay pending for the next refresh")
    }

    private static func testAddMutationSkipsMissingPlaylist() {
        // Target deleted by another client while our add was in flight —
        // server truth wins for existence; no crash, no resurrection.
        let mutations = [PlaylistLibraryMerge.ConfirmedMutation(
            serial: 1, kind: .trackAdded(playlistID: "ghost", localCount: 5)
        )]
        let merged = PlaylistLibraryMerge.merge(
            snapshot: [playlist("a")], mutations: mutations
        )
        expect(
            merged.playlists.map(\.id) == ["a"],
            "an add mutation for a playlist missing from the snapshot is skipped"
        )
        expect(merged.pending.isEmpty, "a missing target retires its add mutation")
    }

    private static func testCreateBodyCarriesExplicitEmptyDescription() {
        let data = try! SpotifyClient.encodeCreatePlaylistBody(name: "Road Trip")
        let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        expect(object["name"] as? String == "Road Trip", "create body carries the name")
        expect(
            (object["description"] as? String) == "",
            "create body must carry an explicit empty description — omitting the key makes Spotify store the literal string \"null\""
        )
        expect(object["public"] as? Bool == false, "create body defaults to a private playlist")
        expect(
            Set(object.keys) == ["name", "description", "public"],
            "create body sends exactly name/description/public"
        )
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

    private static func expectDecodeFailure(
        _ message: String,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
            exit(1)
        } catch {
            // Expected malformed payload rejection.
        }
    }
}
