# Nanyin

<img src="Design/AppIcon-v13-black-blue-headphones.png" width="96" alt="Nanyin icon">

A native macOS Spotify client. SwiftUI owns the app shell, library, and
Web API; a small Rust core ([librespot](https://github.com/librespot-org/librespot))
owns the Spotify session, Connect identity, decryption, and decoding.

Nanyin is for people who want a lightweight Mac music client with the
information density of older desktop players. Two runtime themes share the
same features: **Nanyin Dark** (flat black sidebar, green accents) and
**Classic 2010** (graphite Aqua chrome drawn from the 2006–2010 desktop
era, not a pixel-for-pixel clone).

> **Unofficial client.** Not affiliated with Spotify. Requires a **Spotify
> Premium** account. Using a third-party client is against the Spotify Terms
> of Service — use a secondary account if that concerns you.

## Install

Current release: **0.1.1** (Apple Silicon, macOS 15 Sequoia or later).

Download the notarized arm64 DMG from
[GitHub Releases](https://github.com/natsustan/nanyin/releases). Nanyin
updates itself through Sparkle (**Check for Updates…** in the app menu;
12-hour scheduled check).

A Homebrew cask for the same versioned DMG lives at
[`homebrew/Casks/nanyin.rb`](homebrew/Casks/nanyin.rb). Day-to-day updates
still go through Sparkle (`auto_updates true`). See
[`docs/homebrew.md`](docs/homebrew.md).

Intel Macs are not supported yet: the Rust core is an arm64 static library.

## Features

### Listening

- Play / pause, next / previous, seek, volume
- Shuffle and repeat (off / context / one track)
- Queue page: now playing, next up (server queue, ~20 items), recently played
- Add to queue from track rows
- End-of-track advance, gapless 320 kbps playback, local stall recovery
- Restores the last local track and position across launches
- Appears as a Spotify Connect *device* (other official clients can transfer
  playback to Nanyin). Nanyin does not remote-control other devices.

### Library and discovery

- Home: recently played, top tracks, top artists, library shortcuts
- Search: songs and artists as you type (⌘K / ⌘F); paste a Spotify track
  link to play it directly
- Liked Songs, with optimistic heart toggles in rows and the player bar
- Saved Albums cover grid (Recently Added / Album / Artist, client-side filter)
- Followed Artists portrait grid (name or Spotify cursor order)
- Playlists: browse, create (sidebar `+`), add tracks from context menus
- Album and artist pages: top tracks, discography, follow/save, server-resolved
  `spotify:album:` / `spotify:artist:` / `spotify:playlist:` / Liked Songs
  contexts (large catalogs are never uploaded as track-URI lists)

### macOS

- Media keys, Control Center, and lock-screen Now Playing
  (play/pause/next/prev/seek)
- Back / forward page history (⌘[ / ⌘])
- Space = play/pause; ⌘← / ⌘→ = previous / next
- VoiceOver labels, visible focus, and Reduce Motion on artwork and EQ
- Sparkle updates; Hardened Runtime; Developer ID + notarization on releases

### Appearance

Theme persists in Settings and the **Theme** menu:

```text
Nanyin Dark                              Classic 2010
┌──────── sidebar ────────┬─ content ─┐  ┌─ ● ● ●  ◀ ▶  [ Search ] ─┐
│ Home  Search  Queue     │  page     │  ├─ source list ─┬─ table ─┤
│ Your Library            │           │  │ Home / Search │ tracks  │
│   Songs  Albums  Artists│           │  │ Library       │         │
│ Playlists            +  │           │  │ Playlists   + │         │
│  …                      │           │  │ now playing   │         │
├─────────────────────────┴───────────┤  ├───────────────┴─────────┤
│  artwork  title     ◀ ▶  seek  vol  │  │  ◀ ▶  seek        vol   │
└─────────────────────────────────────┘  └─────────────────────────┘
```

Classic 2010 changes density, chrome, track-table columns, and now-playing
placement. It does not change playback or session behavior.

## Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│  Nanyin.app                                                      │
│                                                                  │
│  SwiftUI shells                                                  │
│    Nanyin Dark  ·  Classic 2010 (ChouTiUI chrome, bridged)       │
│    Sidebar · AppContentView · PlayerBar                          │
│                                                                  │
│  AppModel (auth, navigation, library, playback glue)             │
│    SpotifyAuth     dual PKCE on loopback :8989                   │
│    SpotifyClient   Web API (ncspot client id, own quota)         │
│    KeychainStore   refresh tokens + stable device id             │
│    AudioRenderer   ring buffer → AVAudioEngine                   │
│    NowPlayingManager  MPRemoteCommandCenter                      │
│                                                                  │
│  Rust staticlib  rust/  →  build/rust/lib/libnanyin_core.a       │
│    librespot session + Spirc + decode                            │
│    ProxySink → FFI PCM  44.1 kHz stereo f32, ~4096 samples       │
└──────────────────────────────────────────────────────────────────┘
```

**Auth.** One browser journey, two OAuth clients. Web API uses ncspot's
production-approved client id. Playback uses the librespot keymaster client
id (accepted by login5). Tokens, refresh, and sign-out are strictly
separated; a playback-token refresh is used only after a typed credential
rejection, never after a generic network or dealer failure.

**Connect.** Nanyin is one Connect device with a per-install Keychain device
id. `Spirc::new` connects the session; Swift never calls `session.connect()`
first. Commands require `activate()` before `load()`. Player init runs off
the main thread with a 30s handshake timeout.

**Audio.** Decoder PCM crosses FFI into a ~2 s ring buffer with semaphore
backpressure. Output device changes restart `AVAudioEngine`. Librespot's
audio cache lives at `~/Library/Caches/nanyin/audio` (1 GB cap). A local
watchdog classifies downloader / decoder / PCM / renderer stalls and
recovers the current play request once.

**FFI.** `rust/include/nanyin_core.h` is the contract. Typical return codes:
`0` success, `-1` general, `-2` disconnected, `-3` not ready, `-4`
credentials rejected. Callbacks fire on background threads; Swift hops to
the MainActor.

## Repository

```text
NanyinApp/          Swift app (Views, State, Core, Audio, Classic chrome)
rust/               nanyin-core FFI crate (staticlib, arm64)
Tests/              Offline Swift tests (reducers, theme, artwork cache)
script/             agent_check, live launch, package, vendor, dealer probe
patches/            vendored librespot + ChouTiUI patches
homebrew/Casks/     source cask for the notarized DMG
docs/               distribution, Homebrew, theme/research notes
project.yml         XcodeGen spec (regenerates Nanyin.xcodeproj)
PRODUCT.md          product intent
ROADMAP.md          milestone log
AGENTS.md           agent operating rules (Spotify risk-control)
```

`research-repos/` is git-ignored. It vendors librespot (path dependency,
required to build) plus ChouTi / ChouTiUI / ComposeUI (Classic chrome) and
optional design references (NullSpot, cliamp).

ChouTiUI imports are confined to `NanyinApp/Classic/Chrome/`. Nanyin Dark
and `List` rows stay pure SwiftUI.

## Development

Prerequisites: macOS 15+, Apple Silicon, Xcode command-line tools,
[mise](https://mise.jdx.dev) (at least `rust@stable` and `xcodegen`).

```sh
mise use -g rust@stable xcodegen
```

### Vendor checkouts

Librespot is pinned to `9c7d756` with three local patches. Do **not** switch
`rust/Cargo.toml` to crates.io or a git rev until
[librespot#1741](https://github.com/librespot-org/librespot/pull/1741) lands
upstream — that would drop the Connect state-echo fix.

```sh
mkdir -p research-repos
git clone https://github.com/librespot-org/librespot.git research-repos/librespot
git -C research-repos/librespot checkout 9c7d75615fc093bdcbdb29adbce3fed38c531852
git -C research-repos/librespot apply --unidiff-zero ../../patches/librespot-pr-1741.patch
git -C research-repos/librespot apply --unidiff-zero ../../patches/librespot-auth-error-classification.patch
git -C research-repos/librespot apply --unidiff-zero ../../patches/librespot-audio-progress.patch

./script/vendor_choutiui.sh   # ChouTiUI + ChouTi + ComposeUI at pinned SHAs
```

Patches:

| Patch | Why |
|---|---|
| `librespot-pr-1741.patch` | Active Connect device must not answer its own cluster update with another state PUT (echo loop → 429) |
| `librespot-auth-error-classification.patch` | Re-export access-point auth errors so Swift can tell `BadCredentials` from generic `PermissionDenied` |
| `librespot-audio-progress.patch` | Expose download-wait metrics for the local stall watchdog |
| `choutiui-path-dependencies.patch` | Point ChouTiUI at the vendored ChouTi / ComposeUI checkouts |

### Agent-safe verification (default)

Builds and tests without launching Nanyin, reading Keychain, or contacting
Spotify:

```sh
./script/agent_check.sh
```

That script checks the working tree, verifies vendored patches, compiles
offline Swift tests, runs `cargo test --offline --lib`, and
`xcodebuild` Debug arm64 with `CODE_SIGNING_ALLOWED=NO`.

### Live run (opt-in)

Launches the real app against a real Spotify account. Always stop any
existing `Nanyin.app` first — two processes sharing the Keychain device id
open two dealer sessions for one Connect identity.

```sh
NANYIN_ALLOW_LIVE_SPOTIFY=1 ./script/build_and_run.sh
# optional: --debug | --logs | --live-smoke
# stderr (Swift dlog + Rust eprintln) → build/nanyin-launch.log
# if multiple Apple Development certificates are installed:
# NANYIN_DEVELOPMENT_SIGN_IDENTITY=<certificate-SHA> NANYIN_ALLOW_LIVE_SPOTIFY=1 ./script/build_and_run.sh
```

`NANYIN_ALLOW_LIVE_SPOTIFY` guards the live scripts, not the app binary.
Running from Xcode or Finder is also a live operation: obtain explicit human
approval and stop every existing `Nanyin.app` instance first.

From Xcode, after those checks:

```sh
xcodegen generate        # if Nanyin.xcodeproj is missing
open Nanyin.xcodeproj    # ⌘R — Rust core is a pre-build phase
```

Standalone Rust build: `./rust/build.sh`.

Idle dealer probe (also live, also opt-in):

```sh
NANYIN_ALLOW_LIVE_SPOTIFY=1 script/dealer_probe.sh [device_id]
```

## Tests

`script/agent_check.sh` is the suite. It compiles three Swift test binaries
plus Rust lib tests:

| File | Covers |
|---|---|
| `Tests/StateReducerTests.swift` | Likes, saved albums, followed artists, playlist merge, home feed decode, local playback restore, stall detector, pending play, reconnect policy, sign-out fences |
| `Tests/ThemePreferenceTests.swift` | Theme id persistence and fill semantics |
| `Tests/ArtworkCacheTests.swift` | Shared downloads, prefetch tiers, cancellation, concurrency limits |
| `rust/src` `#[cfg(test)]` | FFI init failure classification, proxy sink |

Live Spotify verification is never part of the default check.

## Distribution

Unsigned local Release archive + DMG (no launch, no Spotify, no Apple):

```sh
./script/package_release.sh
```

Writes `build/release/Nanyin-<version>-arm64.dmg` and a SHA-256. Developer
ID signing and notarization are opt-in (`--sign`, `--notarize`). Sparkle
appcast generation is part of `--notarize`. Details and the release
checklist: [`docs/distribution.md`](docs/distribution.md).

## Status

| Milestone | Scope | State |
|---|---|---|
| M0 | Login, playback core, audio renderer, player bar | Done |
| M1 | Liked Songs, playlists, covers, track lists | Done |
| M2 | Queue, shuffle/repeat, media keys, Now Playing | Done |
| M3 | Search (tracks + artists) | Done |
| M4.1–4.5, M4.9 | Artist/album pages, likes, saved albums, Home, playlist create/add, followed artists | Done (some writes still pending live sign-off) |
| M4.6 | Playlist search/filter | Next |
| M4.7 | Keyboard navigation | Partial (`List` arrows + Space) |
| M4.8 | Mini-player window | Not started |
| M5 | Signing, notarization, Sparkle, DMG, Homebrew cask | Done in v0.1.0 / v0.1.1 |

Out of scope for now: Spotify Connect as a *remote*, podcasts, lyrics,
offline caching beyond librespot's audio cache, social, multiple accounts,
non-macOS, Intel.

See [`ROADMAP.md`](ROADMAP.md) for the full log and [`PRODUCT.md`](PRODUCT.md)
for positioning.

## Working with Spotify

A few rules that are easy to regress (the longer version is `AGENTS.md`):

- One running instance. Always.
- Stable per-install device id from Keychain — never a PID.
- Web API token and playback token stay on separate paths.
- Prefer `nanyin_play_context` for playlists, albums, artists, and Liked
  Songs. Uploading 1000+ track URIs into Connect state has failed silently.
- Do not auto-open a browser from error paths; only from explicit Sign In.
- Persist a replacement `refresh_token` when Spotify returns one.
- Agent and CI paths use `./script/agent_check.sh`. Live scripts require both
  `NANYIN_ALLOW_LIVE_SPOTIFY=1` and explicit human approval. Direct launches
  from Xcode or Finder are not protected by that variable and still require
  approval and the one-instance check.

## Credits

FFI/core shape is adapted from [NullSpot](https://github.com/michaelh03/NullSpot)
(MIT). Dual-client OAuth and several Web API pitfalls are documented by
[cliamp](https://github.com/bjarneo/cliamp) (MIT). Playback is
[librespot](https://github.com/librespot-org/librespot). Classic chrome
draws with [ChouTiUI](https://github.com/honghaoz/ChouTiUI) /
[ComposeUI](https://github.com/honghaoz/ComposeUI). Updates use
[Sparkle](https://sparkle-project.org).
