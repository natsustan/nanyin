import Foundation
import Testing
@testable import NanyinKit

struct ProxyConfigTests {
    @Test func systemAndOffModesValidateWithoutHost() throws {
        #expect(try ProxySettings(mode: .system).validatedEndpoint() == nil)
        #expect(try ProxySettings(mode: .off).validatedEndpoint() == nil)
        #expect(ProxySettings(mode: .system).playbackProxyURL() == nil)
        #expect(ProxySettings(mode: .off).playbackProxyURL() == nil)
    }

    @Test func httpProxyProducesPlaybackURLOnlyWithoutCredentials() throws {
        let plain = ProxySettings(mode: .http, host: "127.0.0.1", port: "7890")
        let endpoint = try #require(try plain.validatedEndpoint())
        #expect(endpoint.host == "127.0.0.1")
        #expect(endpoint.port == 7890)
        #expect(endpoint.playbackProxyURL == "http://127.0.0.1:7890")

        let authed = ProxySettings(mode: .http, host: "127.0.0.1", port: "7890", username: "alice")
        #expect(try authed.validatedEndpoint(password: "secret")?.playbackProxyURL == nil)

        let socks = ProxySettings(mode: .socks5, host: "127.0.0.1", port: "1080")
        #expect(try socks.validatedEndpoint()?.playbackProxyURL == nil)
    }

    @Test func wrapsIPv6HostForPlaybackURL() throws {
        let ipv6 = ProxySettings(mode: .http, host: "[::1]", port: "8080")
        let endpoint = try #require(try ipv6.validatedEndpoint())
        #expect(endpoint.host == "::1")
        #expect(endpoint.playbackProxyURL == "http://[::1]:8080")
    }

    @Test func rejectsMalformedManualProxyAndBlocksTransport() throws {
        #expect(throws: ProxyError.self) {
            _ = try ProxySettings(mode: .http, host: "", port: "7890").validatedEndpoint()
        }
        #expect(throws: ProxyError.self) {
            _ = try ProxySettings(mode: .http, host: "http://127.0.0.1", port: "7890").validatedEndpoint()
        }
        #expect(throws: ProxyError.self) {
            _ = try ProxySettings(mode: .http, host: "127.0.0.1:7890", port: "7890").validatedEndpoint()
        }
        #expect(throws: ProxyError.self) {
            _ = try ProxySettings(mode: .http, host: "127.0.0.1", port: "0").validatedEndpoint()
        }
        #expect(throws: ProxyError.self) {
            _ = try ProxySettings(mode: .http, host: "127.0.0.1", port: "abc").validatedEndpoint()
        }
        #expect(throws: ProxyError.self) {
            _ = try ProxySettings(mode: .socks5, host: "127.0.0.1", port: "1080").validatedEndpoint(password: "pw")
        }

        let transport = HTTPTransport()
        // At startup (blockOnFailure: true), an invalid saved config blocks requests.
        #expect(throws: ProxyError.self) {
            try transport.apply(ProxySettings(mode: .http, host: "", port: "7890"), blockOnFailure: true)
        }
        #expect(throws: ProxyError.self) {
            _ = try transport.currentSession()
        }

        // Recovering with a valid config restores the session.
        try transport.apply(ProxySettings(mode: .system))
        let working = try transport.currentSession()

        // A rejected live edit leaves the existing working session intact.
        #expect(throws: ProxyError.self) {
            try transport.apply(ProxySettings(mode: .http, host: "", port: "7890"))
        }
        #expect(try transport.currentSession() === working)
    }
}
