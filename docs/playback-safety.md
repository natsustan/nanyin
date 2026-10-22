# Playback traffic policy and spotifast comparison

Reviewed 2026-09-29 against spotifast commit
[`1bf060ca58b089b903699497bd418f77107a73d2`](https://github.com/crmne/spotifast/tree/1bf060ca58b089b903699497bd418f77107a73d2).
This is traffic reduction and failure containment, not a guarantee against
account restrictions. A Web API 429, access-point timeout, and dealer disconnect
are different signals; none by itself proves an account ban.

## What was compared

| Area | Reference | Nanyin policy |
| --- | --- | --- |
| Session churn | [backend.rs](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/src/backend.rs): reconnect window and attempt limit | At most six recovery attempts per rolling 10 minutes. Healthy startups do not consume recovery capacity; unfinished attempts survive relaunch. Consecutive failures use 5/15/60/120/300/600-second backoff. Success clears the pending marker and backoff, not recovery history or service holds. |
| Playback commands | [player.rs](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/src/player.rs), [app.rs](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/src/app.rs): explicit load activation and click deduplication | Keep activate-before-load; dispatch one command at a time behind playback confirmation, with a 350ms minimum interval. Pause, sign-out, shutdown and generation changes cancel delayed commands. |
| Web quota | [api/client.rs](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/src/api/client.rs): session-owned cooldown | Share one transport across token refreshes and all Web reads/writes; pace request starts by 150ms, cap concurrent requests at two, and share identical in-flight GETs; preserve the full Retry-After deadline, including the final failed attempt. |
| Credentials and device ownership | [single_instance.rs](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/src/single_instance.rs), [player.rs](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/src/player.rs) | Keep the existing process lock, persisted Keychain device ID, serialized refresh/sign-out coordinator and separate playback/Web token flows. |
| Vendored fixes | [Cargo.toml](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/Cargo.toml): one pinned librespot fork | Keep Nanyin's pinned checkout and all five required patches. Do not replace it wholesale with spotifast's fork. |
| Distribution | [PACKAGING.md](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/PACKAGING.md) and [connection/update notes](https://github.com/crmne/spotifast/blob/1bf060ca58b089b903699497bd418f77107a73d2/docs/_reference/how-it-connects.md) | Keep the existing bundle identity, Sparkle signature verification and inside-out signing; enforce vendor verification in Xcode builds, the Rust build script and release packaging. |

The comparison informed the changes; Nanyin's thresholds are conservative local
choices, not Spotify limits. Spotifast's reconnect limit is six per ten minutes;
Nanyin now uses that six-recovery limit rather than the earlier three-startup limit. Its persisted recovery history and manual retry after failure remain deliberate differences. No spotifast source was
copied. The later session-playlist bridge adds the established range and batch
metadata requests described below; it does not create a new playback session.

The existing `activate()` call was inspected rather than removed blindly:
Nanyin's vendored Spirc ignores Activate while already active, but needs it
before a load when inactive. Spotifast uses the same order. Suppressing duplicate
loads and automatic fallback traffic addresses the avoidable work without
breaking deliberate playback takeover. The existing process lock already
covers both GUI and dealer-probe launches; no second lock or new device identity
was added.


## User-visible behavior

- The first playback selection is immediate. While it is pending, subsequent
  selections replace the queued target; Next/Previous retain their order, up to
  eight waiting commands. Only confirmation of a new matching play request
  releases the next command, at least 350ms after the previous dispatch. An
  eight-second timeout clears pending work without replay. Pause, manual seek, shutdown,
  sign-out, disconnect and deactivation cancel the queue.
- Previous above three seconds seeks to the beginning. Its explicit Seeked
  event can confirm that command without changing the request ID; a later
  Previous below three seconds requires a track transition, so a delayed seek
  event cannot release another command. Queued selections re-resolve the
  selected row before dispatch, or play the selected URI if it disappeared.
- Delayed queue refreshes share one cancellable timer and validate both account
  and playback generation; replaced sessions cannot trigger a later refresh.
- A server-context load is sent once. An eight-second timeout clears buffering;
  it no longer uploads a second track window automatically. Explicit retries
  remain available by selecting playback again.
- Ad-hoc lists use at most 50 tracks. The Rust FFI rejects oversized lists,
  malformed track URIs and out-of-range offsets before activating Connect.
- Once the reconnect budget is exhausted, Nanyin closes the stale core and
  waits for an explicit retry after the displayed interval. It never schedules
  a new timer-driven handshake. Manual retries cannot bypass the budget.
- The existing one-time playback-token refresh is still permitted only after
  a typed access-point credential rejection, within an admitted reconnect cycle.
  Generic network, TLS, dealer and initialization failures never trigger it.
- Web API cooldowns longer than 30 seconds return an error promptly while
  retaining the **full** deadline. Calls during that interval make no network
  request. Short waits are cancellable; network errors and 5xx writes are not
  automatically replayed. An invalidated account's queued requests cannot start.

Spotify explicitly recommends respecting the server's `Retry-After` value for
Web API 429s: [official rate-limit documentation](https://developer.spotify.com/documentation/web-api/concepts/rate-limits).
The previous 30-second clamp could retry earlier than instructed.

Cooldowns and connection admissions are saved atomically to
`~/Library/Application Support/Nanyin/traffic-safety.json`, shared by this
installation across sign-outs, token replacement and app relaunches. Web and
playback have separate service holds; identities/tokens are never stored here.
Using installation scope is deliberately conservative because client quotas and
the stable Connect identity can outlive an account switch. A corrupt or unwritable
store fails closed with a local-storage error rather than dropping the budget.
Same-boot deadlines use uptime and a boot UUID, so changing wall time cannot
shorten them. After an OS reboot, saved durations are retained conservatively;
this can make a long cooldown last longer. There is no background retry timer.

Playback startup persists an unfinished-attempt marker before refreshing a
token, without consuming recovery capacity. Only a successful connection clears
that marker: restarting after failure or a crash remains recovery. Recovery
reserves its budget before authentication. The one refresh after typed rejection
is part of the same attempt, not another unbounded retry path. A blocked startup
can be resumed manually without submitting an empty access token.

Control and CDN response headers now pass through the same checked future:
the first 429 fails without replay and installs a shared service hold. Header
waits and complete control responses have a 15-second deadline. CDN bodies use
a 15-second idle timeout between frames, allowing a progressing download to
last longer. Valid rate-limit headers are combined using the longest delay;
a malformed vendor header cannot mask Retry-After. Missing/invalid headers use
a local 30-second fallback. SpClient uses one attempt instead of ten.

Before the 429 returns to its caller, a synchronous bridge callback writes the
playback hold to the thread-safe local store. This removes the old dependence
on the one-second session watcher for persistence. Storage failure blocks new
Rust HTTP requests; sign-out does not erase a service cooldown. This is not a
promise against power loss or termination before a response has been processed.
The watcher still stops the active session when it detects the hold. The
explicitly authorized dealer probe reserves the same persisted connection
budget before token refresh (exit 7 when blocked), so a diagnostic invocation
cannot bypass a known playback hold.

Web transports share a two-permit request gate across account changes. Identical
GETs (including authorization headers and retry policy) share one in-flight
operation. Mutations remain independent. Cancelling one reader leaves the other
readers intact; cancelling the last reader or invalidating the account cancels
the underlying operation and releases its permit. Cooldown waits release permits,
and the deadline is checked again after every queue wait. CDN futures also
recheck the hold when first polled, before creating the network request, so a
request constructed before a 429 cannot bypass the hold after waiting for a slot. A 429 is recorded before
its request releases the permit.

Recovery only restores the connection. It never replays a pending play/context
load. When another device takes ownership, the session-deactivated event is
emitted before fallible server bookkeeping and clears queued commands, pending
intents and local ownership. It is handled before any track/request filtering.

## Session and build containment

If `Spirc::new` fails or times out after starting background work, Rust explicitly
shuts down that partial session, stops its player and aborts its event listener.
A superseded initialization also tears down its listener. The existing atomic
generation publication and typed credential-error classification remain intact.

`script/check_librespot.sh` validates the pinned revision, six path dependencies,
and all five required patch artifacts. It is called from `rust/build.sh`,
`script/agent_check.sh` and `script/package_release.sh`. Cargo builds use
`--locked` so release packaging cannot silently resolve a different dependency
set. The existing Connect echo-loop, auth classification, audio progress and
handover patches remain required. `vendor_librespot.sh` prepares a clean or
partially patched checkout without resetting existing work.

Release bundles include `Contents/Resources/librespot-build.txt` before signing:
Nanyin revision and worktree diff hash, librespot revision and vendor diff hash,
Rust source hashes, Cargo.lock hash, pinned toolchain and patch hashes. It contains no credentials or device ID. This records core inputs;
it is not a claim that a dirty Nanyin working tree equals its HEAD commit.
Release verification also exposed the macOS 27 Rust proc-macro LINKEDIT stripping
issue. Build-time tools retain debug information and remain unstripped; the
shipped core keeps optimization and LTO. See [distribution notes](distribution.md)
for the upstream issue and removal criterion. Release archiving propagates arm64
to package dependencies as well as the application.

Signing/notarization protect distribution integrity; they do not change Spotify
traffic or provide protection from account restrictions.

## Offline verification

```sh
./script/agent_check.sh
bash Tests/LibrespotBuildGuardTests.sh
# Optional unsigned Release archive and DMG; never launches the app:
./script/package_release.sh
```

`Tests/PlaybackTrafficTests.swift` covers command bursts/cancellation, reconnect
window boundaries, long and date-form Retry-After, shared cooldown across token
replacement, account invalidation, final-attempt 429, and non-replayed failures.
Swift HTTP traffic is intercepted by URLProtocol using synthetic credentials.
Rust HTTP fault tests use only a loopback TCP fixture and assert actual request
counts for 500/429 and replacement-client suppression. Persistence tests cover
relaunch, account/transport replacement, reboot, invalid storage and full delays.
Rust tests reject invalid/oversized loads before consulting any session.
The build guard test uses a disposable local clone and proves an unpatched or
partially patched checkout cannot pass.

Live dealer/playback testing is intentionally separate and still requires the
explicit authorization in AGENTS.md. No production-account probing is part of
these checks. Real playback, multi-device handover and suspected watch-window
behavior cannot be proven by this offline suite.

The `offline-macos.yml` workflow provisions pinned dependencies from a fresh
checkout, runs the same checks and makes an unsigned Release DMG. It never
launches the app or supplies Spotify credentials. Its arm64 `macos-26` runner
matches [GitHub's documented runner architecture](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
The workflow has been added locally; a hosted run has not been triggered here.

## Two follow-up review rounds

Round one added the shared CDN response path, body idle timeout, confirmation
queue and account/generation-scoped delayed refresh. Offline checks and Debug
build passed before round two.

The second review found and fixed ambiguous Previous-to-zero acknowledgements,
queued row-index drift, conflicting rate-limit headers and the delayed cooldown
persistence window. It also added the global Web concurrency gate and shared
GET operations, with cancellation and account replacement fault tests.

The expanded suite verifies actual loopback/CDN 429 responses, control/body
stalls, synchronous persistence before the 429 is returned, preserved relative
skip counts, stale/wrong confirmation events, delayed-refresh cancellation,
HTTP concurrency, independent mutations, token separation and shared-read
cancellation. The final event-order review also covers remote pause while a
command is in flight or waiting for its dispatch interval: it cancels queued
playback, while relative skips deliberately issued from an already-paused state
can still confirm. Real Spotify behavior remains outside these offline checks.

## Playlist follow-up (2026-10-22)

The follow-up compared the same pinned reference's `api/models.rs`,
`api/client.rs` and `session_reads.rs`. The Web playlist endpoint had been
migrated to `/items`, but Nanyin still decoded only `track`. The
[current Spotify response schema](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items)
uses `item` and retains `track` as deprecated. Nanyin now accepts both, preferring
`item`, and keeps null slots until assigning the original playlist position.
Unavailable songs, episodes and local files do not become playable track rows.
Duplicate songs retain distinct original positions. Selecting a visible row
uses its server position, rather than its index in the filtered display array.
A locally appended row without a confirmed position uses the bounded track path.
Album reads now preserve those positions too, and continue after the actual
embedded row count instead of jumping to offset 50. Album metadata enrichment
retains the original position.

Both library and playlist pagination now stop at `next = null`, even when
`total` is stale, and advance by the raw number of returned slots rather than
assuming every page contains 50. A mismatched offset or an empty page that
claims more results fails without replay. No server-provided next URL receives
credentials; requests are still constructed for the fixed Spotify API origin.

Page loads and the playlist library now use the existing one-time Web 401
recovery path. Failed token refreshes propagate instead of silently using a
stale client; a delayed rejection of an old token reuses a replacement already
installed by another request. Page navigation cancels obsolete paginated work,
and account invalidation/quit cancel both page and library reads. Library retry
is explicit and coalesced, and other library sections no longer wait for the
entire playlist list before starting (all share the existing Web request gate).

`Tests/PlaylistReadTests.swift` drives the actual SpotifyClient through a local
URLProtocol fixture: modern/legacy fields, null slots, mixed entry types,
duplicate positions, short and entirely filtered pages, stale totals,
non-progressing responses, fixed Web authorization, album embedded-page
continuation and cancellation. The check
script includes this suite. Positive playback queue assertions now wait for
the observable event with a bounded deadline instead of assuming the host
scheduler will finish in 10–20ms; the timeout/no-replay assertions remain.

### Still requiring evidence

- Session playlist reads were implemented in the later follow-up below.
  Real-account access to external/editorial playlists still needs verification;
  decoder and routing fixtures cannot establish server permissions.
- The Liked Songs position audit and library/playback account binding were
  implemented in the follow-up below; their real-account behavior is still
  part of the live verification scope.
- Real account authorization, playlist access, sustained playback and device
  handover still need an explicitly authorized live verification. Offline
  checks cannot establish account restriction status or smooth audio delivery.

Final verification for this follow-up: `./script/agent_check.sh` passed against
the final source changes on 2026-10-22, including the new playlist/album fixtures,
all Swift suites, 15 Rust tests and the unsigned Debug app build. The initial
offline run exposed missing Cargo cache entries; `script/cargo.sh fetch --locked
--manifest-path rust/Cargo.toml` provisioned those dependencies before rerunning.
No app launch, Keychain credential read or Spotify session was used. Existing
vendored Swift warnings, the deprecated Keychain API warning and a librespot
lint expectation warning remain; they did not fail the build.

## Liked Songs and account binding follow-up (2026-10-22)

Liked Songs now carries raw page continuation and original collection positions,
just like playlist/album rows. Null/unavailable rows no longer shift a click's
server offset or make the next page skip entries. A terminal page is detected
from `next`, not from the count of visible songs. A total that changes between
pages fails as an incomplete snapshot instead of reconciling likes against a
mixed collection.

A refreshed prefix keeps the cached tail visible but invalidates its playback
positions. The previous count-delta shortcut could incorrectly declare that
merge complete, so changed prefixes now finish reading the tail. Until that
succeeds, playback uses the existing bounded track window for unverified rows.
The reconciliation flag survives a failed tail load; an identical subsequent
prefix cannot bless stale tail positions. The unchanged-prefix check compares
both ids and raw positions, and a wholly unavailable prefix supplies no match
anchor. Existing latest-intent overrides and account epoch guards are retained.
A multi-page Web collection still has no server snapshot revision; this does
not claim atomic snapshots across arbitrary simultaneous remote edits.

The GUI playback initializer now passes the canonical Web profile id to Rust.
After Spirc authenticates, Rust compares that id with `Session::username()`
before publishing the player. Spotifast uses the same comparison before session
library reads (`backend.rs::same_account` at the pinned reference revision).
Mismatch closes the partial session, stops its player and aborts its listener;
a healthy existing session belonging to another account is also torn down.
The distinct `-5` result never triggers token refresh or automatic reconnect.
The UI retains library access and explains that both grants need the same
account. New generations cannot emit audio or player events before this check
and publication. The explicit idle probe still has no Web grant and uses its
separate, deliberately unbound initializer; it is never used for GUI playback.

Offline fixtures now cover raw Liked Songs pagination, filtered slots, prefix
position changes, invalidated cached tails and mid-pagination total drift.
Rust verifies identity acceptance/rejection, invalid FFI identity arguments,
non-refresh classification and audio generation admission. No real account
identity or token was used.

The comparison identified a concrete API difference: spotifast's fork adds
[`Playlist::get_range`](https://github.com/crmne/librespot/blob/669e004ec7a79e6eea0f87779efc69680793d3b7/metadata/src/playlist/list.rs)
and `SpClient::get_playlist_range`; Nanyin's pinned vendor has only the full-list
method. Its existing public SpClient request and batched metadata methods can
support the bounded bridge implemented in the following section, without
replacing the pinned vendor or dropping the five safety patches.

Verification for this follow-up: all Swift suites (including the expanded
Liked Songs HTTP fixtures), 16 Rust tests, vendor guards and the unsigned Debug
build passed via `script/agent_check.sh`. The final mismatch path also stops
Swift's output immediately so buffered audio cannot outlive an identity
failure. No app launch or Spotify endpoint probe was performed.

## Session playlist bridge (2026-10-22)

Playlist pages now use an existing, verified playback session when one is ready.
Without one, browsing retains the Web OAuth path. Browsing never initializes a
player. Once a session read starts, refusal, throttling, timeout or malformed
data returns an error without a Web fallback, token refresh or request replay.

`rust/src/playlist_reads.rs` uses the existing public SpClient request method
with the same range shape as spotifast's pinned fork. Each page requests at most
50 raw slots and one TRACK_V4 metadata batch for its unique track URIs. Empty,
local, episode and unavailable slots retain their original context positions;
duplicate tracks remain distinct rows. Swift validates a single revision and
total across every page before caching the result. A changed or incomplete
snapshot asks for an explicit retry.

The bridge checks the canonical account and both Rust/Swift playback generations
before reads and after responses. Navigation cancellation reaches the Rust
future; rebuild and shutdown cancel outstanding reservations. Allocation happens
before dispatch so early cancellation cannot miss registration. At most eight
requests can be reserved; one page performs network work at a time, with 150ms
spacing and a 15-second deadline that includes waiting for that permit. Blocking
FFI work runs on a dedicated concurrent worker queue, away from MainActor.

HTTP 429 retains the existing shared, persisted service hold. Metadata can also
report 429 inside an HTTP-success envelope; the bounded-HTTP patch now exposes
the same synchronous hold recorder for that case. With no Retry-After in that
envelope, it uses a local 30-second fallback and preserves any longer hold.
Persistence failure keeps the HTTP gate closed. Individual metadata 404/451
rows are unavailable songs; provider refusal and incomplete batches fail the
page instead of silently returning an empty playlist.

Offline fixtures exercise the actual Rust protobuf decoder and read pipeline,
bounded reservations, early/in-flight cancellation, queued timeout, generation
replacement, duplicate/null rows, malformed metadata and refusal without replay.
Swift fixtures cover bridge error envelopes and cross-page revision/total
validation. The HTTP loopback suite verifies the shared cooldown recorder.
`./script/agent_check.sh` passed all Swift suites, 21 Rust tests, exact vendor
patch guards and the unsigned Debug app build. Release provenance now hashes
every Rust source module and the C header. No app launch, Keychain credential
read or Spotify request was performed; live authorization, playlist access,
audio continuity and device handover remain unverified.

## Startup versus recovery policy correction (2026-10-22)

The earlier policy incorrectly charged healthy app launches to a three-attempt
budget. That made ordinary development rebuilds block subsequent listening.
Normal startup now checks service holds but does not consume recovery capacity.
Actual recovery permits six attempts per rolling ten minutes, including recovery
from an unfinished or failed startup. Persisting the unfinished marker before
OAuth/handshake prevents restarting from disguising a failed attempt as a healthy
launch. Success clears the marker and consecutive-failure backoff, while keeping
recent recovery history and all service holds.

Consecutive connection failures use 5/15/60/120/300/600-second spacing, matching
spotifast's current backoff values. Nanyin still waits for explicit Retry after a
failed connection or exhausted budget: this change adds no timer-driven network
retry and never replays playback. A dropped established session retains its
existing one recovery attempt, subject to active-audio and foreground rules.

The v1 store could not distinguish successful launches from failures, so the
one-time v2 migration removes only its mixed local attempt/spacing counters.
Web and playback service holds remain intact. V2 recovery state persists across
relaunch/sign-out; malformed or unwritable storage still fails closed. The idle
probe explicitly consumes recovery capacity and cannot use the free startup path.

The notice distinguishes service holds, repeated-failure budget and short
backoff. Its countdown runs locally in the notice view, not in AppModel or the
track list. Retry is disabled until the deadline, then enabled with an explicit
ready message. Tests cover healthy rapid relaunches, six recoveries including
short-lived successes, failed-startup relaunch, increasing backoff, OS reboot,
429 persistence, one-time migration, countdown expiry and very long holds.

Verification: `script/agent_check.sh` passed all Swift suites, 21 Rust tests,
vendor guards and the unsigned Debug build. The signed live launch then used
the existing single-instance script under the user's launch authorization.
Startup logged `player init OK` in approximately 2.54 seconds; the migrated v2
store had zero recovery attempts, `recoveryRequired=false` and `retryStep=0`.
No dealer/spirc failure marker was present in that startup observation. This
verifies startup recovery from the old local lockout, not sustained audio or
handover; no playback clicks were automated.
