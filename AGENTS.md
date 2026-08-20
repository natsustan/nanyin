# AGENTS.md — nanyin

Native macOS Spotify client (SwiftUI shell + Rust librespot core). See `ROADMAP.md` for the milestone plan and `README.md` for architecture.

## Build

```sh
# Default for agents and CI-like local verification. Never launches the app,
# reads Keychain, or contacts Spotify.
./script/agent_check.sh

# LIVE commands: run only after explicit user authorization in the current
# task. They terminate existing instances, build/package, and launch Nanyin.
NANYIN_ALLOW_LIVE_SPOTIFY=1 ./script/build_and_run.sh [run|--live-smoke|--logs|--debug]
# terminate → xcodegen (if needed) → xcodebuild → package to dist/ → launch.
# stderr (dlog + eprintln) captured to build/nanyin-launch.log.
xcodebuild -project Nanyin.xcodeproj -scheme Nanyin -configuration Debug build
# Rust core builds as a pre-build phase (cargo via mise: rust@stable)
# Or standalone: ./rust/build.sh
```

Run the binary with stderr captured for diagnostics — Swift `dlog` + Rust `eprintln` stream unbuffered. `RUST_LOG=librespot_connect=debug,librespot_core::dealer=warn` for librespot internals.

## CRITICAL: vendored librespot with local patches

`rust/Cargo.toml` points at `research-repos/librespot` via **path dependencies** — NOT crates.io, NOT the git rev. The checkout carries applied local patches:

- **PR #1741** (connect: don't answer our own cluster update with another state update). Without it, being an active Connect device causes a state-PUT echo loop that has repeatedly ended in Spotify 429 responses. Dealer ghosting, spirc termination, and credential rejection were observed in the same incident, but the server-side causal chain is not publicly documented.
- **Typed AP authentication error re-export** (local): lets the Rust bridge distinguish explicit `BadCredentials` / `CouldNotValidateCredentials` responses from unrelated `PermissionDenied` failures. Without it, reconnect could rotate the playback token after client-token HTTP 403 responses.

The canonical patch artifact is checked in at
`patches/librespot-pr-1741.patch`; `script/agent_check.sh` verifies that the
vendored checkout contains that exact patch before building.

`patches/librespot-auth-error-classification.patch` is a narrow local API
patch that re-exports librespot's access-point authentication error. The Rust
bridge uses it to distinguish an explicit credential rejection from generic
`PermissionDenied` failures such as client-token HTTP 403 responses. Keep this
patch until upstream exposes an equivalent typed classification.

DO NOT "upgrade" the librespot dependency to crates.io or a git rev until #1741 is merged upstream — you would silently drop the patch and re-enter the echo loop. Check upstream: https://github.com/librespot-org/librespot/pull/1741

`research-repos/` also vendors cliamp (Go, MIT) and NullSpot (Swift+Rust, MIT) as design references. All three are git-ignored; NullSpot's `rust/src/lib.rs` is the reference for Spirc wiring, cliamp's `docs/spotify.md` documents Web API pitfalls.

## Spotify risk-control hazards (do not regress)

