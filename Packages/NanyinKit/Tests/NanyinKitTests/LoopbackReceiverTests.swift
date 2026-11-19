import Foundation
import Testing
@testable import NanyinKit

struct LoopbackReceiverTests {
    @Test func parsesRequestTarget() {
        let request = Data("GET /login?code=abc&state=s HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        #expect(LoopbackReceiver.requestTarget(in: request) == "/login?code=abc&state=s")
        #expect(LoopbackReceiver.requestTarget(in: Data("POST / HTTP/1.1\r\n".utf8)) == nil)
    }

    @Test func receivesTheRedirectAndIgnoresOtherPaths() async throws {
        let port: UInt16 = 38_989
        let receiver = try await LoopbackReceiver.start(port: port, path: "/login")
        async let items = receiver.callback()
        let favicon = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        #expect((favicon.1 as? HTTPURLResponse)?.statusCode == 404)
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/login?code=c1&state=s1")!)
        let received = try await items
        #expect(received.first { $0.name == "code" }?.value == "c1")
    }

    @Test func secondReceiverOnTheSamePortFails() async throws {
        let port: UInt16 = 38_990
        let first = try await LoopbackReceiver.start(port: port, path: "/login")
        defer { first.cancel() }
        await #expect(throws: LoopbackReceiver.Failure.self) {
            _ = try await LoopbackReceiver.start(port: port, path: "/login")
        }
    }
}
