# nanyin — Roadmap

> Status: M0 ✅ · M1 ✅ · hardening ✅ · M2 ✅ · M3 ✅ · M4.1 ✅ · M4.2 ✅ · M4.3 ✅ · M4.4 ✅ · M4.5 ✅ (offline) · next: M4.6
> Last updated: 2026-08-21

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
- Potentially large track lists use `List` (NSTableView recycling) with one
  vertical scroll region; row-local hover state and a PlayerBar-local position
  tick keep scrolling at 60Hz
- Do NOT reintroduce: same-axis nested ScrollViews, parent-scope hover state,
  or AppModel-scope position polling. Bounded, lazy cross-axis carousels are
  allowed inside the vertical page container

---

## M2 — Playback completeness ✅

Goal: "usable as the daily driver" — everything the transport bar implies works.

| # | Item | Notes | Est |
|---|------|-------|-----|
| 2.1 | Media keys + MPNowPlayingInfoCenter | ✅ done 2026-08-17. MPRemoteCommandCenter: play/pause/next/prev/seek/position; NowPlayingInfo: title/artist/artwork/duration/position. Artwork via NSURLSession → NSImage | 0.5d |
| 2.2 | Shuffle / repeat | ✅ done 2026-08-17. `spirc.shuffle(bool)`, `spirc.repeat(bool)`, `spirc.repeat_track(bool)` exported through FFI with PlayerBar toggles; state reflects PlayerEvent::ShuffleChanged/RepeatChanged | 0.5d |
| 2.3 | Queue view | ✅ done 2026-08-18. Queue page (sidebar + player-bar button): Now Playing + Next Up + Recently Played. Data from `GET /v1/me/player/queue` (server-capped ~20 items), refreshed on track change / add-to-queue / page open; recently-played tracked locally. Add-to-queue round-trip verified live (row context menu → track jumps to front of Next Up). **Dead end recorded:** dealer cluster pushes are NOT available to third-party clients — the dealer websocket rejects client `SUBSCRIBE` frames (`Unsupported message type` close; verified empirically). librespot's spirc cluster listener is effectively dead code on the current server; remote control still works because commands arrive as dealer *requests*. | 1d |
| 2.4 | End-of-track auto-advance edge | ✅ done 2026-08-18 — verified after penalty window lifted | 0.5d |
| 2.5 | Track row context menu | ✅ done 2026-08-17. Play next / add to queue and copy song link | 0.25d |
| 2.6 | Seek reliability | ✅ done 2026-08-21 — drag-seek while paused and position interpolation after seek behave correctly in normal use | 0.25d |

Exit criteria: media keys + lock screen controls work; shuffle/repeat round-trip
with the phone's Spotify app state; queue visible and manipulable; a 3-hour
listening session with zero silent failures.

## M3 — Search (0.5–1d)

| # | Item | Notes |
|---|------|-------|
| 3.1 | Search page | `/v1/search` (tracks first; type switch tracks/artists/albums/playlists later); debounced-as-you-type (≥300ms) or submit-on-return; reuse TrackListView | |
| 3.2 | Search results context | Play results as ad-hoc context (`nanyin_play_tracks` window — results are small) | |
| 3.3 | Search entry point | ⌘F/⌘K focus; sidebar "Search" page (currently disabled) | |

Progress 2026-08-18 (final): playback verify done post-penalty — search
results double-click play works end-to-end; M3 closed.

Progress 2026-08-18 (later): artist search added — one /v1/search request
with `type=track,artist`, Artists card row (circular portraits, ≤10) above
Songs, click → artist page (part of 4.1 pulled forward): circular portrait
header + `/v1/artists/{id}/top-tracks` list, plays as a windowed ad-hoc
context. Verified live (OCR on real UI): search row + artist page render;
harness verified decode (50 artists, 10 top tracks). While testing, found a
pre-existing open() epoch bug (capture-before-increment → every page-load
result discarded; playlist pages stuck on "Loading tracks…" since the
hardening pass) — fixed by incrementing loadEpoch before capture.