1. **Stable device id**: pass the per-install, successfully persisted `KeychainStore.spotifyDeviceId()` to `nanyin_init_player`. Never derive device ids from PIDs; repeated device registration produced zombie devices during the 2026-08-18 incident and may resemble abusive traffic.
2. **Token refresh discipline**: on reconnect, reuse the current access token first; only mint via refresh when actually rejected (`AppModel.reconnect`). Repeated refreshes coincided with credential rejection during the 2026-08-18 incident, so avoid refresh storms even though Spotify's internal risk-control rules are not public.
3. **Never auto-open a browser from error paths** (cliamp lesson) — only from explicit user action.
4. **Playback/Web API token split**: Web API uses ncspot client id (`d420a117…`, own quota); playback uses keymaster id (`65b70807…`, required by login5). Web API calls using the keymaster flow repeatedly encountered 429 responses during development, so keep that token out of the Web API path.
5. **Large contexts via `nanyin_play_context`** (server-resolved `spotify:playlist:…` / `spotify:user:<id>:collection`). In testing, uploading 1000+ track URIs into Connect state returned rc=0 but did not start playback and coincided with 429 responses; prefer server-resolved contexts.
6. **One running instance, always**: before ANY launch (manual or automated test), run `pgrep -f Nanyin.app` and stop existing instances first. Two processes sharing the Keychain device id create two dealer connections for one Connect identity, producing ambiguous state; this coincided with the suspected 2026-08-18 restriction. Applies to `open`, `hub start`, and clicking the app in Finder alike.
7. **Stop-loss discipline during automated testing**: UI automation (keystroke/click scripts) triggers REAL API calls and REAL dealer traffic. At the FIRST sign of spirc/dealer trouble (`failed to put connect state`, spirc task ended, dealer TLS error) — kill ALL nanyin processes immediately and switch to the idle probe. Do not keep automating through errors; repeated reconnect traffic may compound a suspected restriction. In the 2026-08-18 incident the automated session kept running ~2 minutes past the first `connect state PUT failed` error.
8. **Multi-device listening is fine; multi-device *automation* is not** (2026-08-19): normal Premium use — CarPlay in the morning, nanyin at the desk — is safe. The 2026-08-19 ghosting happened when an overnight-idle nanyin session `activate()`d against a phone+CarPlay that had been playing, seconds apart, while the account was still in a watch window from the day before. Two hard rules: (a) during a suspected watch window, do NOT automate playback tests at all — every fresh probe session may itself renew the window (2026-08-19 morning probes kept dying at ~70s and each run was another handshake); (b) protocol-level experiments against Spotify endpoints (hand-rolled dealer frames, novel request shapes) only ever from a throwaway account — the 2026-08-18 SUBSCRIBE experiments sent server-rejected frames 3× from the primary account.
9. **Overnight zombie sessions self-heal, don't poke them** (2026-08-19): an app left running overnight holds a session that is effectively dead by morning; the first `activate()` after another device played can ghost it. The core now rebuilds on `is_invalid` (`fix(core): rebuild the player when the session went invalid`), so the recovery path is: reconnect callback → clean rebuild. Future hardening direction: on app foreground with session age > a few hours, proactively re-init before the user's first click.


Possible penalization signatures observed during the 2026-08-18 incident (also rule out local network, stale binaries, and Spotify service failures):

- Flaky playback + repeated `Websocket peer does not respond` + spirc restarts while connect-state PUTs succeed (no 429) — ghosting.
- `failed to put connect state for new device` / `IncompleteMessage` on PUT + spirc task exit + auto re-init loop — 2026-08-18 first symptom.
- Accesspoint TLS handshakes silently dropped (TCP connects, then timeout / `-9806 connection closed`) on ap-gew1/gue1/guc3 while `apresolve.spotify.com` and `accounts.spotify.com` still work. This is consistent with an accesspoint-specific block or outage, but does not by itself exclude local routing or TLS problems. Quick triage: `python3 -c "import socket,ssl; s=ssl.create_default_context().wrap_socket(socket.create_connection(('ap-gew1.spotify.com',443),timeout=6),server_hostname='ap-gew1.spotify.com'); print('TLS OK')"`.

Use the idle probe to separate playback activity from dealer stability. It is a LIVE command and requires explicit user authorization. Its result is diagnostic evidence, not proof of a specific server-side cause:

```sh
NANYIN_ALLOW_LIVE_SPOTIFY=1 script/dealer_probe.sh [device_id]   # 0 = stable for 300s; 1/3 = dealer failure; 2 = token missing/rejected; 5 = Keychain access failed
```

