import Foundation
import Testing
@testable import NanyinKit

struct SpotifyOAuthTests {
    @Test func playbackGrantAsksOnlyForStreamingAndAlwaysShowsConsent() {
        let url = OAuthGrant.playback.authorizeURL(pkce: PKCE()).absoluteString
        #expect(url.contains("client_id=65b708073fc0480ea92a077233ca87bd"))
        #expect(url.contains("scope=streaming&"))
        #expect(url.contains("show_dialog=true"))
        #expect(url.contains("127.0.0.1:8898"))
    }

    @Test func webGrantUsesTheListenersClientID() {
        let grant = OAuthGrant.webAPI(clientID: " 0123456789abcdef0123456789abcdef \n")
        #expect(grant.clientID == "0123456789abcdef0123456789abcdef")
        #expect(grant.redirectURI == "http://127.0.0.1:8989/login")
        #expect(!grant.authorizeURL(pkce: PKCE()).absoluteString.contains("show_dialog"))
    }

    @Test func clientIDShape() {
        #expect(OAuthGrant.looksLikeClientID("0123456789abcdef0123456789ABCDEF"))
        #expect(!OAuthGrant.looksLikeClientID("0123456789abcdef"))
        #expect(!OAuthGrant.looksLikeClientID("0123456789abcdef0123456789abcdeg"))
    }

    @Test func classifiesTokenErrors() {
        let body = { (error: String) in Data(#"{"error":"\#(error)"}"#.utf8) }
        #expect(SpotifyOAuth.error(status: 400, body: body("invalid_grant")) == .grantRevoked)
        #expect(SpotifyOAuth.error(status: 400, body: body("invalid_client")) == .unknownClient)
        #expect(SpotifyOAuth.error(status: 500, body: Data()) == .http(500, ""))
    }

    @Test func formEncodingEscapesReservedCharacters() {
        #expect(SpotifyOAuth.formEncode(["b": "x y", "a": "1+2&3=4"]) == "a=1%2B2%263%3D4&b=x%20y")
    }

    @Test func freshnessKeepsAMargin() {
        let token = OAuthToken(accessToken: "a", refreshToken: nil, expiresAt: .now.addingTimeInterval(60), scope: "", clientID: "c")
        #expect(!token.isFresh())
    }
}
