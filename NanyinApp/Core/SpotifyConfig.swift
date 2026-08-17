//
//  SpotifyConfig.swift
//  Nanyin
//

enum SpotifyConfig {
    /// Web API client: ncspot's published client_id (same one NullSpot uses).
    /// Production-approved (not Dev Mode) → own rate-limit quota and catalog
    /// endpoints (/v1/search) work. Registered redirect: 127.0.0.1:8989/login.
    nonisolated static let webApiClientId = "d420a117a32841c2b3474932e49fb54b"

    /// Playback client: the librespot keymaster client_id (shared by librespot,
    /// spotify-player, cliamp). Accepted by login5 for playback sessions
    /// (verified working). Any 127.0.0.1 port is allowed for it.
    nonisolated static let playbackClientId = "65b708073fc0480ea92a077233ca87bd"

    /// ncspot's client_id is registered with this exact loopback redirect.
    /// Both flows run on this port (cliamp-style chained redirects).
    nonisolated static let redirectUri = "http://127.0.0.1:8989/login"
    nonisolated static let loopbackPort: UInt16 = 8989

    /// Web API scopes (metadata, library, playlists).
    nonisolated static let webApiScopes: [String] = [
        "playlist-read-collaborative",
        "playlist-read-private",
        "playlist-modify-public",
        "playlist-modify-private",
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

    /// Playback scopes for the keymaster flow (cliamp: only "streaming").
    nonisolated static let playbackScopes: [String] = ["streaming"]
}
