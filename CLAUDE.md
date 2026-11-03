# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (imported above) is the authoritative source for build commands,
the vendored-librespot patch rules, Spotify risk-control hazards, librespot API
traps, UI performance rules, and code-review rules. This file only adds what is
not already there.

## Verification

`./script/agent_check.sh` is the only test suite and the default verification
step. It never launches the app, touches Keychain, or contacts Spotify. Any
`NANYIN_ALLOW_LIVE_SPOTIFY=1` command, Xcode ⌘R, or `open Nanyin.app` is live
and needs explicit user approval in the current task.

The check also runs grep-based structural guards (e.g. `import ChouTiUI` only
under `NanyinApp/Classic/Chrome/` and never alongside `import SwiftUI`;
exactly one position ticker in `PlayerBar`; required Classic-theme seams and
fixture states; `dealer_probe.sh` must not read Keychain). A failing guard
names the invariant — fix the code, don't loosen the guard.

### Swift tests are not XCTest

Each `Tests/*.swift` file is a standalone `@main` executable that
`agent_check.sh` compiles with `xcrun swiftc` against an **explicit list of
app sources**, then runs. To run one suite on its own, copy its
`xcrun swiftc … -o <out>` block from `script/agent_check.sh` and execute the
binary. To run a single test, temporarily comment out the other calls in that
file's `static func main()`.

Consequences:

- Logic that needs offline tests lives in framework-free pure types
  (`NanyinApp/State/*` reducers, `PlaybackReconnectPolicy`, `CredentialRevision`,
  `PlaybackStallDetector`) so it can compile without `AppModel`, the Rust
  library, or SwiftUI. Keep new testable logic out of `AppModel`.
- A new test file, or a new dependency of an existing suite, must be added to
  the matching `swiftc` source list in `agent_check.sh`.
- New tests are plain functions invoked from `main()`, using whatever assertion
  style the file already uses (`expect(…)`, `check(…)`, or plain
  `assert`/`precondition` in `PlaylistReadTests`); there is no test-name filter.
  Suites are compiled without `-O`, so `assert` stays active — keep it that way.

Rust: `./script/cargo.sh test --offline --locked --manifest-path rust/Cargo.toml --lib [name_filter]`.
Always go through `script/cargo.sh` (pins the toolchain from `rust-toolchain.toml`).

### Adding Swift files

`Nanyin.xcodeproj` is generated from `project.yml`. After adding or removing a
file under `NanyinApp/`, run `xcodegen generate`; `agent_check.sh` fails if
any Swift source is missing from the project.

### Fresh checkout

`research-repos/` is git-ignored but required to build:
`./script/vendor_librespot.sh && ./script/vendor_choutiui.sh`.

## Architecture

SwiftUI app (`NanyinApp/`) + Rust staticlib (`rust/`, built by the Xcode
pre-build phase via `rust/build.sh` into `build/rust/{lib,include}`). The C
header `rust/include/nanyin_core.h` is the FFI contract; Swift imports it as
module `NanyinCore`.

**Two independent Spotify paths:**

- *Web API* (library, search, playlists, likes): `SpotifyAuth` (ncspot client
  id) → `SpotifyClient` → `SpotifyWebTransport` / `SpotifyRequestGate` (request
  throttling and persisted cooldowns).
- *Playback* (Connect device, audio): keymaster token → `Core`
  (`Core/NanyinCore.swift`, thin FFI wrapper) → `rust/src/lib.rs` (librespot
  `Session` + `Spirc` + player). PCM flows back through `rust/src/proxy_sink.rs`
  → FFI callback → `Audio/AudioRenderer.swift` ring buffer → `AVAudioEngine`.
  `rust/src/playlist_reads.rs` lets playlist pages reuse an already-verified
  playback session for bounded reads.

**`State/AppModel.swift`** (~3.8k lines, `@MainActor`) is the single glue
object: auth, navigation, library state, and playback orchestration. It owns
the reconnect flow (`AppModel.reconnect`), the `activePlaybackGeneration`
fence, and pending play intents.

**Generation fencing spans the FFI boundary.** Every player rebuild bumps a
generation. Rust guards publication with `PLAYER_LIFECYCLE` +
`with_current_player_generation`; callbacks carry the generation, and Swift
drops events whose generation is not current. Any new event, callback, or
async completion must follow the same pattern (see the review rules in
`AGENTS.md`).

**Persisted traffic safety.** `TrafficSafetyStore`, `PlaybackCommandQueue`, and
`PlaybackReconnectPolicy` in `State/PlaybackReconnectPolicy.swift` hold
recovery budgets, backoff, and 429 cooldowns. Rust reports server cooldowns
through `nanyin_register_rate_limit_callback`; persistence must succeed before
the request continues. Details: `docs/playback-safety.md`.

**Themes.** `NanyinDarkShell` and `Classic2010Shell` both host the shared
`AppContentView`; themes change chrome and density only, never playback or
session behavior. Classic chrome is AppKit/ChouTiUI wrapped by SwiftUI bridges
in `Classic/Bridge/`.

## Reference docs

- `REVIEW.md` — full-tree review (2026-08-28), a dated snapshot. Its "What is
  solid" table lists areas already verified; don't re-litigate them without new
  evidence. Its line numbers have drifted and some findings may since be fixed
  (e.g. second-instance protection now exists as `NanyinProcessLock`) — check
  the current code before citing it.
- `docs/playback-safety.md`, `docs/playback-recovery-research.md`,
  `docs/spirc-decision-and-boundary-plan.md` — background for playback changes.
- `docs/distribution.md` — release/notarization/Sparkle (`script/package_release.sh`).
- `ROADMAP.md` (milestones), `PRODUCT.md` (positioning).
