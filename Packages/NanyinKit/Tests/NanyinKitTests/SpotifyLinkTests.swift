import Foundation
import Testing
@testable import NanyinKit

@Suite("SpotifyLink")
struct SpotifyLinkTests {
    @Test func parsesURIs() {
        #expect(SpotifyLink.parse("spotify:track:4uLU6hMCjMI75M1A2tKUQC") == .track(id: "4uLU6hMCjMI75M1A2tKUQC"))
        #expect(SpotifyLink.parse("spotify:album:1DFixLWuPkv3KT3TnV35m3") == .album(id: "1DFixLWuPkv3KT3TnV35m3"))
        #expect(SpotifyLink.parse("spotify:artist:0OdUWJ0sBjDrqHygGUXeCF") == .artist(id: "0OdUWJ0sBjDrqHygGUXeCF"))
        #expect(SpotifyLink.parse("spotify:playlist:37i9dQZF1DXcBWIGoYBM5M") == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M"))
        #expect(SpotifyLink.parse("spotify:user:spotify:playlist:37i9dQZF1DXcBWIGoYBM5M") == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M"))
    }

    @Test func parsesWebURLs() {
        #expect(
            SpotifyLink.parse("https://open.spotify.com/album/1DFixLWuPkv3KT3TnV35m3?si=abcdef123")
                == .album(id: "1DFixLWuPkv3KT3TnV35m3")
        )
        #expect(
            SpotifyLink.parse("https://open.spotify.com/intl-ja/track/4uLU6hMCjMI75M1A2tKUQC?si=xyz")
                == .track(id: "4uLU6hMCjMI75M1A2tKUQC")
        )
        #expect(
            SpotifyLink.parse("open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")
                == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M")
        )
        #expect(
            SpotifyLink.parse("https://play.spotify.com/user/alice/playlist/37i9dQZF1DXcBWIGoYBM5M")
                == .playlist(id: "37i9dQZF1DXcBWIGoYBM5M")
        )
    }

    @Test func rejectsRegularQueriesAndUnsupportedURLs() {
        #expect(SpotifyLink.parse("daft punk") == nil)
        #expect(SpotifyLink.parse("https://example.com/album/123") == nil)
        #expect(SpotifyLink.parse("https://open.spotify.com/episode/12345") == nil)
        #expect(SpotifyLink.parse("spotify:show:12345") == nil)
        #expect(SpotifyLink.parse("spotify:track:bad-id!") == nil)
    }

    @Test func decodesSearchResultsWithNullPlaylistEntries() throws {
        let json = """
        {
          "playlists": {
            "items": [
              null,
              {
                "id": "pl1",
                "name": "Late Night",
                "uri": "spotify:playlist:pl1",
                "owner": { "id": "u1", "display_name": "Alice" }
              }
            ],
            "total": 2,
            "next": null
          }
        }
        """
        let decoded = try JSONDecoder().decode(SearchResults.self, from: Data(json.utf8))
        #expect(decoded.compactPlaylists.count == 1)
        #expect(decoded.compactPlaylists.first?.id == "pl1")
        #expect(decoded.compactPlaylists.first?.name == "Late Night")
    }
}
