import Foundation
import Testing
@testable import NanyinKit

struct ReconnectPolicyTests {
    @Test func retryDelaysGrowAndThenRepeat() {
        var policy = ReconnectPolicy()
        let delays = (0 ..< 8).map { _ in policy.attemptFailed() }
        #expect(delays == [5, 15, 60, 120, 300, 600, 600, 600])
        policy.connected()
        let next = policy.attemptFailed()
        #expect(next == 5)
    }

    @Test func dropsAreLimitedWithinTheWindow() {
        var policy = ReconnectPolicy()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0 ..< ReconnectPolicy.dropLimit {
            let allowed = policy.sessionDropped(at: start.addingTimeInterval(Double(index)))
            #expect(allowed)
            policy.connected()
        }
        let exhausted = !policy.sessionDropped(at: start.addingTimeInterval(60))
        #expect(exhausted)
        let later = policy.sessionDropped(at: start.addingTimeInterval(ReconnectPolicy.dropWindow + 1))
        #expect(later)
    }
}
