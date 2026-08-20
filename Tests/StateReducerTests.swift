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
        testSignOutRejectsLateCredentialPersistence()
        print("State reducer tests passed")
    }

    private static func testSingleFailedLikeRollsBack() {
        for initiallyLiked in [false, true] {
            var mutation = LikeMutation(
                confirmedLiked: initiallyLiked,
                desiredLiked: !initiallyLiked
            )
            let attempt = mutation.nextAttempt()
            expect(
                mutation.resolve(attempt, succeeded: false) == .rollback(to: initiallyLiked),
                "single failed write must roll back to the confirmed state"
            )
        }
    }

    private static func testObsoleteFailureAfterToggleBackNeedsNoSecondWrite() {
        for initiallyLiked in [false, true] {
            var mutation = LikeMutation(
                confirmedLiked: initiallyLiked,
                desiredLiked: !initiallyLiked
            )
            let obsoleteAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallyLiked)
            expect(
                mutation.resolve(obsoleteAttempt, succeeded: false)
                    == .settled(maskServerLag: false),
                "an obsolete failure must settle when latest intent already matches the server"
            )
        }
    }

    private static func testLatestFailureRollsBackToSuccessfulOlderWrite() {
        for initiallyLiked in [false, true] {
            var mutation = LikeMutation(
                confirmedLiked: initiallyLiked,
                desiredLiked: !initiallyLiked
            )
            let firstAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallyLiked)
            expect(
                mutation.resolve(firstAttempt, succeeded: true) == .persistLatest,
                "a newer intent must be persisted after an older success"
            )

            let latestAttempt = mutation.nextAttempt()
            expect(
                mutation.resolve(latestAttempt, succeeded: false)
                    == .rollback(to: !initiallyLiked),
                "latest failure must roll back to the last successful write"
            )
        }
    }

    private static func testTwoSuccessfulWritesSettleOnLatestIntent() {
        for initiallyLiked in [false, true] {
            var mutation = LikeMutation(
                confirmedLiked: initiallyLiked,
                desiredLiked: !initiallyLiked
            )
            let firstAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallyLiked)
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
                mutation.confirmedLiked == initiallyLiked,
                "latest successful state must be confirmed"
            )
        }
    }

    private static func testRepeatedIntentAfterTwoFailuresRollsBackToServer() {
        for initiallyLiked in [false, true] {
            var mutation = LikeMutation(
                confirmedLiked: initiallyLiked,
                desiredLiked: !initiallyLiked
            )
            let obsoleteAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallyLiked)
            mutation.setDesired(!initiallyLiked)
            expect(
                mutation.resolve(obsoleteAttempt, succeeded: false) == .persistLatest,
                "the repeated latest intent must survive an obsolete failure"
            )

            let latestAttempt = mutation.nextAttempt()
            expect(
                mutation.resolve(latestAttempt, succeeded: false)
                    == .rollback(to: initiallyLiked),
                "two failed writes must return to the original server state"
            )
        }
    }

    private static func testRepeatedIntentAfterFailureThenSuccessSettles() {
        for initiallyLiked in [false, true] {
            var mutation = LikeMutation(
                confirmedLiked: initiallyLiked,
                desiredLiked: !initiallyLiked
            )
            let obsoleteAttempt = mutation.nextAttempt()
            mutation.setDesired(initiallyLiked)
            mutation.setDesired(!initiallyLiked)
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
                mutation.confirmedLiked == !initiallyLiked,
                "the successful retry must become the confirmed state"
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
    }

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