Progress 2026-08-18 (later): artist discography + album pages — artist page
gains Albums/Singles/compilations rows (LazyHStack horizontal strips, from
`/v1/artists/{id}/albums?include_groups=album,single,compilation`, paginated),
header count "N top tracks · N albums · N singles"; album cards click into an
album page reusing PlaylistDetailView (new `label` param → "ALBUM" eyebrow),
tracks from `/v1/albums/{id}` + paginated `/tracks` (simplified tracks get the
album name/artwork filled in via `Track.withAlbum`), playback via
`spotify:album:<id>` server context (same as playlist path). Verified live:
harness (36 releases: 16 albums + 20 singles; RAM Drumless 13 tracks) + OCR on
real UI (artist page rows, album page header + track list). Remaining M4.1:
clickable artist/album names in track rows, plus the artist link in the player
bar. The compact player bar intentionally omits the album name.

Note: ncspot client id keeps /v1/search working (production-approved app).

## M4 — Polish & completeness

| # | Item | Notes |
|---|------|-------|
| 4.1 | Album / artist pages | ✅ done 2026-08-18. Clickable artist/album names in track rows (per-artist buttons, multi-artist tracks each clickable). The compact player bar intentionally shows only the title and artist, with the artist linking to the artist page; it does not display the album name. Id-less external starts fall back to `/v1/tracks` metadata fetch for artist navigation. Also fixed pre-existing `withAlbum` bug: album name was overwriting the track title on album pages | 1d |
| 4.2 | Likes round-trip | ✅ done 2026-08-19. Heart toggle in track rows (hover-ghost, liked-solid green; context-menu entry) + player bar; `likedContains` seeds per-context (50-id cap), `toggleLike` optimistic with revert-on-failure (incl. one needsAuth retry); liked page cache + sidebar count maintained. Verified live both directions (unlike from liked page → server `[false]`, save from search → `[true]`). Note: server `contains` lags its own PUT/DELETE — never read-back-validate a just-toggled id. | 0.5d |
| 4.3 | Saved Albums / album library | ✅ done 2026-08-20. First-class album library: aggregate page, album save/remove, album-first playback, sorting/filtering, and cross-client reconciliation. Saved albums and Liked Songs remain separate concepts | 2–2.75d |
| 4.4 | Personalized Home | ✅ done 2026-08-20. Recently Played, Top Tracks, Top Artists, and Your Library from public Web API endpoints; independent section loading and cache/failure handling | 1d |
| 4.5 | Playlist create/add | ✅ done 2026-08-21 (offline). `+` beside the sidebar `PLAYLISTS` title opens New Playlist; track context menus add to owned playlists. Uses `/v1/me/playlists` + `/v1/playlists/{id}/items`. Live verification pending explicit approval | 0.5d |
| 4.6 | Playlist search/filter | **Next.** Client-side filter row in detail view | 0.25d |
| 4.7 | Keyboard navigation | ↑↓ already free via List; Enter = play; Space = play/pause (global) | 0.25d |
| 4.8 | Window: mini-player | Collapsed player-bar-only mode (classic Winamp-ish) | 0.5d |
| 4.9 | Followed Artists / artist library | **Planned.** Library page for followed artists plus Follow/Following controls on artist detail pages; cursor pagination, filtering, optimistic writes, and cross-client reconciliation | 1.5–2d |

### M4.3 — Album Library product plan

Progress 2026-08-20 (implementation): all four slices landed offline.
Data foundation: `LikeMutation` generalized to `MembershipMutation` (same
latest-intent-wins reducer now backs both track likes and album saves);
`SavedAlbumCache` extracted as a pure snapshot/override reconciler (unconfirmed
saves pin to the top, removals need a *complete* snapshot to confirm, expired
overrides force a full re-page) with deterministic tests in
`Tests/StateReducerTests.swift`. SpotifyClient gained `GET /v1/me/albums`
paging (added_at retained) plus the unified library surface
(`PUT/DELETE /v1/me/library`, `GET /v1/me/library/contains` chunked at 40
uris) — no deprecated album-specific endpoints. AppModel mirrors the likes
machinery: one writer per album, `withAPIAuthRetry`, epoch fencing on every
load/probe/mutation, sign-out wins. UI: Saved Albums sidebar entry + count,
SavedAlbumsView (virtualized List rows, filter field, Recently Added/Album/
Artist sort, cover hover-play via `playAlbum` → `spotify:album:<id>` context,
context menus with remove/copy-link), always-mounted album header with
SAVE ALBUM/SAVED (plus/check, never a heart) + Retry on failed track loads,
and save/remove/play/copy on artist-page album cards. PlaylistDetailView
now keeps its header mounted across loading/empty/error states. Live
verification (>50-album pagination, rapid toggles, cross-client
reconciliation) still pending explicit approval.

