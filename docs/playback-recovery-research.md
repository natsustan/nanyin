# Playback recovery research

Research snapshot: 2026-08-21. Revisions inspected: librespot `9c7d756`, go-librespot `cddcada`, NullSpot `2b8d318`, and cliamp `6164a26`. The psst-main and spotiglass-main directories are source snapshots without independent Git metadata.

## Executive conclusion

The six trees do **not** provide one inherited, end-to-end cure for Nanyin's symptom. A dealer/AP reconnect repairs the control plane; it does not prove that the current CDN range reader and decoder are making progress. This matters when PCM stops near 1:06 while Spirc and `Session` remain valid and the renderer consumes silence.

The strongest data-plane designs are:

* current librespot retries missing ranges after a bounded wait and turns decoder/read failure into `EndOfTrack`, which Spirc advances; it does not expose a dedicated `AudioStalled` event or reload the same track at its position (`audio/src/fetch/mod.rs:227-252`; `playback/src/player.rs:1551-1574`; `connect/src/spirc.rs:781-789`);
* go-librespot retries each CDN chunk, tries alternate CDN URLs during stream creation, and quarantines failed CDN hosts, but source evidence shows no same-track mid-stream reconstruction after the chunk retry budget is exhausted (`audio/chunked-reader.go:150-199`; `player/player.go:600-642`);
* cliamp explicitly detects no-progress reads and rebuilds a stream with exponential backoff, but restarts the selected item rather than demonstrating Spotify-context restoration at the exact position (`player/decode.go:132-166`; `ui/model/update.go:147-165,209-224`);
* psst has an independent ranged-download/cache architecture. A failed range becomes requestable again, but a blocked reader waits without a timeout; therefore its retry is demand-driven and can still wait indefinitely if no successful retry wakes it (`psst-core/src/player/file.rs:235-292`; `psst-core/src/player/storage.rs:255-276`).

The smallest safe Nanyin design is consequently a **bounded data-plane progress watchdog**, separate from session reconnection: detect that playback is expected but decoded position/PCM progress has stopped, first issue one same-track seek/reload at the last confirmed position using the existing Spirc context, then escalate to a generation-safe full player rebuild only if that fails. Do not refresh credentials for this generic transport failure, and rate-limit recovery.

## Scope and terminology

* **Data plane:** CDN/range fetching, decrypting, decoding, PCM delivery, buffering, and audio-output progress.
* **Control plane:** AP/session, dealer WebSocket, Spirc/Connect state, commands, and queue/context resolution.
* “Client-specific” below means code outside the upstream library's generic behavior. Absence claims are limited to the inspected first-party source; they are not claims about Spotify's undocumented server behavior.

## Project findings

### 1. librespot

#### Data-plane behavior (inherited by Spirc clients)

librespot streams audio as requested byte ranges. A failed or incomplete request subtracts its missing bytes from the `requested` set, making them eligible for a later request (`audio/src/fetch/receive.rs:128-149`). Blocking fetch waits use `download_timeout`; if no download status changes, they return `WaitTimeout`, while a status change with the range still incomplete requests the range again (`audio/src/fetch/mod.rs:227-252`). During ordinary streaming it chooses larger chunks from measured throughput and concurrently requests missing ranges; the source still contains a TODO to refresh an expired CDN URL (`audio/src/fetch/receive.rs:178-231`). A 429 honors `Retry-After`, but the current request then returns a status-code error rather than looping in place (`audio/src/fetch/receive.rs:84-99`).

Initial URL selection is stronger than mid-stream failover: opening a stream bounds each candidate URL's first response at ten seconds and tries the next URL on failure (`audio/src/fetch/mod.rs:444-478`). Once selected, subsequent requests use the stored CDN URL; no source here proves rotation to another URL after a mid-track failure.

At player level, load failure emits `Unavailable` (`playback/src/player.rs:1404-1412`). A packet-read or sample-decode error emits `EndOfTrack`, not “stalled” and not “retry current track” (`playback/src/player.rs:1551-1574`). Spirc handles `EndOfTrack` by selecting repeat-current or advancing to the next track, and handles `Unavailable` by marking/skipping it (`connect/src/spirc.rs:781-789,875-880`; `connect/src/spirc.rs:1697-1702`). Thus a surfaced error preserves the broader Connect queue/context through Spirc, but sacrifices the failed track; it does not resume that track at the last position.

