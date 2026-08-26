# nanyin

A native macOS Spotify client with the feel of the classic (pre-Electron-look) desktop app: flat dark UI, black sidebar, green accents. Pure SwiftUI shell over a small Rust core ([librespot](https://github.com/librespot-org/librespot)) that handles the Spotify session, Spotify Connect, decryption and decoding.

> **Unofficial client.** Not affiliated with Spotify. Requires a **Spotify Premium** account. Using it is against the Spotify ToS — use a secondary account if that concerns you.

## Install

Download the notarized Apple Silicon DMG from
[GitHub Releases](https://github.com/natsustan/nanyin/releases). Nanyin requires
macOS 15 or later and updates itself through Sparkle.

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

- **Auth**: two chained OAuth flows in one browser journey. The Web API uses
  ncspot's client id and playback uses the librespot keymaster client id; the
  credentials and refresh lifecycles remain strictly separated.
- **Audio**: 44.1 kHz stereo f32 interleaved PCM crosses the FFI boundary ~4096 samples at a time; backpressure paces the decoder to real time.
- **Credits**: the FFI/core design is adapted from [NullSpot](https://github.com/michaelh03/NullSpot) (MIT) and cliamp (MIT). Both are vendored as reference under `research-repos/` (git-ignored).

## Development

Prerequisites (via [mise](https://mise.jdx.dev)):

```sh
mise use -g rust@stable   # cargo
```

Agent-safe verification (builds and tests without launching Nanyin, reading
Keychain, or contacting Spotify):

```sh
./script/agent_check.sh
```

Build and run against a real Spotify account (live operation):

```sh
NANYIN_ALLOW_LIVE_SPOTIFY=1 ./script/build_and_run.sh
# build + package to dist/ + launch (logs: build/nanyin-launch.log)
xcodegen generate        # if Nanyin.xcodeproj doesn't exist
open Nanyin.xcodeproj    # ⌘R — the Rust core builds as a pre-build phase
```

Or from the CLI:

```sh
xcodebuild -project Nanyin.xcodeproj -scheme Nanyin -configuration Debug build
./rust/build.sh          # standalone Rust core build
```

## Distribution

Build an unsigned, arm64 Release app and DMG without launching Nanyin or
contacting Spotify/Apple:

```sh
./script/package_release.sh
```

Developer ID signing and notarization are opt-in. See
[`docs/distribution.md`](docs/distribution.md) for credentials, commands, and
the release checklist.

## Status

| Milestone | Scope | State |
|---|---|---|
| M0 | Login, playback core, audio renderer, player bar | ✅ |
| M1 | Liked Songs, playlists, covers, track lists | ✅ |
| M2 | Queue, shuffle/repeat, media keys, MPNowPlayingInfo | ✅ |
| M3 | Search | ✅ |
| M4 | Library expansion, personalized Home, themes and polish | In progress; see `ROADMAP.md` |
| M5 | Signing, notarization, Sparkle, DMG and Homebrew cask | ✅ v0.1.0 |

Out of scope for MVP: Spotify Connect as a *remote*, podcasts, lyrics, offline caching, social.