Progress 2026-08-20 (later): Saved Albums page switched to a cover grid per
user preference — `LazyVGrid` (adaptive ~170pt cards) in the page's single
vertical `ScrollView`; card = square cover + hover play circle (green,
Spotify-grid style) + hover minus badge for removal; click opens the album
page. Live-verified the row/list layout earlier the same day (106-album
library, correct count); grid layout verified live right after.

Live verification 2026-08-20 (write path, via UI automation + OCR):
106-album library paginates (server total drives sidebar count); remove from
the album header flipped the control to + SAVE ALBUM, dropped the count to
105, removed the card from the grid, and a forced refresh confirmed the
server agreed (105 albums); re-saving flipped it back to ✓ SAVED, count 106,
and after refresh the album returned at the TOP of Recently Added (newest
first). Override lifecycle cleared exactly on server confirmation. Zero 429s
/ dealer errors the whole session (one benign hm://collection dealer parse
warning). Rapid-toggle ordering and failed-write rollback remain covered by
the deterministic reducer suite (forcing a live server failure isn't worth
the risk-control exposure); cross-client convergence relies on the same
forced-refresh path verified above.

Goal: make album-first listening a complete library flow. A user can save an
album from its detail page, find it immediately in Saved Albums, and start the
whole album with one action. Saving an album must not imply that every track is
in Liked Songs, and liking one or more tracks must not save the album.

Primary UI:

```text
YOUR LIBRARY              SAVED ALBUMS                          68 albums
♥  Liked Songs      423   [Filter albums…]  [Recently Added ▾]
▣  Saved Albums      68
                           [cover]     [cover]     [cover]     [cover]
PLAYLISTS                  RAM         Kind of      Blue        ...
Discover Weekly            Daft Punk   Miles ...   Coltrane
Daily Mix 1
```

Album detail header:

```text
[ Album Cover ]   ALBUM
                  Random Access Memories
                  Daft Punk · 2013 · 13 tracks

                  [ PLAY ]  [ ✓ SAVED ]
```

MVP product scope:

- Add a fixed `Saved Albums` sidebar entry with the current library count.
- Build a cover grid (`LazyVGrid` in the page's single vertical ScrollView —
  grid layout per user preference, 2026-08-20) with prominent cover art,
  album, primary artist, and year. Default to `Recently Added`; also support
  `Album` and `Artist` sort orders plus a client-side album/artist filter.
- Single-click a card to open the existing album detail page. A hover play
  circle on the cover and `Play Album` context-menu action start the
  server-resolved `spotify:album:<id>` context at index 0 without uploading
  track URIs.
- Add `SAVE ALBUM` / `SAVED` to the album header. Use plus/check semantics, not
  a heart, so album saves cannot be confused with Liked Songs. Keep the header
  visible and interactive while tracks are loading, empty, or failed.
- Add Save/Remove, Play Album, and Copy Album Link actions to album-card and
  Saved Albums card context menus. Removal is immediate and does not require a
  confirmation dialog; a failed write restores the previous state.
- Show explicit loading, empty, and retryable error states. An empty state links
  to Search even though dedicated album search results are a follow-up.

API and state model:

- Existing `user-library-read` and `user-library-modify` scopes are sufficient;
  do not add another OAuth journey.
- Page `GET /v1/me/albums?limit=50&offset=…`, retain `added_at`, and render the
  first page before fetching the tail. The server `total` drives the sidebar
  count; the complete snapshot enables deterministic client-side sorting.
