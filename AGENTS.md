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
6. **One running instance, always**: before ANY launch (manual or automated test), run `pgrep -f Nanyin.app` and stop existing instances first. Two processes sharing the keychain device id register as one Connect device over two dealer connections — this triggered the 2026-08-18 penalty. Applies to `open`, `hub start`, and clicking the app in Finder alike.
7. **Stop-loss discipline during automated testing**: UI automation (keystroke/click scripts) triggers REAL API calls and REAL dealer traffic. At the FIRST sign of spirc/dealer trouble (`failed to put connect state`, spirc task ended, dealer TLS error) — kill ALL nanyin processes immediately and switch to the idle probe. Do not keep automating through errors; each dealer reconnect during a penalty window deepens it. In the 2026-08-18 incident the automated session kept running ~2 minutes past the first `connect state PUT failed` error.


Penalization signatures (any one is enough to suspect; confirm with the probe):

- Flaky playback + repeated `Websocket peer does not respond` + spirc restarts while connect-state PUTs succeed (no 429) — ghosting.
- `failed to put connect state for new device` / `IncompleteMessage` on PUT + spirc task exit + auto re-init loop — 2026-08-18 first symptom.
- Accesspoint TLS handshakes silently dropped (TCP connects, then timeout / `-9806 connection closed`) on ap-gew1/gue1/guc3 while `apresolve.spotify.com` and `accounts.spotify.com` (CDN) still work — server-side accesspoint block, NOT a local network issue. Quick triage: `python3 -c "import socket,ssl; s=ssl.create_default_context().wrap_socket(socket.create_connection(('ap-gew1.spotify.com',443),timeout=6),server_hostname='ap-gew1.spotify.com'); print('TLS OK')"` (timeout = blocked).

The code is NOT the cause. Verify with the idle probe:

```sh
cd rust
RT=$(security find-generic-password -s com.nanyin.app.spotify -a playback_refresh_token -w)
# refresh → token, then:
cargo run --release --example dealer_test -- <token> nanyin_probe_check
# "survived 300s" = account fine (investigate code); dies mid-run (65s–130s
# observed) = penalized (wait it out). Spirc::new panicking on connect means
# the block is at TLS-handshake depth — the deepest tier; it softens first.
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
