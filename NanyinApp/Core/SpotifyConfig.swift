//
//  SpotifyConfig.swift
//  Nanyin
//

enum SpotifyConfig {
    /// The librespot keymaster client_id — shared by librespot, spotify-player
    /// and cliamp. Predates Spotify's Nov 27 2024 dev-mode quota restriction,
    /// so catalog endpoints (/v1/search) keep working, and login5 accepts
    /// playback credentials minted by it (cliamp).
    nonisolated static let clientId = "65b708073fc0480ea92a077233ca87bd"

    /// Loopback redirect for the OAuth flow. Spotify's loopback exception
    /// allows any port on 127.0.0.1 (RFC 8252); 19873 avoids cliamp (19872)
    /// and NullSpot (8989).
    nonisolated static let redirectUri = "http://127.0.0.1:19873/login"
    nonisolated static let loopbackPort: UInt16 = 19_873

    /// OAuth scopes (same set cliamp requests in its single keymaster flow).
    nonisolated static let scopes: [String] = [
        "playlist-read-collaborative",
        "playlist-read-private",
        "playlist-modify-public",
        "playlist-modify-private",
        "streaming",
        "user-library-read",
        "user-library-modify",
        "user-read-private",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-top-read",
        "user-follow-read",
        "user-follow-modify",
    ]
}