- Use the current unified library API for writes and probes:
  `PUT /v1/me/library?uris=spotify:album:<id>`,
  `DELETE /v1/me/library?uris=spotify:album:<id>`, and
  `GET /v1/me/library/contains?uris=…` in batches of at most 40 URIs. Do not add
  new calls to the deprecated album-specific save/remove/contains endpoints.
- Keep `savedAlbumIDs`, known-state IDs, the paged album cache, server total,
  and per-album optimistic overrides separate. Reuse the latest-intent-wins
  mutation reducer pattern proven by track likes; a stale snapshot or obsolete
  request completion must never overwrite a newer local intent.
- Saving from detail inserts the album at the top of `Recently Added` locally;
  removing it from Saved Albums removes the row and adjusts the count locally.
  On failure, roll back both membership and list position/count.
- Refresh on Saved Albums entry and app foreground with bounded requests so
  changes made by another Spotify client converge. Fence every load, probe, and
  mutation by account epoch; sign-out wins over late completions.
- Preserve the existing 401 discipline: refresh the Web API token only after a
  typed `needsAuth`, honor `Retry-After` on 429, and never involve the playback
  token in library calls.

Delivery slices:

1. **Data foundation (0.5–0.75d):** saved-album DTO/model, paged list API,
   unified library probe/mutation calls, cache/reducer state, and deterministic
   concurrency tests.
2. **Save round-trip (0.5d):** stable album header, Save/Saved control, artist
   album-card menu, optimistic update, auth retry, and rollback.
3. **Saved Albums page (0.75–1d):** navigation, count, cover grid,
   filtering/sorting, whole-album playback, context menus, and page states.
4. **Verification (0.5d):** >50-album pagination, rapid toggles, stale refresh,
   failed writes, account changes, and cross-client convergence. Normal agent
   checks remain offline; live Spotify verification requires explicit approval.

Acceptance criteria:

- Saving any reachable album updates its detail control, Saved Albums list, and
  sidebar count immediately, then remains correct after refresh/relaunch.
- Removing from either detail or the aggregate page updates every visible
  surface; a failed request restores the exact prior result.
- Rapid save/remove/save sequences settle on the latest user intent. Older
  snapshots, probes, and completions cannot reverse it.
- A library larger than 50 albums fully paginates without duplicate or missing
  rows and remains responsive while filtering, sorting, and scrolling.
- Album-row playback starts the whole album through its Spotify context; it
  does not construct or upload a large track list.
- Loading/error/empty states preserve navigation and never hide the album
  header's save control.

Follow-ups, not part of M4.3 MVP: album results in Search, a Home-page Recently
Saved Albums shelf, an optional compact list view alongside the grid, and bulk
library actions.

### M4.4 — Personalized Home ✅ (2026-08-20)

Home replaced the M0 URI-paste screen with a personalized page built only from
public Web API endpoints: Recently Played (`GET /v1/me/player/recently-played`),
Top Tracks (`GET /v1/me/top/tracks?time_range=short_term`), Top Artists
(`GET /v1/me/top/artists?time_range=medium_term`), plus a Your Library shelf
derived from existing liked/saved-album/playlist state. No recommendation
feeds, no private endpoints, no new scopes (user-read-recently-played and
user-top-read were already granted).

- `SpotifyClient`: `recentlyPlayed/topTracks/topArtists` with static decode
  entry points + limit clamping (1…50) — decode logic is pure and covered by
  `Tests/StateReducerTests.swift`.
- `HomeFeed` (new, pure): play-history → context cards. Playlist contexts
  resolve names/covers against `/v1/me/playlists`; editorial mixes (Daily Mix
  etc., absent from that list) and unknown contexts fall back to the track's
  album so a card never renders nameless. Cards dedupe by context and cap at
  10.
- `AppModel.loadHome(force:)`: three sections load independently and publish
  independently — one failing never clears the others. Memory cache per
  section for the login session; failed sections auto-retry on next entry;
  manual refresh re-requests everything; per-section request generations +
  account-epoch fencing keep stale results from publishing after a refresh or
  sign-out. All traffic goes through `withAPIAuthRetry` (Web token only).
