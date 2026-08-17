# nanyin

A native macOS Spotify client with the feel of the classic (pre-Electron-look) desktop app: flat dark UI, black sidebar, green accents. Pure SwiftUI shell over a small Rust core ([librespot](https://github.com/librespot-org/librespot)) that handles the Spotify session, Spotify Connect, decryption and decoding.

> **Unofficial client.** Not affiliated with Spotify. Requires a **Spotify Premium** account. Using it is against the Spotify ToS — use a secondary account if that concerns you.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ nanyin.app                                           │
│                                                     │
│  Swift (UI + app logic)                             │
│  ├─ SwiftUI — classic dark three-pane layout        │
│  ├─ SpotifyAuth — OAuth PKCE via loopback redirect  │
│  ├─ SpotifyClient — Web API (metadata)              │
│  ├─ AudioRenderer — ring buffer + AVAudioEngine     │
│  └─ KeychainStore — tokens                          │
│                                                     │
│  Rust cdylib (rust/)                                 │
│  └─ librespot: session, Spirc, decode → PCM FFI     │
└─────────────────────────────────────────────────────┘
```

- **Auth**: single OAuth flow with the librespot keymaster client id — the token works for both the Web API and playback (strategy from [cliamp](https://github.com/bjarneo/cliamp)).
- **Audio**: 44.1 kHz stereo f32 interleaved PCM crosses the FFI boundary ~4096 samples at a time; backpressure paces the decoder to real time.
- **Credits**: the FFI/core design is adapted from [NullSpot](https://github.com/michaelh03/NullSpot) (MIT) and cliamp (MIT). Both are vendored as reference under `research-repos/` (git-ignored).

## Development

Prerequisites (via [mise](https://mise.jdx.dev)):

```sh
mise use -g rust@stable   # cargo
```

Build & run:

```sh
xcodegen generate        # if Nanyin.xcodeproj doesn't exist
open Nanyin.xcodeproj    # ⌘R — the Rust core builds as a pre-build phase
```

Or from the CLI:

```sh
xcodebuild -project Nanyin.xcodeproj -scheme Nanyin -configuration Debug build
./rust/build.sh          # standalone Rust core build
```

## Status

| Milestone | Scope | State |
|---|---|---|
| M0 | Login → play any track by URI/URL → audio out, player bar | ✅ scaffolded, needs live testing |
| M1 | Liked Songs, playlists, covers, track lists | — |
| M2 | Queue, shuffle/repeat, media keys, MPNowPlayingInfo | — |
| M3 | Search | — |

Out of scope for MVP: Spotify Connect as a *remote*, podcasts, lyrics, offline caching, social.
