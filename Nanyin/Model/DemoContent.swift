#if DEBUG
import Foundation
import NanyinKit

/// Made-up content for looking at the interface without a Spotify account
/// or any network traffic: `NANYIN_DEMO=1 script/build_and_run.sh`.
@MainActor
enum DemoContent {
    static func install(in app: AppModel) {
        app.account.showDemo(decode(#"{"id":"demo","display_name":"rasmus","product":"premium"}"#))
        app.session.showDemoReady()
        let rows = tracks.enumerated().map { index, track in
            TrackRow(
                index: index, uri: "spotify:track:demo\(index)", name: track.0,
                artists: [.init(name: track.1, uri: nil)], album: track.2, durationMs: track.3,
                popularity: 90 - index * 4, added: Date(timeIntervalSince1970: 1_270_000_000 + Double(index) * 86_400 * 9))
        }
        app.stars.learn(rows.map(\.uri), starred: false)
        app.stars.learn(rows.filter { $0.id % 3 == 0 }.map(\.uri), starred: true)
        let list = TrackList(rows: rows, contextURI: "spotify:user:demo:collection")
        let playlists: [Playlist] = playlistNames.enumerated().map { index, name in
            decode(#"{"id":"p\#(index)","name":"\#(name)","uri":"spotify:playlist:p\#(index)","owner":{"id":"demo"}}"#)
        }
        app.library.showDemo(
            playlists: playlists,
            pages: [.whatsNew: .tracks(list), .likedSongs: .tracks(list)])
        app.player.showDemo(
            CoreTrack(
                uri: rows[4].uri, name: rows[4].name, artists: [.init(uri: "", name: rows[4].artistNames)],
                album: rows[4].album, albumURI: nil, coverURL: nil, durationMs: 206_000, explicit: false),
            positionMs: 112_000,
            upNext: TrackList(rows: Array(rows.dropFirst(5))))
    }

    private static func decode<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static let playlistNames = [
        "You!", "Loud", "Make Me Happy", "joyful evening", "Sleep", "Jogg", "DFA remixes", "Noncollective",
        "Sunday Morning", "Road Trip 2010", "Indie Gems",
    ]

    private static let tracks: [(String, String, String, Int)] = [
        ("Paper Lanterns", "The Northern Lights", "Harbour", 215_000),
        ("Glass Houses", "Mira Kell", "Static Bloom", 198_000),
        ("Coastline", "The Northern Lights", "Harbour", 241_000),
        ("Velvet Hours", "Oslo Dawn", "Velvet Hours", 187_000),
        ("Everywhere", "Empire Dogs", "Love Attack!!!", 206_000),
        ("Night Music", "Linnea Saar", "Night Music", 233_000),
        ("The Terrace", "Kingfisher Lane", "Blue Afternoon", 176_000),
        ("Stage Invader", "Bright Machines", "Signal", 254_000),
        ("Hold Me Closer", "Mira Kell", "Static Bloom", 202_000),
        ("Waterfall", "Oslo Dawn", "Velvet Hours", 228_000),
        ("Hot & Wrong", "Bright Machines", "Signal", 191_000),
        ("Baby I'm Amazed", "Kingfisher Lane", "Blue Afternoon", 219_000),
        ("Stereo Love", "Edward Grey", "Summer Radio", 245_000),
        ("Fight For This Love", "Cheryl Vale", "Messy Little Raindrops", 223_000),
    ]
}
#endif