- Home UI: greeting + refresh button, horizontal Recently Played cards
  (album/playlist/artist hover-play via `playServerContext` — never track-URI uploads), ≤10 top
  tracks as plain rows (ad-hoc windowed context, same as search), circular
  Top Artists tiles, Your Library grid (Liked Songs + saved albums +
  playlists) with loading / empty / partial-error / full-error states.
  Single vertical scroll region; hover state stays card-local.
- The M0 paste-a-track-URI box lives on in Search: pasting a track link/URL
  swaps the page to a direct play card (`app.playURI`) instead of a text
  search.

Live verification (real listening history rendering, card navigation,
playback from cards) still pending explicit approval.

### M4.5 — New Playlist and Add to Playlist ✅ (2026-08-21, offline)

All four slices landed offline; `script/agent_check.sh` green (deterministic
reducer/decode tests + full app build). Live create/add/server-refresh
verification still requires explicit approval.

- **Data foundation:** `PlaylistInfo` gained `ownerId` (retained at load —
  owned-playlist filtering needs no extra request; `trackCount` became a
  `var` so confirmed adds can bump it). `SpotifyClient` gained a generic
  `mutate` transport accepting the endpoints' 2xx successes with bounded
  Retry-After on 429 and typed 401, plus `createPlaylist` (POST
  `/v1/me/playlists`, `public: false`, returns the decoded created
  playlist via static `decodeCreatedPlaylist`) and `addTrackToPlaylist`
  (POST `/v1/playlists/{id}/items`, never the legacy `/tracks` route).
  **Trap (live 2026-08-21):** the create body MUST carry an explicit
  `"description": ""` — omitting the key makes Spotify store the literal
  string `null` as the description, visible in the official client.
  NullSpot sends `description ?? ""` for the same reason; covered by
  `testCreateBodyCarriesExplicitEmptyDescription`.
- **Staleness reconciliation:** new pure `PlaylistLibraryMerge` reducer.
  Confirmed local mutations carry a monotonic serial, but snapshots confirm
  them by content because Spotify reads may briefly lag successful writes.
  Creates retire when their id appears; adds retire when the count reaches
  the confirmed local count. Missing writes survive two stale snapshots,
  then server truth wins so remote deletes/count decreases are not masked.
  Existing snapshot rows are never replaced by older create responses.
- **New Playlist UI:** one stable `PLAYLISTS` title row with an always-visible
  `+` (accessibility label + tooltip `New Playlist`, keyboard-focusable) —
  present while loading and empty; the list itself gained explicit
  loading / empty / failed states. The sheet (name only, focused on open,
  trimmed, Return submits, Esc cancels) disables both Create and dismissal
  while in flight, shows a retryable inline error that keeps the entered
  name, and on success inserts the playlist into the sidebar immediately,
  dismisses, and opens its empty detail page. All create/add results are
  fenced by account epoch — sign-out wins over late completions.
- **Add to Playlist:** `Add to Playlist` submenu in track-row context menus
  (List rows, Home top-tracks rows, artist top-tracks rows — all share
  `TrackRow`) listing only playlists the current user owns; one add per
  click (per-target in-flight set guards duplicates), sidebar count and
  open-target detail page update only after the server confirms, appending
  every confirmed occurrence because Spotify playlists permit duplicate
  tracks. Track rows use occurrence identity so duplicates render and play
  at the correct index. `Add to Queue` stays a separate item.

### M4.5 — New Playlist and Add to Playlist plan

Goal: make playlist creation discoverable from the library sidebar, then let a
track be added to an owned playlist without leaving its current page.

Primary UI:

```text
PLAYLISTS                                  [+]
Discover Weekly                             30
Daily Mix 1                                 50

┌──────────────────── New Playlist ────────────────────┐
│ Name                                                  │
│ [My playlist_______________________________________]  │
│                                                       │
│                              [Cancel]  [Create]        │
└───────────────────────────────────────────────────────┘
```

- Replace the conditional `PLAYLISTS`/`Loading playlists…` label with one
  stable title row. Put a plain `+` button at the title's right edge with the
  accessibility label and tooltip `New Playlist`; keep it visible when the
  library is loading or empty.
- Clicking `+` opens a focused New Playlist sheet. Name is the only MVP field;
  trim surrounding whitespace, disable Create for an empty name, submit with
  Return, and create a private playlist by default. Cancel makes no request.
