import Testing
@testable import NanyinKit

struct PKCETests {
    @Test func challengeMatchesRFC7636Example() {
        // RFC 7636, appendix B.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifiersAreUniqueAndURLSafe() {
        let a = PKCE(), b = PKCE()
        #expect(a.verifier != b.verifier)
        #expect(a.verifier.count >= 43 && a.verifier.count <= 128)
        #expect(!a.verifier.contains { "+/=".contains($0) })
    }
}
