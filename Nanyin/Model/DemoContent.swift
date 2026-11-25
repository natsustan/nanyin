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
        let demoReleases: [AlbumSummary] = [
            decode(#"{"id":"a1","name":"Harbour","uri":"spotify:album:a1","album_type":"album","artists":[{"name":"The Northern Lights"}],"release_date":"2026-10-16"}"#),
            decode(#"{"id":"a2","name":"Static Bloom","uri":"spotify:album:a2","album_type":"album","artists":[{"name":"Mira Kell"}],"release_date":"2026-10-10"}"#),
            decode(#"{"id":"a3","name":"Velvet Hours","uri":"spotify:album:a3","album_type":"single","artists":[{"name":"Oslo Dawn"}],"release_date":"2026-10-02"}"#),
            decode(#"{"id":"a4","name":"Blue Afternoon","uri":"spotify:album:a4","album_type":"album","artists":[{"name":"Kingfisher Lane"}],"release_date":"2026-09-28"}"#),
            decode(#"{"id":"a5","name":"Signal","uri":"spotify:album:a5","album_type":"album","artists":[{"name":"Bright Machines"}],"release_date":"2026-09-21"}"#),
            decode(#"{"id":"a6","name":"Night Music","uri":"spotify:album:a6","album_type":"album","artists":[{"name":"Linnea Saar"}],"release_date":"2026-09-14"}"#),
            decode(#"{"id":"a7","name":"Summer Radio","uri":"spotify:album:a7","album_type":"album","artists":[{"name":"Edward Grey"}],"release_date":"2026-09-09"}"#),
            decode(#"{"id":"a8","name":"Love Attack!!!","uri":"spotify:album:a8","album_type":"album","artists":[{"name":"Empire Dogs"}],"release_date":"2026-09-03"}"#),
            decode(#"{"id":"a9","name":"Paper Lanterns","uri":"spotify:album:a9","album_type":"single","artists":[{"name":"The Northern Lights"}],"release_date":"2026-08-26"}"#),
            decode(#"{"id":"a10","name":"Quiet Harbour","uri":"spotify:album:a10","album_type":"album","artists":[{"name":"Nordic Drift"}],"release_date":"2026-08-19"}"#),
            decode(#"{"id":"a11","name":"Silver Lining","uri":"spotify:album:a11","album_type":"album","artists":[{"name":"Klara Holm"}],"release_date":"2026-08-12"}"#),
            decode(#"{"id":"a12","name":"Midnight Ferry","uri":"spotify:album:a12","album_type":"single","artists":[{"name":"Vesterbro"}],"release_date":"2026-08-04"}"#),
        ]
        let demoArtists: [Artist] = [
            decode(#"{"id":"ar1","name":"The Northern Lights","uri":"spotify:artist:ar1"}"#),
            decode(#"{"id":"ar2","name":"Mira Kell","uri":"spotify:artist:ar2"}"#),
            decode(#"{"id":"ar3","name":"Oslo Dawn","uri":"spotify:artist:ar3"}"#),
            decode(#"{"id":"ar4","name":"Kingfisher Lane","uri":"spotify:artist:ar4"}"#),
            decode(#"{"id":"ar5","name":"Bright Machines","uri":"spotify:artist:ar5"}"#),
            decode(#"{"id":"ar6","name":"Linnea Saar","uri":"spotify:artist:ar6"}"#),
        ]
        let whatsNew = WhatsNewModel(
            newReleases: demoReleases,
            madeForYou: Array(playlists.prefix(4)),
            topMixes: Array(playlists.dropFirst(4).prefix(3)),
            topArtists: demoArtists,
            recentlyPlayed: list,
            topTracks: list
        )
        app.library.showDemo(
            playlists: playlists,
            pages: [.whatsNew: .whatsNew(whatsNew), .likedSongs: .tracks(list)])
        app.player.showDemo(
            CoreTrack(
                uri: rows[4].uri, linkedURI: nil, name: rows[4].name, artists: [.init(uri: "", name: rows[4].artistNames)],
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