- While Create is in flight, disable both duplicate submission and dismissal.
  Show a retryable inline error in the sheet. On success, insert the returned
  playlist into the sidebar immediately, dismiss the sheet, and navigate to
  its empty detail page.
- Give the playlist list explicit loading and empty states instead of treating
  an empty response as perpetual loading. The `+` action remains available in
  both states.
- Add an `Add to Playlist` submenu to track-row context menus after creation is
  complete. List only playlists the current user owns in the MVP; selecting
  one adds that track once per click, updates its sidebar count after success,
  and refreshes an already-open target playlist. Keep `Add to Queue` separate.

API and state model:

- Retain playlist ownership in `PlaylistInfo` so write targets can be filtered
  without another request. A newly created playlist is editable immediately.
- Add a Web API mutation helper that accepts the endpoint's normal 200/201/204
  success statuses while preserving the existing bounded 429 handling and
  typed 401 behavior.
- Create with `POST /v1/me/playlists` and JSON
  `{ "name": name, "public": false }`. Decode and return the created playlist
  rather than synthesizing an id or waiting for a full library refresh.
- Add tracks with `POST /v1/playlists/{playlistId}/items` and JSON
  `{ "uris": [track.uri] }`. Do not use the legacy `/tracks` route.
- Route both writes through `withAPIAuthRetry` using only the Web API token.
  Fence results by account epoch so a late completion cannot repopulate state
  after sign-out or an account change.
- Keep one playlist refresh path as the server reconciliation source. A stale
  refresh started before a successful create/add must not overwrite the newer
  local result; use a request generation or merge the confirmed mutation into
  the arriving snapshot.

Delivery slices:

1. **Create API/state:** ownership metadata, mutation transport,
   `createPlaylist`, account-epoch/request-generation guards, and list refresh.
2. **New Playlist UI:** stable title row with right-aligned `+`, creation sheet,
   keyboard behavior, loading/empty/error states, and success navigation.
3. **Add to Playlist:** owned-playlist submenu, add-item write, count/detail
   reconciliation, and bounded per-target in-flight state to prevent accidental
   duplicate clicks.
4. **Verification:** offline decode/state tests and `script/agent_check.sh`;
   live create/add/server-refresh verification only after explicit approval.

Acceptance criteria:

- `+` is always visible to the right of `PLAYLISTS` and is keyboard- and
  VoiceOver-accessible.
- A valid name creates exactly one private playlist, shows it immediately, and
  opens its empty detail page; cancellation and invalid names make no request.
- API failure leaves the entered name intact and permits retry without adding
  a phantom sidebar entry.
- `Add to Playlist` exposes only writable MVP targets; success survives a full
  refresh and updates an open target without duplicating existing loaded rows.
- Sign-out or account replacement wins over every late create/add/refresh
  completion.

### M4.9 — Followed Artists / Artist Library plan

Goal: make followed artists a first-class Library surface. A user can browse
every artist they follow, filter the collection, open or play an artist, and
follow/unfollow from the existing artist detail page. "Followed Artists" is
distinct from Home's listening-affinity-based Top Artists.

Primary UI:

```text
YOUR LIBRARY              ARTISTS                         84 artists
♥  Songs            423  [Filter artists…]
▣  Albums             68
●  Artists            84  ( portrait )  ( portrait )  ( portrait )
                         Artist name   Artist name   Artist name

ARTIST DETAIL
( portrait )  Artist name
              10 top tracks · 14 albums · 8 singles
              [▶ PLAY]  [✓ FOLLOWING]
```

MVP product scope:

- Add a fixed `Artists` sidebar entry with the current followed-artist count.
- Build an adaptive circular-portrait `LazyVGrid` in one vertical
  `ScrollView`. Publish the complete collection once in localized artist-name
  order so cards do not jump while cursor pages arrive. If tail pagination
  fails, retain page one as an explicitly labeled partial fallback.
- Add a client-side name filter. Empty-library state links to Search; a
  no-filter-results state clears the query without making a request. Filtering
  stays disabled for a partial fallback because it cannot search the full
  collection.
