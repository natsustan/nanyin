# AGENTS.md — nanyin

Native macOS Spotify client (SwiftUI shell + Rust librespot core). See `ROADMAP.md` for the milestone plan and `README.md` for architecture.

## Build

```sh
xcodegen generate   # if Nanyin.xcodeproj missing (XcodeGen via mise)
xcodebuild -project Nanyin.xcodeproj -scheme Nanyin -configuration Debug build
# Rust core builds as a pre-build phase (cargo via mise: rust@stable)
# Or standalone: ./rust/build.sh
```

Run the binary with stderr captured for diagnostics — Swift `dlog` + Rust `eprintln` stream unbuffered. `RUST_LOG=librespot_connect=debug,librespot_core::dealer=warn` for librespot internals.

## CRITICAL: vendored librespot with local patch

`rust/Cargo.toml` points at `research-repos/librespot` via **path dependencies** — NOT crates.io, NOT the git rev. The checkout carries an applied-but-upstream-unmerged patch:

- **PR #1741** (connect: don't answer our own cluster update with another state update). Without it, being an active Connect device causes a state-PUT echo loop → Spotify 429 → dealer websocket ghosting → spirc dies at ~33s → refresh tokens eventually revoked (account-level risk control). This happened; it cost a full debugging day and the account got temporarily penalized.

DO NOT "upgrade" the librespot dependency to crates.io or a git rev until #1741 is merged upstream — you would silently drop the patch and re-enter the echo loop. Check upstream: https://github.com/librespot-org/librespot/pull/1741

`research-repos/` also vendors cliamp (Go, MIT) and NullSpot (Swift+Rust, MIT) as design references. All three are git-ignored; NullSpot's `rust/src/lib.rs` is the reference for Spirc wiring, cliamp's `docs/spotify.md` documents Web API pitfalls.

## Spotify risk-control hazards (do not regress)

1. **Stable device id**: pass `KeychainStore.spotifyDeviceId` (persisted per-install) to `nanyin_init_player`. Never derive device ids from PIDs — every launch registering a new Connect device leaves zombies and looks like abuse.
2. **Token refresh discipline**: on reconnect, reuse the current access token first; only mint via refresh when actually rejected (`AppModel.reconnect`). Token-rotation storms trigger risk control (we had a refresh token REVOKED this way).
3. **Never auto-open a browser from error paths** (cliamp lesson) — only from explicit user action.
4. **Playback/Web API token split**: Web API uses ncspot client id (`d420a117…`, own quota); playback uses keymaster id (`65b70807…`, required by login5). Keymaster's Web API quota is globally shared and often 429-limited — never call Web API with the keymaster flow's token.
5. **Large contexts via `nanyin_play_context`** (server-resolved `spotify:playlist:…` / `spotify:user:<id>:collection`). Uploading 1000+ track URIs into Connect state gets 429-rejected silently (rc=0 but nothing plays).

## Account penalization (recognition & procedure)

If playback becomes flaky with repeated `Websocket peer does not respond` + spirc restarts while connect-state PUTs succeed (no 429), the account is being ghosted server-side. Code is NOT the cause. Verify with the idle probe:

```sh
cd rust
RT=$(security find-generic-password -s com.nanyin.app.spotify -a playback_refresh_token -w)
# refresh → token, then:
cargo run --release --example dealer_test -- <token> nanyin_probe_check
# "survived 300s" = account fine (investigate code); dies at ~65s = penalized (wait it out)
```

Penalties decay within hours to ~a day. During a penalty window, UI/Web-API work proceeds normally (dealer-independent); defer playback-smoothness verification. Recommend using a secondary Premium account for daily listening.

## librespot API traps (verified the hard way)

- `Spirc::new` connects the session itself — never `session.connect()` before it (`NotConnected` error).
- `spirc.activate()` before `load()` — commands are ignored while the device is Not Active (silent: rc=0, nothing happens).
- A spirc task exit means the session is unusable; `nanyin_init_player` rebuilds stale state (it does NOT no-op when spirc died — that was a bug).
- `get_player_event_channel()` creates a NEW broadcast channel per call — multiple listeners all receive events.
- `TrackChanged` carries full metadata (title/artists/album/cover URL) — use it; no Web API round trip on track change.
- Tokio runtime: default worker pool. A small fixed pool starves the dealer pong handler under decode load → false ping timeouts → spirc death.

## UI performance rules (60Hz, do not regress)

- Track lists: `List` (NSTableView recycling) + **single scroll region** (never nest ScrollViews).
- Hover state is row-local (`@State` in the row view) — never in the list parent.
- Playback position is NOT stored in AppModel — PlayerBar ticks `Core.positionMs` locally; a 2Hz app-wide observable update re-renders every track row.
- eq indicator: fixed phases, no `randomElement()` per render.

## Conventions

- Commits: conventional style, English (see `git log`).
- xcodegen 2.46: script phases go under `preBuildScripts:` (the `scripts:` key is silently ignored).
- Dual OAuth flows are chained in ONE browser journey (loopback :8989, ncspot first, redirect to keymaster). The loopback listener must survive until ALL callbacks arrive.
- UI: classic flat dark palette (`Theme.swift`), SF Pro, #1DB954 accent used sparingly.
