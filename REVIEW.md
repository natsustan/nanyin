# nanyin — Full Project Review

- **Date:** 2026-08-28
- **Scope:** tracked application sources (`NanyinApp/`, `rust/src/`, `Tests/`, `script/`, `patches/`, `project.yml`, `Info.plist`). Not a diff review — a walkthrough of the shipping tree on `main`.
- **Method:** AGENTS.md review rules as the contract; auth / core / library / UI+distribution reviewed in parallel and then re-checked against the source.
- **Live Spotify:** not used. No Keychain reads, no dealer traffic, no app launch.

## Verdict

**Request changes.** The Spotify session life-cycle — reconnect token discipline, sign-out vs in-flight refresh, generation fencing, device-id stability, Web/playback token split — is in good shape and matches the documented safe paths.

The remaining defects are in daily listening and library reconciliation. Two of them are silent no-ops or wrong seeks that ROADMAP M2 already claims done. Liked Songs still inlines snapshot math that Saved Albums / Followed Artists already extracted and tested. The notarized app does not stop a second process from sharing the Keychain device id.

Do not treat this as “auth is on fire.” Do treat it as “the hardened core is ahead of the product paths that sit on top of it.”

## What is solid

These were checked and should not be re-litigated without new evidence.

| Area | Evidence |
|---|---|
| Reconnect reuses the current playback access token | `AppModel.reconnect` (`3077–3136`): `.failed` returns; refresh only after `.credentialsRejected` |
| Typed credential rejection only | Rust maps `BadCredentials` / `CouldNotValidateCredentials` to `-4`; timeouts / generic `PermissionDenied` stay `-1` (`lib.rs:67–77`, test at `1171–1188`) |
| Sign-out wins over a late replacement refresh token | `CredentialPersistenceState` + `TokenCoordinator`; `testSignOutRejectsLateCredentialPersistence` |
| Player events do not publish across a rebuild | Rust `PLAYER_LIFECYCLE` + `with_current_player_generation`; Swift `activePlaybackGeneration` |
| Init is off MainActor and 30s-bounded | `Core.initQueue` + `PLAYER_INIT_TIMEOUT` |
| Stable device id in production | `KeychainStore.spotifyDeviceId()`; FFI rejects null/empty |
| Browser opens only from explicit sign-in | Sole `NSWorkspace.shared.open` is `SpotifyAuth.signIn` |
| Web API vs keymaster split | `SpotifyConfig` client ids; `SpotifyClient` never sees the playback token |
| Replacement refresh tokens persisted | `persistReplacement` + `dealer_probe.sh` save-before-continue |
| PR #1741 / auth-error / audio-progress patches | `script/agent_check.sh` reverse-applies all three |
| Large contexts use server URIs | `playServerContext` / `playContext`; windowed fallback capped at 50 URIs |
| UI 60Hz rules | One vertical scroller per page; row-local hover; position ticks only in `PlayerBar`; `EqIndicator` uses fixed phases |
| `MembershipMutation` / album / artist caches | Pure reducers with substantial `StateReducerTests` coverage |
| ChouTiUI isolation | `agent_check.sh` confines `import ChouTiUI` to `Classic/Chrome/` |

## Findings

Severity:

- **High** — user-visible wrong behavior, or an AGENTS.md hotspot that can produce a second dealer identity / clobber local intent.
- **Medium** — real race or gap; not every session.
- **Low** — hardening, examples, operational hygiene.

### High

#### H1 — Lock screen / Control Center seek is off by 1000×

- **File:** `NanyinApp/Core/NowPlayingManager.swift:50`
- **Also:** `AppModel.seek(to:)` at `3351–3353`

`MPChangePlaybackPositionCommandEvent.positionTime` is seconds. Now Playing info publishes duration as seconds (`durationMs / 1000`). The handler then does:

```swift
let fraction = posEvent.positionTime / Double(max(app.durationMs, 1))
app.seek(to:) // positionMs = fraction * durationMs
```

Algebraically that seeks to `positionTime` **milliseconds**. Dragging the in-app slider is fine (it already passes a 0…1 fraction). Scrubbing from Control Center / lock screen / headphones to 2:00 jumps to 120 ms.

ROADMAP M2.1 lists media-key seek as done. In-app drag-seek does not cover this path.

**Fix:** divide by duration in seconds, or seek `UInt32(positionTime * 1000)` directly.

**Failure:** track is 3:00; user scrubs Now Playing to 2:00; playback jumps to the start.

#### H2 — Play / next / prev after another device took over is a silent no-op

- **File:** `rust/src/lib.rs:986`
- **Also:** `AppModel.togglePlay` resume arm at `3304`