- Single-click opens the existing artist detail page. A cover hover action and
  `Play Artist` context-menu action start the server-resolved
  `spotify:artist:<id>` context; never construct a track-URI list.
- Add `Follow` / `Following` to both dark and classic artist headers. The
  artist-card context menu offers Play, Follow/Unfollow, and Copy Artist Link.
  Unfollow is immediate and requires no confirmation.
- Preserve the existing artist page header while profile, tracks, albums, or
  membership state is loading or retrying. A membership failure is retryable
  without replacing the rest of the artist page.

API and state model:

- Page `GET /v1/me/following?type=artist&limit=50&after=…`; retain the cursor
  and server `total`, retain page one for failure recovery while fetching the
  tail, deduplicate by artist id, and publish a complete snapshot only after
  `next` is nil and the unique item count agrees with `total`. Spotify does not
  document a semantic ordering for this endpoint, so the UI defaults to
  localized artist-name order while retaining `Spotify Cursor` as an explicit
  alternative. This endpoint requires the existing `user-follow-read` scope.
- Spotify removed `PUT/DELETE /v1/me/following` in February 2026. Follow and
  unfollow only through the current unified library interface:
  `PUT /v1/me/library?uris=spotify:artist:<id>` and
  `DELETE /v1/me/library?uris=spotify:artist:<id>`. Probe detail-page state via
  `GET /v1/me/library/contains?uris=…` in batches of at most 40 URIs. Existing
  `user-library-read` and `user-library-modify` scopes are sufficient; do not
  add another OAuth journey.
- Reuse `SpotifyClient.Artist` and the shared `MembershipMutation` reducer.
  Keep artist collection snapshots and optimistic overrides behind one
  artist-library state seam in `AppModel`; do not make views coordinate API
  requests or mutation ordering.
- Follow/unfollow is optimistic with one serialized writer per artist. Rapid
  follow/unfollow/follow sequences settle on the latest intent; a failed
  latest write rolls back to the last confirmed state.
- Partial cursor snapshots may confirm presence but never confirm absence.
  Only a complete snapshot may retire an optimistic unfollow. Successful
  writes mask Spotify read-after-write lag for a bounded window; expired
  overrides force complete re-pagination.
- Fence every load, probe, mutation, and completion by account epoch. Route
  calls through `withAPIAuthRetry`, honor `Retry-After`, and ensure sign-out
  clears artist data and wins over in-flight work.
- Refresh on page open/reselection and explicit retry. Reuse the current
  library refresh throttling pattern so navigation does not create request
  storms; cross-client changes converge on a full refresh.

Delivery slices:

1. **Data foundation (0.5d):** cursor-page DTO/decode, followed-artist client
   calls, pure snapshot/override reconciliation, account-epoch cleanup, and
   deterministic reducer tests.
2. **Artist Library page (0.5d):** route/sidebar count, paged portrait grid,
   filtering, artist navigation/playback, context menus, and page states.
3. **Follow round-trip (0.25–0.5d):** detail-header control, contains probe,
   serialized optimistic writes, rollback, and stale-read masking.
4. **Verification (0.25–0.5d):** offline decode/state/UI build checks and
   `script/agent_check.sh`; live follow/unfollow/server-refresh verification
   only after explicit approval.

Acceptance criteria:

- A library larger than 50 followed artists cursor-paginates without missing
  or duplicate cards. Successful loads publish once in stable artist-name
  order; a failed tail retains page one with `Showing <loaded> of <total>` and
  a retry action.
- Sidebar count, Artists page, artist detail header, and card context menus
  show one consistent membership state after local writes and refreshes.
- Rapid repeated toggles, stale/partial snapshots, failed writes, override
  expiry, and account replacement cannot overwrite the latest user intent.
- Artist playback uses `spotify:artist:<id>` as a server-resolved context and
  never uploads a large list of tracks.
- Loading, empty, no-filter-results, partial-error, and retry states remain
  navigable and accessible in both shell presentations.
- Offline verification covers cursor decoding, >50-item pagination,
  deduplication, optimistic rollback, stale snapshot reconciliation, and
  sign-out/account-epoch fencing. Live Spotify writes remain opt-in.

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
