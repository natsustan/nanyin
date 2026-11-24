# Nanyin

A native macOS Spotify client inspired by the 2010 Aqua-era Spotify for Mac: brushed metal chrome, Lucida Grande, and a fast charcoal track table. Built with Swift/SwiftUI for the interface and [librespot](https://github.com/librespot-org/librespot) (Rust) for audio playback.

> **Disclaimer:** Nanyin is an unofficial third-party client and is not affiliated with or endorsed by Spotify.

## Requirements

- **macOS 14.0 (Sonoma) or later** on Apple Silicon (`arm64`)
- A **Spotify Premium** account (required by Spotify both for creating a personal Web API app and for playback via librespot)

## Download & Install

1. Download the latest `Nanyin-<version>.dmg` from [GitHub Releases](https://github.com/natsustan/nanyin/releases/latest).
2. Open the disk image and drag **Nanyin** into your **Applications** folder.
3. Launch Nanyin. Releases are signed with Developer ID, notarized by Apple, and update automatically via Sparkle (**Nanyin → Check for Updates…**).

## First-Time Setup (~2 minutes)

Spotify's Web API rules no longer allow third-party open-source clients to share a single Client ID across users. Each listener registers a personal app once on Spotify's developer dashboard; Nanyin guides you through this on first launch:

1. Open the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and sign in with your Spotify Premium account.
2. Click **Create app** (any app name and description are fine).
3. Under **Redirect URIs**, add exactly:
   ```
   http://127.0.0.1:8989/login
   ```
4. Tick **Web API**, accept the terms, and click **Save**.
5. Open your app's **Settings**, copy the 32-character **Client ID** (not the Client Secret), paste it into Nanyin, and click **Sign In with Spotify**.
6. Complete the one-time **Approve Playback in Browser** prompt so Nanyin can stream audio and appear as a Spotify Connect device on your Mac.

Nanyin never sees your Spotify password; OAuth tokens and playback credentials are stored in your macOS Keychain.

## What's Included

- **Library & Playlists**: Starred (Liked Songs), Saved Albums, Followed Artists, creating/renaming/editing/deleting playlists, adding/removing tracks, in-playlist filter and sort, album saving, and artist following.
- **What's New**: Followed artists' new releases, personalized mixes, top artists, top tracks, and recently played history.
- **Search & Links**: Search tracks, artists, albums, and playlists, or paste any `open.spotify.com` URL / `spotify:` URI directly into the search bar.
- **Native Playback**: High-quality playback (96 / 160 / 320 kbps), optional volume normalization, song credits, macOS media keys and Control Center integration, Spotify Connect receiver, and automatic recovery after sleep or brief drops.
- **Settings (`⌘,`)**: Audio quality, volume normalization, custom Connect device name, HTTP/SOCKS5 proxy configuration, cache management, and one-click log access.

## Known Limitations

- **Spotify Free accounts are not supported** (Spotify requires Premium for playback and personal Development Mode apps).
- **Music only**: Podcasts, audiobooks, and offline downloads are not supported.
- **No built-in lyrics** or outbound Spotify Connect device switcher yet (Nanyin acts as a Connect receiver).
- **Proxy for playback**: Browsing, sign-in, and cover art support macOS System Proxy, HTTP, and SOCKS5 (including authentication). Audio playback (librespot) only tunnels through an unauthenticated HTTP proxy (for example `http://127.0.0.1:7890`).

## Troubleshooting

- **Sign-in says "Invalid redirect URI"**: Check that `http://127.0.0.1:8989/login` is saved verbatim in your Spotify Developer app settings (no trailing slash, `127.0.0.1` instead of `localhost`).
- **Library loads, but playback won't connect behind a proxy**: Open **Settings (`⌘,`) → Network**, select **HTTP**, and point it at your local HTTP proxy port without a username/password.
- **Reporting a bug**: Open **Settings (`⌘,`) → Storage & Logs → Reveal in Finder** to locate `core.log` (`~/Library/Logs/Nanyin/core.log`, rotated at 5 MB, no passwords stored) and attach relevant lines to a GitHub issue.

## Building from Source

Dependencies (Rust, `xcodegen`, `xcbeautify`) are managed with [mise](https://mise.jdx.dev):

```sh
mise install
script/build_and_run.sh
```

Run tests:

```sh
swift test --package-path Packages/NanyinKit
(cd core && mise exec -- cargo test && mise exec -- cargo clippy --all-targets)
```

See [AGENTS.md](AGENTS.md) for architecture notes and release scripts.

## License

MIT — see [LICENSE](LICENSE).