The risky gap for Nanyin is an error that never surfaces. The player calls the blocking decoder on its poll path and only reacts to `Ok`/`Err` (`playback/src/player.rs:1456-1575`). Although the range wait is bounded, there is no explicit decoded-position/PCM no-progress event in this path. Audio preloading before playback/seek waits for read-ahead (`playback/src/player.rs:2464-2483`), but that is not a mid-track watchdog.

#### Control-plane behavior

The dealer reconnect loop reconnects after either WebSocket task ends and waits a fixed ten seconds after connect failures (`core/src/dealer/mod.rs:662-716`; reconnect interval declaration at `core/src/dealer/mod.rs:57`). This preserves subscription objects, but it is independent of audio download progress.

When Spirc itself disconnects, it clears the context resolver, marks playback stopped/inactive, and emits `SessionDisconnected` (`connect/src/spirc.rs:1311-1324`). `PlayerEvent::SessionDisconnected` is merely an event emitted by a player command (`playback/src/player.rs:2353-2367`); upstream player code shown here does not reconstruct the session, queue, or current stream. That responsibility belongs to the embedding client.

### 2. go-librespot

#### Data-plane behavior (library)

`HttpChunkedReader` splits the file into chunks, eagerly obtains the first chunk and total size, and prefetches following chunks (`audio/chunked-reader.go:84-135,252-278`). Each chunk request retries three times with a one-second constant backoff; transport errors retry, closure is permanent, and unexpected HTTP status also retries (`audio/chunked-reader.go:150-184`). Body-read failure is returned after the request stage and is not retried inside `downloadAndRead` (`audio/chunked-reader.go:186-199`).

Stream creation tries every CDN URL. A host that fails reader construction is quarantined for 15 minutes and skipped when alternatives exist (`player/player.go:37,600-642`). This is client/library-specific go-librespot behavior, not inherited from Rust librespot. Cached complete encrypted audio bypasses CDN resolution; successful full downloads are cached best-effort (`player/player.go:825-876`). A new stream accepts a media position and seeks after decoder construction, so the primitive required for same-track recovery exists (`player/player.go:737-747,942-958`). Source inspected does not show automatic invocation of that primitive after a mid-stream read failure.

The daemon preserves Connect context in its own state and skips unplayable current tracks. `loadCurrentTrackOrSkip` only skips restricted/unsupported/audio-key failures, while other load errors return (`daemon/controls.go:344-365`). Natural player end reports `OnPlayerEnd` and advances via daemon controls (`daemon/controls.go:196-211`). This is not evidence of a mid-track same-item retry.

#### Control-plane behavior

Dealer receive failure closes the socket and reconnects with the `cenkalti/backoff` exponential policy; a successful reconnect keeps receiver channels alive (`dealer/dealer.go:185-274,296-306`). Again, that loop does not touch the current audio reader or player queue. AP/session lifetime is managed separately, so dealer recovery must not be counted as audio-stall recovery.

go-librespot has no Rust `PlayerEvent::EndOfTrack`, `Unavailable`, or `SessionDisconnected` variants; those names are librespot APIs. Equivalent behavior is daemon/player callbacks and errors, so claiming direct handling of those variants would be incorrect.

### 3. NullSpot

NullSpot embeds Rust librespot and therefore inherits the range fetching and Spirc advance behavior above. Its own bridge adds extensive **control-plane** recovery, not a demonstrated PCM-stall cure.

Its “soft reconnect” intentionally retains Player/Mixer and the already-loaded audio stream while replacing Session and Spirc, then swaps the new session into the existing player for future loads (`rust/src/lib.rs:1194-1224,1243-1266`). This is ideal for a control-plane interruption while healthy audio continues, but by design it also retains a stuck decoder/download pipeline. It cannot by itself repair Nanyin's reported silent renderer.

The client event listener relies on Spirc for `EndOfTrack` auto-advance and only resets local UI state (`rust/src/lib.rs:1487-1492`). No `PlayerEvent::Unavailable` arm was found in the bridge source, so handling is inherited from Spirc rather than client-specific. On `SessionDisconnected`, generation-stale events are ignored; otherwise NullSpot marks disconnected and starts its reconnect loop unless sleeping/shutting down (`rust/src/lib.rs:1620-1644`). A command-side guard also detects `Session::is_invalid()` zombie sessions and triggers reconnection (`rust/src/lib.rs:1787-1814`). These are session-health checks, not audio-progress checks.