Load paths call `spirc.activate()` then `load()` (`lib.rs:912`, `953`). `nanyin_resume` / `nanyin_next` / `nanyin_prev` only call `play()` / `next()` / `prev()`. librespot ignores those while the device is Not Active and returns success.

This is the AGENTS.md trap (“commands are ignored while Not Active: rc=0, nothing happens”) on the transport bar, not on first load. Phone / CarPlay take the active role, user hits Play in nanyin, UI thinks it worked.

**Fix:** `nanyin_resume` (and user-initiated next/prev) should `activate()` then issue the command, same as load.

**Failure:** nanyin was playing; phone starts playback; user presses Play in nanyin; rc=0, nothing is audible, `isPlaying` may stay false until a later event.

#### H3 — First Liked Songs prefix overwrites a newer local intent

- **File:** `NanyinApp/State/AppModel.swift:657`

When `tracksByContext["liked"]` is empty, `refreshLiked` paints the prefix **without** `applyLikedSnapshot` / `likeOverrides`:

```swift
tracksByContext["liked"] = prefix.tracks
likedIDs.formUnion(prefix.tracks.map(\.id))
likedCount = prefix.total
```

`restoreUserAndLibrary` starts this fetch at login in parallel with home/search hearts. Saved Albums and Followed Artists always apply the first page through the override-aware cache. Liked Songs does not.

Comment at 659 (“Do not replace likedIDs”) is already violated by `formUnion`.

**Failure:** login prefix is in flight; user unlikes a recently-played track from the player bar; prefix returns; heart fills again and the liked page still lists the row. If the tail fetch then fails, the wrong state sticks.

#### H4 — Shipped app does not prohibit a second process

- **File:** `NanyinApp/Info.plist`
- **Also:** `NanyinApp/NanyinApp.swift` (`WindowGroup` only)

No `LSMultipleInstancesProhibited`. No unique-instance guard in `AppDelegate`. `build_and_run.sh` kills `Nanyin.app` before launch; the notarized app users actually run does not.

AGENTS.md hazard #6: two processes share `device_id` and open two dealer connections for one Connect identity.

Finder/Dock usually reactivates; `open -n`, a leftover `dist/` copy next to `/Applications`, or Debug + Release side by side do not.

**Fix:** set `LSMultipleInstancesProhibited` to `true`. Optionally activate the existing instance and exit.

**Failure:** two Nanyin binaries running; both persist the same Keychain device id; Connect state becomes ambiguous.

---

### Medium

#### M1 — Rebuild leaves the position clock running

- **File:** `rust/src/lib.rs:350`

`nanyin_init_player` rebuild bumps `PLAYER_GENERATION` and takes Spirc/session/player, but does not `stop_position_clock()`. `nanyin_shutdown` does (`lib.rs:604`). `PlayerBar` interpolates `Core.positionMs` while `IS_PLAYING` is true, so the bar can run for the whole handshake (up to 30s) on a player that no longer exists.

#### M2 — `nanyin_shutdown` `block_on`s from MainActor with no timeout

- **File:** `NanyinApp/State/AppModel.swift:1851`
- **Also:** `rust/src/lib.rs:611`

Quit and sign-out call `Core.shutdown()` on `@MainActor`. Init was moved off the UI thread because accesspoint stalls froze login for 95s+. The goodbye path still has that shape. Cancelled init already shuts down on `initQueue` — quit/sign-out should too, with a timeout.

#### M3 — Liked prefix always adopts server `total`

- **File:** `NanyinApp/State/AppModel.swift:480`

`applyLikedSnapshot` sets `likedCount` from the snapshot `total` ± overrides, with no `countedInServerTotal`. Saved Albums refuse to adopt a prefix total unless every override is confirmed by that prefix (`testPartialPrefixDoesNotDoubleAdjustRemovalCount`). A lagged `total` plus an unlike still present in the first page double-decrements the sidebar count.

#### M4 — In-flight like writes ignore a confirming snapshot

- **File:** `NanyinApp/State/AppModel.swift:516`

```swift
guard !activeLikeMutations.contains(id) else { continue }
```

Albums/artists call `observeConfirmedState` when a snapshot already shows the desired membership (`testNewerServerObservationWinsOverFailedWrite`). Likes never do. PUT can succeed, prefix can already contain the track, then a transport error rolls the heart back to the pre-click state.

#### M5 — Expired like overrides are dropped before a prefix apply

- **File:** `NanyinApp/State/AppModel.swift:477`

`applyLikedSnapshot` starts with `pruneExpiredLikeOverrides()`. A settled unlike past the 30s lag window is gone, then a prefix that still lists the track resurrects it. Albums keep expired overrides through prefix paints and only discard them in front of a complete snapshot.