**CRITICAL — persist replacement refresh tokens**: Spotify may return a new
`refresh_token` in a refresh response. The keymaster flow (65b70807…) has been
observed returning a replacement and then rejecting the previous token.
`dealer_probe.sh` and `SpotifyAuth.decodeToken` therefore require any returned
replacement to be saved to Keychain before continuing. If no replacement is
returned, retain the existing token, as specified by Spotify's public OAuth
documentation. Do not assume either client flow always or never rotates.

Probe interpretation based on the 2026-08-18 incident: surviving 300 seconds
shows that one idle dealer session was stable and shifts suspicion toward the
application path. Mid-run failures at 65–130 seconds and `-9806 connection
closed` were observed during the suspected penalty window, but are not unique
proof of penalization or a guaranteed recovery stage.

In the observed incident, the suspected restriction decayed within hours to about a day. Treat that as an incident note, not a guaranteed recovery time. During a suspected penalty window, UI/Web-API work can proceed independently; defer playback-smoothness verification. Recommend using a secondary Premium account for daily listening.

## librespot API traps (verified the hard way)

- `Spirc::new` connects the session itself — never `session.connect()` before it (`NotConnected` error).
- `spirc.activate()` before `load()` — commands are ignored while the device is Not Active (silent: rc=0, nothing happens).
- A spirc task exit means the session is unusable; `nanyin_init_player` rebuilds stale state (it does NOT no-op when spirc died — that was a bug).
- `get_player_event_channel()` creates a NEW broadcast channel per call — multiple listeners all receive events.
- `TrackChanged` carries full metadata (title/artists/album/cover URL) — use it; no Web API round trip on track change.
- Tokio runtime: default worker pool. A small fixed pool starves the dealer pong handler under decode load → false ping timeouts → spirc death.
- `nanyin_init_player` bounds the `Spirc::new` handshake with a 30s tokio
  timeout (`PLAYER_INIT_TIMEOUT`), and Swift calls it OFF the main thread
  (`Core.initializePlayer` → serial queue). Never call the FFI synchronously
  from MainActor: penalty-window TLS drops stall it 95s+ (the 2026-08-18
  "login spins forever" report was exactly this, not an auth regression).

## UI performance rules (60Hz, do not regress)

- Potentially large track lists use `List` (NSTableView recycling) and one
  vertical scroll region. Never nest same-axis scroll views. Bounded
  cross-axis carousels may use a lazy horizontal `ScrollView` inside the
  page's vertical container.
- Hover state is row-local (`@State` in the row view) — never in the list parent.
- Playback position is NOT stored in AppModel — PlayerBar ticks `Core.positionMs` locally; a 2Hz app-wide observable update re-renders every track row.
- eq indicator: fixed phases, no `randomElement()` per render.

## Conventions

- Commits: conventional style, English (see `git log`).
- xcodegen 2.46: script phases go under `preBuildScripts:` (the `scripts:` key is silently ignored).
- Dual OAuth flows are chained in ONE browser journey (loopback :8989, ncspot first, redirect to keymaster). The loopback listener must survive until ALL callbacks arrive.
- UI: classic flat dark palette (`Theme.swift`), SF Pro, #1DB954 accent used sparingly.

## Code Review Rules

### Spotify auth and session recovery

- Flag any reconnect path that refreshes a playback token after a generic
  network, dealer, TLS, timeout, or initialization failure. Safe path: reuse
  the current access token and refresh only after a typed authentication
  rejection.
- Flag any sign-out path where an in-flight refresh can persist a replacement
  token after credential deletion. Safe path: refresh and clear operations for
  each token kind share one serialized coordinator, and sign-out wins.
- Flag any player event, completion monitor, or initialization result that can
  publish after its generation was replaced or shutdown began. Safe path:
  generation validation and state publication are atomic.

### Liked Songs reconciliation

- For changes to optimistic likes, verify rapid repeated toggles, stale server
  snapshots, partial-prefix refreshes, failed writes, override expiry, and
  account-epoch changes. Safe path: UI state is derived from the last confirmed
  server state plus the latest non-expired local intent; an older result never
  overwrites a newer intent.
