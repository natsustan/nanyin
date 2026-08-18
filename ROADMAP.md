# nanyin — Roadmap

> Status: M0 ✅ · M1 ✅ · hardening ✅ · M2 batch 1 (2.1/2.2/2.5) ✅ · M3 in progress (search done, playback verify pending)
> Last updated: 2026-08-18

## Completed

### M0 — Vertical slice (done 2026-08-17)
- Rust core (librespot 0.8-dev @ 9c7d756): session, Spirc, proxy sink → PCM FFI
- Dual-client OAuth in one browser journey (Web API via ncspot client id,
  playback via keymaster) — keymaster's Web API quota is globally 429-limited
- Classic dark UI shell: sidebar / home / player bar
- AudioRenderer: ring buffer + AVAudioEngine + semaphore backpressure

Key lessons (do not regress):
- Never `session.connect()` before `Spirc::new` — Spirc connects itself
  after registering dealer listeners; double-connect = `NotConnected`
- `spirc.activate()` before `load()` — commands are ignored while Not Active
- Large contexts must go through `nanyin_play_context` (server-resolved
  context URIs); uploading 1000+ track URIs gets 429-rejected silently
- Liked Songs context URI: `spotify:user:<id>:collection`
- `TrackChanged` carries full metadata (title/artists/album/cover) — no
  Web API round trip needed on track change

### M1 — Library (done 2026-08-17)
- Sidebar: Liked Songs + real playlists with counts
- Playlist detail: cover header, PLAY button, NSTableView-backed track list
- Context play (double-click plays the context from that row)
- TrackChanged metadata → now-playing bar instant updates

### Hardening pass (done 2026-08-17)
- Web API token auto-refresh (expiry + in-flight dedup), revalidate before loads
- AudioRenderer writer deadlock window closed (running check under lock)
- Engine restart on output-device change (AVAudioEngineConfigurationChange)
- Epoch guard on playlist loads (rapid navigation races)
- Compact one-line Rust event logs

Perf notes:
- Track list = `List` (NSTableView recycling), single scroll region,
  row-local hover state, position tick local to PlayerBar — 60Hz verified
- Do NOT reintroduce: nested ScrollViews, parent-scope hover state,
  AppModel-scope position polling

---

## M2 — Playback completeness (next)

Goal: "usable as the daily driver" — everything the transport bar implies works.

| # | Item | Notes | Est |
|---|------|-------|-----|
| 2.1 | Media keys + MPNowPlayingInfoCenter | MPRemoteCommandCenter: play/pause/next/prev/seek/position; NowPlayingInfo: title/artist/artwork/duration/position. Artwork via NSURLSession → NSImage | 0.5d |
| 2.2 | Shuffle / repeat | `spirc.shuffle(bool)`, `spirc.repeat(bool)`, `spirc.repeat_track(bool)` — FFI surface already exists in librespot; add 3 exports + PlayerBar toggles; reflect state from PlayerEvent::ShuffleChanged/RepeatChanged | 0.5d |
| 2.3 | Queue view | TrackChanged cluster state → expose current queue via FFI (`nanyin_get_queue_json`); queue panel (sidebar page or popover): now playing + upcoming; "add to queue" row context menu via `spirc.add_to_queue` | 1d |
| 2.4 | End-of-track auto-advance edge | Verify context autoplay continues past last track (autoplay variant); fix EndOfTrack handling if the context stalls at the end | 0.5d |
| 2.5 | Track row context menu | Play next / add to queue (needs 2.3), copy song link | 0.25d |
| 2.6 | Seek reliability | Drag-seek while paused; position interpolation after seek (player emits Seeked) | 0.25d |

Exit criteria: media keys + lock screen controls work; shuffle/repeat round-trip
with the phone's Spotify app state; queue visible and manipulable; a 3-hour
listening session with zero silent failures.

## M3 — Search (0.5–1d)

| # | Item | Notes |
|---|------|-------|
| 3.1 | Search page | `/v1/search` (tracks first; type switch tracks/artists/albums/playlists later); debounced-as-you-type (≥300ms) or submit-on-return; reuse TrackListView | |
| 3.2 | Search results context | Play results as ad-hoc context (`nanyin_play_tracks` window — results are small) | |
| 3.3 | Search entry point | ⌘F/⌘K focus; sidebar "Search" page (currently disabled) | |

Progress 2026-08-18: 3.1–3.3 implemented (SpotifyClient.searchTracks, SearchView
with 350ms debounce + ⌘K/⌘F + sidebar entry, results play via nanyin_play_tracks
window). Search verified end-to-end (`search "daft punk" → 50 tracks`, UI shows
results). 3.2 playback verify blocked on an account penalty window — retest
double-click play after the dealer probe survives 300s.

Note: ncspot client id keeps /v1/search working (production-approved app).

## M4 — Polish & completeness

| # | Item | Notes |
|---|------|-------|
| 4.1 | Album / artist pages | `/v1/albums/{id}`, `/v1/artists/{id}/top-tracks`; clickable artist/album in rows and player bar | 1d |
| 4.2 | Likes round-trip | Heart toggle in rows + player bar; `/v1/me/tracks` PUT/DELETE; liked cache invalidation | 0.5d |
| 4.3 | Playlist create/add | `+` in sidebar, context menu "Add to playlist"; `/v1/users/{id}/playlists` + `/v1/playlists/{id}/tracks` (scopes already granted) | 0.5d |
| 4.4 | Playlist search/filter | Client-side filter row in detail view | 0.25d |
| 4.5 | Keyboard navigation | ↑↓ already free via List; Enter = play; Space = play/pause (global) | 0.25d |
| 4.6 | Window: mini-player | Collapsed player-bar-only mode (classic Winamp-ish) | 0.5d |

## M5 — Distribution

| # | Item | Notes |
|---|------|-------|
| 5.1 | Signing + notarization | Developer ID; hardened runtime exceptions (none expected — audio via AVAudioEngine, network via URLSession) | 0.5d |
| 5.2 | Sparkle updates | appcast + delta | 0.5d |
| 5.3 | Release build profile | Rust LTO already on; verify release-vs-debug audio latency; strip symbols | 0.25d |
| 5.4 | DMG / Homebrew cask | | 0.25d |

## Explicitly out of scope (for now)

Spotify Connect as a *remote* (controlling other devices from nanyin — we are
a Connect *device* only), podcasts, lyrics, offline caching beyond librespot's
built-in audio cache, social, multiple accounts, non-macOS platforms.

## Standing engineering notes

- **Borrow, don't reinvent**: NullSpot (MIT) has working implementations of
  media keys, queue callbacks, wake/sleep handling under `NullSpot/Views`,
  `Store/`, `SpotifyPlayer.swift`. cliamp (MIT) documents Web API pitfalls
  (429 semantics, snapshot_id caching, invalid_grant handling). Both vendored
  in `research-repos/`.
- **Token split**: Web API (ncspot id) vs playback (keymaster id) — never mix.
- **Connect state uploads are rate-limited**: batch state changes, avoid
  per-second updates (librespot already throttles; don't force-refresh).
- **UI perf rules**: see "Perf notes" above. New list-like UIs must follow
  the same pattern (List, row-local state, no global position).
- **Debugging**: run the binary with stderr captured — Swift `dlog` + Rust
  `eprintln` both stream unbuffered. `RUST_LOG=info` for librespot internals.