#### M6 — Liked Songs pagination has no completeness check

- **File:** `NanyinApp/Core/SpotifyClient.swift:588`

Offset walk advances by `pageSize` even on short/empty pages, then `refreshLiked` marks `serverSnapshotIsComplete: true`. That sticky-completes `likedSnapshotComplete` (probes stop) and can confirm an unlike because the id was missing from a gapped list. Saved Albums require totals to match, unique ids, and a prefix re-read.

#### M7 — Album rollback drops count compensation that artists keep

- **File:** `NanyinApp/State/AppModel.swift:979`

Followed-artist rollback keeps an override when `confirmedFollowed != countedInServerTotal` (`testFollowedArtistsRollbackRetainsCountCompensation`). Album rollback always `forgetAlbumSaveOverride`. Empty library → save succeeds → user already toggled remove → remove fails → row restored, sidebar count stays 0.

#### M8 — LIVE scripts do not serialize `Nanyin.app` with `dealer_test`

- **File:** `script/build_and_run.sh:19`
- **Also:** `script/dealer_probe.sh:120`

`build_and_run.sh` only pgreps `Nanyin.app`. `dealer_probe.sh` releases the playback-refresh lock (`exec 9>&-`) before the 300s idle, then execs `dealer_test`. A LIVE app launch during a probe is two dealer sessions on one account. If the probe was given the Keychain device id, it is hazard #6; otherwise it is still two automated Connect devices (hazard #8).

#### M9 — OAuth form bodies use `urlQueryAllowed`

- **File:** `NanyinApp/Core/SpotifyAuth.swift:449`

`application/x-www-form-urlencoded` encoding leaves `+`, `&`, `=` unescaped. A refresh or authorization-code token containing `+` is sent as space. Spotify answers `invalid_grant`; the coordinator treats that as revoked and **deletes** the stored refresh token.

This may never fire if Spotify only issues URL-safe tokens. If it does fire, it looks like “credential expired” and is unrecoverable without a full interactive sign-in.

**Fix:** encode with a form-urlencoded set (unreserved minus `+`), not `CharacterSet.urlQueryAllowed`.

#### M10 — Stall recovery is one-shot per play request

- **File:** `NanyinApp/Audio/PlaybackStallDetector.swift:53`

`recoveredAttempt` is not cleared by `suspend()`. A successful local seek recovery then a second stall on the same `playRequestID` is ignored. `failAudioStallRecovery` only reconnects when a deferred rebuild is already queued; otherwise the UI stays “playing” over silence.

One recovery per request is what prevents a seek storm. After a *confirmed* recovery, allow another attempt (or a budget), and keep the “never loop on a dead request” test.

#### M11 — Render callback takes `NSLock`

- **File:** `NanyinApp/Audio/AudioRenderer.swift:237`

The CoreAudio I/O thread holds the same `NSLock` as `write` (up to 4096-float copies) and `stop`. Not a proven AB-BA deadlock (`write` releases before `wait()`), but it is priority inversion on the real-time thread.

#### M12 — Sparkle private-key export is only cleaned on `RETURN`

- **File:** `script/package_release.sh:304`

`trap 'rm -f "$private_key_file"' RETURN` does not run on SIGINT/SIGTERM during `generate_appcast`. `build/release/.sparkle-private-key` is the Ed25519 key installed apps trust via `SUPublicEDKey`. Use `EXIT INT TERM`.

---

### Low

#### L1 — `notify_connected` can run after the generation was replaced

- **File:** `rust/src/lib.rs:587`

Publish is fenced; `notify_connected` / `Ok(())` are not. Swift currently drops the late success via `initGeneration` / `isCurrentPlayback`. Re-check under `PLAYER_LIFECYCLE` before notifying, to match the AGENTS.md publication rule.

#### L2 — Failed `engine.start()` never signals a blocked writer

- **File:** `NanyinApp/Audio/AudioRenderer.swift:119`

`running = true` is set before `engine.start()`. On failure it is cleared without `spaceAvailable.signal()`. Latent if `Sink::write` can run during start.

#### L3 — Failed `Spirc::new` drops `Session` without `shutdown()`

- **File:** `rust/src/lib.rs:486`

Timeout / auth-error returns before publish. The cancelled-publish path does call `session.shutdown()`. A handshake that registered the device and then timed out skips Connect goodbye until process teardown. Next init reuses the stable device id (not a PID zombie flood), but it is a dirty disconnect during penalty-window retries.

#### L4 — Example binaries can mint PID device ids

- **File:** `rust/examples/dealer_test.rs:20`
- **Also:** `rust/examples/init_test.rs`