Queue/context preservation comes from retaining Player plus Spirc/Connect state during soft reconnect and reactivating only if it was previously active (`rust/src/lib.rs:1256-1277`). In contrast, Swift's force-reinitialize explicitly says the new Rust player has no loaded track/context and clears URI, duration, and position (`NullSpot/ViewModels/PlaybackViewModel.swift:158-185`). That is clear evidence that a hard rebuild needs explicit context restoration if seamless recovery is desired.

### 4. cliamp

cliamp is not a Spotify Connect endpoint and does not consume librespot's Rust player events. Its relevant behavior is its generic player plus a custom go-librespot-based Spotify provider.

For live HTTP streams, every blocking read has a ten-second timeout that cancels the request, surfaces `StreamErr`, and intentionally drives UI auto-reconnect (`player/decode.go:132-166,181-211`). Its buffered/download path separately stores arriving bytes and returns an error after five seconds with no progress; deadlines reset whenever bytes arrive, so slow but progressing transfers are tolerated (`player/nav_buffer.go:13-17,76-140`). Seek waits use the same progress-sensitive timeout (`player/nav_buffer.go:143-207`). This is the clearest source-backed distinction between a data-plane stall and a control-plane failure among the clients.

The UI polls `StreamErr`; stream-like items get at most five rebuilds with 1/2/4/8/16-second backoff. On the deadline it stops the player and calls `playTrack` for the currently selected track (`ui/model/update.go:147-165,209-224`). Success resets the retry state (`ui/model/update.go:639-657`). This preserves the playlist selection/queue model, but the cited path does not seek to the previous position, so exact mid-track continuity is not established. Normal drain advances the playlist (`ui/model/update.go:280-295`), while playlist methods preserve queued/current indices and skip unavailable tracks (`playlist/playlist.go:560-590,592-647`).

For Spotify stream **creation** only, the provider classifies audio-key errors as authentication failures, performs one silent session replacement, then retries `NewStream`; cancellation/deadline errors are deliberately not classified as auth (`external/spotify/provider.go:410-420,427-488`). The session swap builds the replacement before atomically replacing and closing old resources (`external/spotify/session.go:630-670`). This is control/auth recovery and does not prove repair of an already-open Spotify stream after a CDN stall.

### 5. psst-main

psst does not use librespot playback/Spirc. It has its own session, CDN, ranged temporary-file storage, decoder worker, queue, and audio output.

Opening a streamed file resolves one CDN URL, downloads an initial 6 KiB range to learn total length, and creates a sparse temporary backing file (`psst-core/src/player/file.rs:199-232`). The storage tracks `downloaded` and `requested` ranges and wakes blocked readers when bytes are written (`psst-core/src/player/storage.rs:38-58,240-253`). Range requests run on independent threads. On failure, psst logs and removes the range from `requested`, allowing a later demand to request it again (`psst-core/src/player/file.rs:235-292`). Expired URLs are refreshed before spawning a new range request (`psst-core/src/player/file.rs:235-253`).

However, the blocked-reader wait loop uses an unconditional condition-variable wait and has no timeout/error channel (`psst-core/src/player/storage.rs:255-276`). The streaming service only logs a `Blocked` request (`psst-core/src/player/file.rs:281-290`). Therefore source supports retry eligibility, not bounded autonomous recovery: after a failed download, no explicit delayed retry/backoff or terminal playback error is propagated through this wait path.

Decoded samples flow through a producer/consumer ring buffer; a dedicated audio-priority worker is used to reduce CPU-induced underruns (`psst-core/src/player/worker.rs:115-162,274-308`). The public player event model does include `Blocked` and `EndOfTrack`, but not librespot's `Unavailable` or `SessionDisconnected` (`psst-core/src/player/mod.rs:435-483`). Loading failures skip tracks until a consecutive-failure limit, then stop (`psst-core/src/player/mod.rs:127-146`). End-of-track/queue state lives in the independent player queue: loading a queue retains the vector and position, and player transitions load current/following items (`psst-core/src/player/mod.rs:200-214,216-285`; `psst-core/src/player/queue.rs:41-113`).

The session module reports `Error::SessionDisconnected` when request channels vanish (`psst-core/src/session/mod.rs:97-110,237-257`), but no source inspected connects that error to restoration of an in-progress item. Since CDN audio is HTTP/range based and independently buffered, AP session reconnection and data-plane recovery remain separate concerns here too.

### 6. spotiglass-main

