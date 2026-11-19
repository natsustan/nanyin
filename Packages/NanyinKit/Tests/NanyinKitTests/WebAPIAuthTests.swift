import Foundation
import Testing
@testable import NanyinKit

struct WebAPIAuthTests {
    private func token(_ access: String, refresh: String = "r1", expiresIn: TimeInterval) -> OAuthToken {
        OAuthToken(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expiresIn), scope: "", clientID: "c")
    }

    @Test func freshTokenIsNotRenewed() async throws {
        let calls = Counter()
        let auth = WebAPIAuth(store: MemorySecretStore()) { _ in
            calls.increment()
            throw OAuthError.grantRevoked
        }
        try await auth.signIn(with: token("a1", expiresIn: 3600))
        #expect(try await auth.accessToken() == "a1")
        #expect(calls.value == 0)
    }

    @Test func concurrentCallersShareOneRenewalAndTheRotatedTokenIsSaved() async throws {
        let calls = Counter()
        let store = MemorySecretStore()
        let auth = WebAPIAuth(store: store) { old in
            calls.increment()
            try await Task.sleep(for: .milliseconds(50))
            return OAuthToken(accessToken: "a2", refreshToken: "r2", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: old.clientID)
        }
        try await auth.signIn(with: token("a1", expiresIn: 10))
        async let first = auth.accessToken()
        async let second = auth.accessToken()
        #expect(try await [first, second] == ["a2", "a2"])
        #expect(calls.value == 1)
        #expect(try store.readValue(OAuthToken.self, WebAPIAuth.tokenKey)?.refreshToken == "r2")
    }

    @Test func rejectionOfAnOlderTokenDoesNotRenewAgain() async throws {
        let calls = Counter()
        let auth = WebAPIAuth(store: MemorySecretStore()) { _ in
            calls.increment()
            return OAuthToken(accessToken: "a2", refreshToken: "r2", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: "c")
        }
        try await auth.signIn(with: token("a1", expiresIn: 3600))
        #expect(try await auth.tokenAfterRejection(of: "a1") == "a2")
        #expect(try await auth.tokenAfterRejection(of: "a1") == "a2")
        #expect(calls.value == 1)
    }

    @Test func signOutDuringRenewalDiscardsTheResult() async throws {
        let store = MemorySecretStore()
        let auth = WebAPIAuth(store: store) { _ in
            try await Task.sleep(for: .milliseconds(100))
            return OAuthToken(accessToken: "a2", refreshToken: "r2", expiresAt: .now.addingTimeInterval(3600), scope: "", clientID: "c")
        }
        try await auth.signIn(with: token("a1", expiresIn: 10))
        let renewed = Task { try await auth.accessToken() }
        try await Task.sleep(for: .milliseconds(20))
        await auth.signOut()
        await #expect(throws: (any Error).self) { _ = try await renewed.value }
        #expect(try store.read(WebAPIAuth.tokenKey) == nil)
        #expect(await auth.isSignedIn == false)
    }

    @Test func revokedGrantSignsOut() async throws {
        let auth = WebAPIAuth(store: MemorySecretStore()) { _ in throw OAuthError.grantRevoked }
        try await auth.signIn(with: token("a1", expiresIn: 10))
        await #expect(throws: OAuthError.grantRevoked) { _ = try await auth.accessToken() }
        #expect(await auth.isSignedIn == false)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