`dealer_probe.sh` always passes a device id (default `nanyin_probe_check`). Running `dealer_test` without argv[2] uses `nanyin_probe_{pid}`. Require the argument; do not invent a PID id.

#### L5 — Refresh / access tokens appear on process argv

- **File:** `script/dealer_probe.sh:96`
- **Also:** `dealer_test` argv[1]

`curl -d "refresh_token=$RT"` and `"$BIN" "$TOKEN"` leak credentials to `ps`. Pass via stdin/env.

#### L6 — `AppModel.start()` is not idempotent

- **File:** `NanyinApp/NanyinApp.swift:64`

`WindowGroup.onAppear` calls `start()`. Concurrent calls share the token coordinator's in-flight refresh, and the first completion changes `authState`, so later completions do not run `restorePlayback` again. A call after `.loggedIn` still enters `refreshAccessToken(for: .web)` before its eventual state guard and then discards the result. A started guard would avoid that redundant refresh, but this is not duplicate playback initialization or a second Connect identity.

#### L7 — Overnight invalid sessions are not rebuilt on foreground

- **File:** `NanyinApp/NanyinApp.swift:32`

`applicationDidBecomeActive` only refreshes library probes. AGENTS.md already records the hardening: session age of several hours should re-init before the first click. Current recovery is still “first activate after another device played may ghost, then reconnect.”

#### L8 — No App Sandbox; Keychain items have no ACL

- **File:** `NanyinApp/Core/KeychainStore.swift:24`
- **Also:** `docs/distribution.md:44`

Documented. Same-user `security find-generic-password` can read refresh tokens (`dealer_probe.sh` already does). Not a regression vs the distribution plan; record it as shipping posture.

#### L9 — Sparkle feed is GitHub `latest/download`

- **File:** `NanyinApp/Info.plist:29`

Integrity is EdDSA on the archive, not on the XML. Availability/retarget risk only. Matches `docs/distribution.md`.

## Test coverage

`Tests/StateReducerTests.swift` (~1954 lines) is the right shape: pure reducers, no Keychain, no Spotify. It covers membership, album/artist caches, playlist merge, stall classification, pending-play, reconnect deferral, home decode, and credential-revision fencing.

Gaps that match the findings above:

| Missing test | Why it matters |
|---|---|
| Now Playing seek units | H1 would have been a one-liner: `positionTime` seconds vs `durationMs` |
| `nanyin_resume` activates when not active | H2 is an FFI contract; a mock Spirc or a documented assertion belongs next to the load-path tests |
| Liked prefix + in-flight unlike | H3/M3/M4/M5 live in `AppModel`, not a reducer, so they have no deterministic test |
| Liked pagination completeness | Albums have `isCompleteSnapshot` / prefix re-read tests; likes do not |
| Album rollback count compensation | Artists already have `testFollowedArtistsRollbackRetainsCountCompensation` |
| Form-urlencoded escaping | M9 is a single encoding test |

Rust unit tests already cover typed `-4`, device-id rejection, generation-vs-rebuild, and position interpolation. Keep those.

## AGENTS.md checklist

| Rule | Result |
|---|---|
| Reconnect must not refresh after generic network/TLS/timeout/init failure | Pass |
| Sign-out must win over in-flight replacement tokens | Pass |
| Events / init results must not publish after generation replacement | Pass for player events; L1 for `notify_connected` |
| Stable device id in production | Pass |
| Never auto-open a browser from error paths | Pass |
| Web API vs keymaster split | Pass |
| Persist replacement refresh tokens | Pass |
| Liked Songs: last confirmed server state + latest non-expired local intent | **Fail** (H3, M3–M6) |
| `activate()` before commands that require Active | **Fail** for resume/next/prev (H2) |
| One running instance | **Fail** for the shipped app (H4); scripts only cover `Nanyin.app` (M8) |
| UI 60Hz rules | Pass |
| Vendored librespot patches | Pass |

## Suggested order of work

1. **H1 + H2** — lock-screen seek and `activate()` on resume/next/prev. Small, user-visible, M2-complete claims.
2. **H3 + extract Liked Songs to the same cache pattern as albums** — also closes M3–M6 if the reducer is the one albums already test.
3. **H4** — `LSMultipleInstancesProhibited`.
4. **M1 + M2** — rebuild clock freeze; shutdown off MainActor.
5. **M8 + L4 + L5** — LIVE script occupancy and token argv (agents hit these, users do not).
6. **M7** — album rollback count, copy the artist compensation.
7. **M9** — form encoding, plus a unit test.
8. **M10–M12, L-series** — as encountered.

Do not “upgrade” librespot off the vendored path until PR #1741 is merged upstream. That remains a silent way to re-enter the connect-state echo loop.