Spotiglass does **not** integrate go-librespot in this revision. Its README explicitly identifies Spotify Web Playback SDK playback in a hidden `WKWebView` (`README.md:7-9,21-25`). The host constructs `Spotify.Player`, forwards SDK `ready`, `not_ready`, initialization/auth/account/playback errors and state changes to Swift, and exposes only SDK commands (`Spotiglass/Playback/Resources/SpotifyPlaybackHost.html:35-56,101-146`). Thus download buffering/CDN retry behavior belongs to Spotify's opaque SDK, not to Spotiglass UI and not to go-librespot; this tree provides no first-party source evidence for the SDK's internal mid-track behavior.

Client-specific recovery is connection-host recovery. `not_ready` clears the device/next tracks and invokes recovery; initialization errors also invoke recovery, while `playback_error` offers transfer retry (`Spotiglass/Playback/Session/PlaybackSessionViewModel+WebPlaybackEvents.swift:23-34,52-79`). Recovery tries `connect`, then disconnect/connect, then a budgeted host reload (`Spotiglass/Playback/Session/PlaybackSessionViewModel+SessionLifecycle.swift:118-196`). Manual/hard start reloads the host, sets auto-resume intent, and reconnects (`...+SessionLifecycle.swift:5-28`). These are useful control-host measures but there is no decoded-PCM progress watchdog in the cited code.

Queue/context is partly SDK/server owned: state events expose `next_tracks` (`SpotifyPlaybackHost.html:74-98`), while a host restart loses local `deviceID`; Swift may transfer playback from a stale Spotiglass device on the next `ready` event (`...+WebPlaybackEvents.swift:7-21`). This is not evidence of deterministic local queue restoration after an audio stall.

## Comparison

| Project | Mid-track no-progress detection | CDN/download failure handling | End/unavailable equivalent | Dealer/session recovery | Context/queue preservation | Data-plane recovery verdict |
|---|---|---|---|---|---|---|
| librespot | Bounded range-status wait, no explicit PCM watchdog | Re-request missing range; alternate URL only at open | Decode/read error becomes `EndOfTrack`; `Unavailable` skips | Dealer fixed 10 s reconnect; embedding handles session event | Spirc queue survives ordinary track skip | Partial; skips rather than resumes |
| go-librespot | No explicit playback-progress watchdog found | 3 chunk retries; URL failover and 15 min host quarantine at open | Daemon end/skip callbacks, not Rust events | Dealer exponential reconnect | Daemon Connect state retained | Partial; no proven same-track rebuild |
| NullSpot | None found | Inherits librespot | End inherited; no client `Unavailable` arm found | Generation-safe soft reconnect and zombie detection | Soft reconnect retains player; hard reset loses context | Control-plane only for reported symptom |
| cliamp | 10 s live-read / 5 s buffered no-progress timeout | Error surfaces to five exponential rebuild attempts | Drain advances; unavailable tracks skipped | Spotify session reconnect only for typed auth-like stream creation error | Playlist selection retained; exact position not proven | Strong generic rebuild, not exact resume |
| psst-main | `Blocked` event, but unbounded condvar wait | Failed range made requestable; expired URL refreshed; no backoff found | Independent `EndOfTrack`; load failures skip/stop | Session errors exist; no in-progress restoration found | Independent queue vector/index retained | Retry-capable but can hang |
| spotiglass-main | None in first-party code | Opaque Web Playback SDK | SDK state/error events only | UI connect/reset/reload budget | SDK/server queue; local restoration not deterministic | Neither go-librespot nor first-party audio recovery |

## Implications for Nanyin

1. **Do not use `Session::is_invalid()` as the stall oracle.** NullSpot proves why: a loaded track can keep playing without Session, and soft reconnect deliberately retains Player (`NullSpot/rust/src/lib.rs:1194-1224`). The inverse is also true for Nanyin's symptom: Session can remain valid while audio is dead.
2. **Observe progress at two points.** Track decoder/player position distinguishes a stalled source from an output-only issue; renderer PCM/non-silent-frame progress distinguishes decoder starvation from CoreAudio output failure. A renderer that keeps filling silence must not count silence callbacks as healthy media progress.
3. **Reuse existing librespot recovery before inventing transport code.** Its downloader already re-requests missing ranges (`librespot/audio/src/fetch/mod.rs:227-252`). Nanyin should first establish whether the 1:06 case reaches `WaitTimeout`, decoder error, `EndOfTrack`, or none. Logging these boundaries is safer than replacing vendored behavior.
4. **Do not map a generic CDN stall to authentication refresh.** cliamp explicitly excludes cancellation/deadline errors from auth classification (`cliamp/external/spotify/provider.go:410-420`). Nanyin's documented token discipline requires the same separation.
5. **Preserve server-resolved context.** Re-uploading a large URI queue is both unnecessary and hazardous for this repo. Recovery should command the existing Spirc/current context where possible, not reconstruct a large client-side queue.

## Smallest safe recommended design

1. Add telemetry first: monotonic timestamps/counters for last decoded position change, last non-empty PCM delivery from librespot, last renderer consumption, downloader timeout/error, and current generation/play-request ID.
2. Arm a watchdog only when the current generation is active, expected to be playing, not paused/seeking/loading, and not within startup/track-transition grace. Trigger only when **both** decoded position and media PCM have made no progress for a conservative interval (for example 10–15 seconds). Renderer callbacks containing inserted silence do not reset it.
3. First recovery, once per play request: capture current URI/context and last confirmed position; ask the existing Player/Spirc to seek to that position (or a tiny bounded offset) so librespot reissues range demand. Do not reconnect dealer/session and do not refresh a token.
4. If no progress resumes within a second bounded interval, reload the same current track at the captured position through the existing Spirc context. Keep repeat/shuffle/next/previous state owned by Spirc; do not upload the queue.
5. Only after the local data-plane attempt fails, perform Nanyin's existing generation-safe player rebuild using the current access token, then restore the server-resolved context/current URI and position. Validate generation atomically so stale completion/events cannot publish.
6. Apply stop-loss: one local retry plus one rebuild per track within a cooldown, exponential delay for subsequent failures, and stop with a visible error instead of a reconnect storm.

This is smaller and safer than immediately rebuilding Session: it directly targets the failed plane, preserves Connect context in the common case, and avoids token/dealer traffic when Spotify control state is healthy.

## Open uncertainties

* The source alone does not identify why Nanyin stalls specifically near 1:06. Required runtime evidence is the last successful CDN range, downloader status changes, decoder return/block state, and PCM callback counts. No live Spotify command was run for this research.
* librespot's `download_timeout` value is derived from ping-related fetch parameters (`audio/src/fetch/mod.rs:97-114`); whether the observed path is blocked inside that wait, HTTP body collection, decoder, or Nanyin's sink requires instrumentation.
* go-librespot's chunk code retries request creation/status but not `io.ReadAll` body failure in the same function (`audio/chunked-reader.go:150-199`). Whether a decoder re-read later causes another chunk fetch depends on caller behavior not proven as an automatic recovery policy.
* psst's removal of failed ranges permits another request, but its blocking callback fires only once per `wait_for` call and waits indefinitely (`psst-core/src/player/storage.rs:255-276`). A race may cause demand elsewhere to retry; no bounded guarantee exists.
* Spotify Web Playback SDK internals are unavailable in spotiglass's first-party source, so no CDN/buffering claim can be made for it.

## Files inspected

Key files read (searches also covered all first-party `.rs`, `.go`, `.swift`, and playback host HTML files for the named recovery terms):

* librespot: `audio/src/fetch/mod.rs`, `audio/src/fetch/receive.rs`, `playback/src/player.rs`, `connect/src/spirc.rs`, `connect/src/state/tracks.rs`, `core/src/dealer/mod.rs`, `core/src/http_client.rs`, `core/src/connection/mod.rs`.
* go-librespot: `audio/chunked-reader.go`, `player/player.go`, `player/source.go`, `player/stream.go`, `daemon/player.go`, `daemon/controls.go`, `dealer/dealer.go`, dealer tests.
* NullSpot: `AGENTS.md`, `rust/src/lib.rs`, `NullSpot/SpotifyPlayer.swift`, `NullSpot/ViewModels/PlaybackViewModel.swift`, `NullSpot/Store/Services/ConnectionService.swift`, `NullSpot/Store/Services/QueueService.swift`.
* cliamp: `player/decode.go`, `player/nav_buffer.go`, `player/player.go`, `player/pipeline.go`, `player/ffmpeg.go`, `player/gapless.go`, `ui/model/update.go`, `playlist/playlist.go`, `external/spotify/provider.go`, `external/spotify/session.go`, stall/player tests.
* psst-main: `psst-core/src/player/{file,storage,worker,mod,queue,item}.rs`, `psst-core/src/{cdn,error}.rs`, `psst-core/src/session/mod.rs`, `psst-gui/src/controller/playback.rs`, `psst-gui/src/data/playback.rs`.
* spotiglass-main: `README.md`, `Spotiglass/Playback/Resources/SpotifyPlaybackHost.html`, `Spotiglass/Playback/SpotifyPlaybackBridge.swift`, and playback session lifecycle/event/timer/transport/command files.
