# IDEAS

Living brainstorm for Nanyin. Not a commitment, not a schedule, not a
substitute for `ROADMAP.md` or `PRODUCT.md`.

Last updated: 2026-08-28.

## How to read this

Each idea is a seed, not a spec. Effort is relative to the current
codebase (`S` hours, `M` a day-ish, `L` a real project). Horizon:

- **Near** — closes a hole in the daily driver without new product
  identity. Prefer these before inventing surfaces.
- **Mid** — coherent bets that deepen “classic desktop player” without
  fighting Spirc, the token split, or the 60 Hz list rules.
- **Horizon** — after listening is boringly reliable. Many need a
  product decision, a new OAuth scope, or a ToS/risk conversation.

Risk tags: `api` (Web API / quota), `tos` (unofficial client),
`hazard` (AGENTS.md Spotify risk-control), `a11y`, `perf`, `ip`
(historical assets / brand).

Do not treat Horizon items as “the fun stuff we skipped.” Several of
them would make Nanyin a different app.

## North star (so ideas can be rejected)

Nanyin is a **Connect device that happens to be a native Mac library
browser**, not a Web-API remote that happens to look old. Listening
comes first. Themes recreate era *design logic*, not branded pixels.
Public Web API only; large contexts stay server-resolved
(`nanyin_play_context`). Keep Spirc.

If an idea needs Connect-as-remote, private recommendation feeds,
uploading 1000+ track URIs, a new OAuth journey, auto-opening a
browser from an error path, or a theme plugin platform, it probably
belongs in [Anti-ideas](#anti-ideas).

What is already a daily driver (do not re-propose as new work):
login, playback core, Liked Songs, playlists (create + add), saved
albums, followed artists, search (tracks + artists), album/artist
pages, Home from public endpoints, queue (read + add), shuffle/repeat,
media keys / Now Playing, Classic 2010 + Nanyin Dark, Sparkle,
notarized arm64 DMG, Homebrew cask.

Roadmap leftovers that already have a name: **M4.6** playlist
filter, **M4.7** keyboard (Enter still missing), **M4.8** mini-player.

---

## Near — close the remaining listening holes

These are the highest-leverage ideas because the seams already exist.

### N1. Playlist / Liked Songs filter (M4.6)

**Why.** Classic desktop players let you type in a 400-track playlist
and jump. `SavedAlbumsView` / `FollowedArtistsView` already have a
client-side filter; `PlaylistDetailView` does not. No API.

**Effort.** S. **Risk.** `perf` if the filter lives in the list parent
instead of a derived array.

```
  LIKED SONGS                         1129 songs
  [ Filter tracks…              ]  12 matches
  #  Track              Artist        Album           Time
  1  Teardrop           Massive A…    Mezzanine       5:31
```

Keep the header mounted (same rule as the album save control). Empty
filter-results clears the query locally. Do not re-fetch.

### N2. Enter plays the selected row (M4.7)

**Why.** `List` already gives ↑↓ selection in Classic; Space is global
play/pause; double-click plays. Keyboard users still cannot commit a
row. ROADMAP calls this remaining. Also add
`.accessibilityAction(.default)` so VoiceOver does not depend on
“Double-click to play”.

**Effort.** S. **Risk.** `a11y` if Space in a focused search field
pauses playback (iTunes/Spotify both special-case this — decide
explicitly).

### N3. Mini-player window (M4.8)

**Why.** The compact player bar already wants to be a window. Classic
desktop software lived as a small always-available deck; the current
900×600 minimum fights that.

**Effort.** M. **Risk.** `perf` if a second window observes
`AppModel` too broadly; `a11y` if it is a fake overlay instead of a
real `Window` scene.

```
  ┌──────────────────────────────────────────┐
  │ ● ● ●   nanyin                           │
  │ [art] Teardrop                           │
  │       Massive Attack                     │
  │  ⏮  ❚❚  ⏭    1:42 ━━━●━━━━ 5:31   🔊  │
  └──────────────────────────────────────────┘
```

Use a second scene, not another layout inside `PlayerBar`. Collapse
the main window rather than duplicating transport state. Always-on-top
is a preference, not the default. The existing local 400 ms position
tick stays in one owner.

### N4. Search albums and playlists

**Why.** `SavedAlbumsView` empty state says “Search for albums” and
then `SearchView` only requests `type=track,artist`. M3.1 and the
M4.3 follow-up already named this. Same `SpotifyClient.search`, expand
the `type` query.

**Effort.** S–M. **Risk.** `api` (bigger payload); `perf` if result
sections become nested same-axis scrollers.

Play albums/playlists via `spotify:album:` / `spotify:playlist:` —
never turn result tracks into a large Connect upload. Cap each
section. Paste handling should accept album/artist/playlist URLs the
same way track URLs already work.

### N5. Artist header Play uses `playArtist`

**Why.** Followed-artist cards start `spotify:artist:<id>` (server
radio). The artist page PLAY button window-plays ~10 top tracks via
`play(track:contextKey:)`. Same verb, two products. Users will think
Play is broken when the context dies after ten songs.

**Effort.** S. **Risk.** none if it reuses `AppModel.playArtist`.

Optional: keep “Play Top Tracks” as a quieter menu item.

### N6. Play Next as a real verb

**Why.** M2.5 text promised Play Next / Add to Queue. `TrackContextMenu`
only has Add to Queue, and the FFI comment is append. Classic players
treat “play next” as the power-user move.

**Effort.** S if spirc can insert; M if it cannot and the UI must stop
lying. **Risk.** `api` / `hazard` if this becomes a hand-rolled dealer
frame. Do not invent a queue protocol. If insert-at-front is not
actually available, rename the menu and drop the promise.

### N7. Queue rows are tracks

**Why.** Queue is a second-class list: no like, no artist/album jump,
no Add to Playlist. The data is already `Track`. Reuse `TrackRow` /
`TrackContextMenu` instead of a parallel menu.

**Effort.** S. **Risk.** `perf` if Queue stops using one recycling
`List`.

Do not promise remove / reorder / “play this upcoming row in the
current context”. `GET /v1/me/player/queue` is capped ~20; dealer
`SUBSCRIBE` is a verified dead end.

### N8. Playlist sidebar life cycle

**Why.** Users can create playlists and add tracks, then cannot rename,
unfollow, or delete from Nanyin. `snapshotId` is already decoded and
unused. Scopes already include `playlist-modify-private` and
`playlist-modify-public`.

**Effort.** M. **Risk.** `api` (write lag — reuse `PlaylistLibraryMerge`
latest-intent-wins, do not invent a second reducer).

Ship as a source-list context menu, not a settings page:

```
  PLAYLISTS                         +
  Late Night                   128    [ Rename… ]
  Discover Weekly               30    [ Delete playlist ]
                                      [ Copy Playlist Link ]
```

Unfollow vs delete must be distinct for playlists the user does not
own. No confirmation-on-unfollow; delete of an owned playlist does
need one, because it is remote and irreversible.

### N9. Remove a track from an owned playlist

**Why.** Add without remove is a one-way street. `DELETE /v1/playlists/{id}/items`
needs `snapshot_id` (already on the DTO). Occurrence identity in
`TrackListView` is the hard part and it already exists.

**Effort.** M. **Risk.** `api` (duplicates: must delete the right
occurrence, not every copy).

### N10. Home: Recently Saved Albums shelf

**Why.** Named M4.3 follow-up. Purely derived from `SavedAlbumCache`.
No request. Completes “I saved it, where did it go?” without teaching
the sidebar.

**Effort.** S. **Risk.** `perf` if it duplicates the Saved Albums
grid instead of a bounded horizontal shelf (the Home pattern).

### N11. Home Top time range

**Why.** `TopTimeRange` already exists; Home hard-codes tracks
`short_term` and artists `medium_term`. A segmented control is the
classic “this library remembers my taste at three scales” move, and
it is already paid for.

**Effort.** S. **Risk.** `api` (three extra calls on toggle — cache
per range, do not refetch on every Home appear).

### N12. Paste any Spotify URL in Search

**Why.** Track paste is a hidden power feature from M0. Album / artist
/ playlist / user-collection links currently search as text and miss.
This is the fastest “phone shared a link, Mac should just go there”
path, and it needs no new scope.

**Effort.** S. **Risk.** none if it routes to existing `open` /
`playServerContext` helpers.

### N13. Single window, standard window menu

**Why.** `WindowGroup` offers File → New Window against one
shared `AppModel`. That does not create a second process, device identity,
or dealer connection, but it exposes duplicate library windows for a product
designed around one app-wide navigation and playback state. PRODUCT wants
predictable Mac behavior, which here means **one library window**.

**Effort.** S. **Risk.** duplicate navigation surfaces if left as-is.

Also: `applicationShouldTerminateAfterLastWindowClosed`, Dock reopen,
`defaultSize` / restoration id. Window title can follow the current
track (`Teardrop — nanyin`) without becoming a now-playing bar.

### N14. Account and Playback menus that match the chrome

**Why.** Sign Out lives only in the sidebar. Shuffle / repeat / like
are not in the Playback menu. Dark `PlayerBar` buttons are mostly
unlabelled for VoiceOver. A Mac music app of this vintage is operated
from the menu bar as much as from the deck.

**Effort.** S. **Risk.** `a11y`.

Add: Sign Out, Check Liked Songs (already a become-active probe),
Shuffle, Repeat, Repeat One, Love, Volume Up/Down, Mute, Go to Current
Track (`⌘L` iTunes muscle memory).

### N15. Volume and window geometry persist

**Why.** Volume is `AppModel` state at 1.0 every launch. Sidebar width
and Classic now-playing collapse already hint at local preferences.
A desktop player that forgets volume feels unfinished.

**Effort.** S. **Risk.** none. Store volume in `UserDefaults`, not
Keychain; do not write it through Spirc on launch (avoid a connect
state PUT storm — set the renderer, then one bounded spirc volume
once the session is ready).

### N16. Connection note → user-driven Retry

**Why.** Generic init failure currently says retry on relaunch.
Sidebar already has `connectionNote`. A Retry button that reuses the
**current** playback token and the Keychain device id is the missing
affordance. Never open a browser from it.

**Effort.** S. **Risk.** `hazard` if Retry refreshes on TLS/timeout.

### N17. Dark transport accessibility and Space-vs-search

**Why.** Classic chrome has roles/labels; Dark play/pause/next mostly
do not. PRODUCT’s inclusion rule is not theme-specific.

**Effort.** S. **Risk.** `a11y`.

### N18. Go to Current Track / Reveal in list

**Why.** iTunes `⌘L`. When a 1000-row Liked Songs list is open, the
eq indicator is easy to miss. Scroll the recycling `List` to the
current URI + occurrence.

**Effort.** S. **Risk.** `perf` if this is implemented by observing
position in the list parent.

### N19. Album header metadata that we already fetched

**Why.** `albumTracks` hits `GET /v1/albums/{id}` and then throws away
year / label / copyright. The header subtitle is whatever navigation
passed in. Classic album pages lived on that line.

**Effort.** S. **Risk.** none.

### N20. Compilations and Appears On

**Why.** `artistAlbums` already returns `group`. Compilations are
folded into Albums (`group != "single"`), contradicting the artist
page copy that counts three rows. `appears_on` is one extra
`include_groups` value and a fourth strip.

**Effort.** S. **Risk.** `api` (one more paging loop). Play each
release as `spotify:album:<id>`, never a discography URI dump.

---

## Mid — deepen the desktop player

### M1. Sleep / wake and overnight session preheat

**Why.** Hazard #9 is still a first-click landmine. NullSpot has
`LoggedInLifecycleModifier`; Nanyin has zero `willSleep` / `didWake`.
`handleAppDidBecomeActive` only refreshes library membership.

**Effort.** M. **Risk.** `hazard` if preheat `activate()`s or refreshes
tokens. `nanyin_init_player` currently no-ops while the session exists and
has not reported `is_invalid`, so session age alone cannot force this
rebuild. Safe shape: add a generation-fenced force-rebuild operation; on
wake or on foreground with session age > a few hours **and not playing**,
invoke it once with the current token and same device id. Do not activate
until the user hits play. At most once per foreground. Playing audio stays
untouched (`PlaybackReconnectPolicy` already defers rebuild).

### M2. Stall recovery steps 2 and 3

**Why.** Watchdog + one seek/renderer restart is in. If that fails,
the user gets `audio pipeline stalled` and the Connect context is not
rebuilt. Research already named the next steps.

**Effort.** M. **Risk.** `hazard` if stall recovery refreshes
credentials or uploads the open playlist.

Safe ladder, one budget per `(generation, playRequestID)`:

1. local seek / renderer restart (done)
2. same-track reload at `confirmedPositionMs` via existing Spirc
   context or `nanyin_play_track_at` (single URI)
3. one generation-safe rebuild **reusing the current token**, then
   `playContext(original URI, index)` + seek
4. stop, visible error, Retry (N16)

Remember last server-resolved context (URI + index + position +
shuffle/repeat flags) independently of `PendingPlayIntent`. Pending
play is “unconfirmed command”; this is “what was actually playing.”

### M3. Persist position more than on quit

**Why.** `LocalPlaybackStore` only writes in `shutdown()`. Force-quit
and crashes lose the place. Pause / track change / throttled tick can
write the same snapshot. Still **do not autoplay** on launch.

**Effort.** S. **Risk.** `hazard` if launch starts calling `activate()`.

### M4. Classic right-pane queue inspector

**Why.** Named and deferred in `classic-2010-theme-plan.md` so v1 fits
the 900 pt minimum. Historically the third column is how the 2010
client showed “what happens next” without leaving the album.

**Effort.** M. **Risk.** `perf` (three columns, two lists); window
minimum must grow or the pane must collapse.

```
  ┌────────────┬──────────────────────────┬──────────────┐
  │ Library    │  Mezzanine               │ QUEUE        │
  │ Songs      │  Massive Attack          │ Teardrop  ◂  │
  │ Albums     │  # Track          Time   │ Angel        │
  │ Artists    │  1  Angel         6:18   │ Risingson    │
  │ Late Night │  4  Teardrop  ▮▮▮ 5:31   │              │
  └────────────┴──────────────────────────┴──────────────┘
```

Same queue data as `QueueView`. Hidden in Nanyin Dark. Do not fetch a
second queue.

### M5. Column sort and type-select in track tables

**Why.** Classic tables sorted by clicking Track / Artist / Album /
Time. `List` headers are currently inert labels. Client-side sort of
the already-loaded page is enough; do not re-request. Type-select
(focus list, type “tea”, jump to Teardrop) is the other half of
feeling like Finder.

**Effort.** M. **Risk.** `perf` on 1000+ Liked Songs — sort a derived
array, do not rebuild row identity carelessly (occurrence IDs must
follow the new order, and play-from-row must still send the
**context** index, not the visual index). This is the trap: visual
sort vs Spotify context order. If that cannot be made honest, show a
banner “playing in playlist order” and keep double-click bound to
context index.

Honest alternative: sort is a *view* and Play means “play this
track’s context from this URI” via server context + URI, not
`start_index` into a resorted array.

### M6. Drag a track onto a playlist

**Why.** Context-menu Add to Playlist is complete but hidden.
Drag-and-drop is the desktop verb. Sidebar playlists are the drop
target; owned playlists only.

**Effort.** M. **Risk.** `perf` / AppKit-in-SwiftUI; `a11y` (menu
path must remain). One URI per drop, same `addTrackToPlaylist`
pipeline. No drag-reorder of the queue (no API).

### M7. Multi-select in track tables

**Why.** “Add these five to Late Night.” `List(selection:)` already
exists for Classic single select.

**Effort.** M. **Risk.** `hazard` if multi-play uploads a constructed
list. Multi-add-to-playlist in batches of ≤100 Web API URIs is fine.
Multi-play should play the first selected row’s **context**, not
`nanyin_play_tracks` of the selection.

### M8. Local library search (search my stuff)

**Why.** Global Search is catalog. Power users want “which of *my*
playlists contains Teardrop?” Client-side over already-loaded
playlists / liked / albums / artists, with an optional one-shot
`GET /v1/search` filtered by `user` if the public API still honors
it — verify before depending.

**Effort.** M. **Risk.** `api` if it pages every playlist’s tracks on
first query (do not). Honest v1: names of playlists, albums, artists,
and already-open track caches only. Full collection grep is Horizon
and needs a local index.

### M9. Playlist description, public flag, owner line

**Why.** Create currently forces `public: false` and an empty
description (the `null` string trap is already tested). A detail
header that can edit name + description, and a quieter “Make public”
for owned lists, makes create feel like a real library object.

**Effort.** M. **Risk.** `api`. Custom cover needs `ugc-image-upload`
(new scope, new OAuth journey) — **not** part of this idea.

### M10. Saved Albums compact list

**Why.** Named M4.3 follow-up. Grid is correct for covers; 200-album
libraries also want a dense table (Album / Artist / Year / Added).
Same data, second presentation, persisted per-page like Classic vs
comfortable track rows.

**Effort.** S–M. **Risk.** `perf` if the list is not `List`.

### M11. Daily Mix / editorial cards with real names

**Why.** `HomeFeed` falls unknown contexts back to the track’s album,
so Daily Mix can render as a random album cover. `GET /v1/playlists/{id}`
is unused; `playlist-read-private` is already granted.

**Effort.** S. **Risk.** `api` (N extra playlist lookups — bounded,
cached, never on the playback token).

### M12. Output device picker (system devices, not Connect remotes)

**Why.** `AudioRenderer` already restarts on
`AVAudioEngineConfigurationChange` but always follows the default
output. Classic hi-fi Mac apps let you pick headphones vs interface
without visiting Sound settings.

**Effort.** M. **Risk.** `hazard` if this is confused with Connect
transfer. Label it “This Mac’s speakers”, never “Devices”. No AirPlay
picker unless AVAudioEngine can do it without extra entitlements
(distribution.md: no entitlement exceptions today).

### M13. Dock menu and Now Playing extras

**Why.** Dock right-click → Play/Pause/Next/Previous is free native
texture. Now Playing already has seek; shuffle / like remote commands
are missing.

**Effort.** S. **Risk.** none.

Skip track-change user notifications. They fight listening-first and
become spam during an album.

### M14. Classic title-bar behaves like a title bar

**Why.** `ClassicTitleBarBridge` hides system traffic lights and
draws its own. `mouseDown` only `performDrag`. Double-click to
zoom/minimize (system preference), Option-zoom, and full-screen
semantics are how Mac windows teach themselves.

**Effort.** S–M. **Risk.** `a11y` if custom buttons drift from
`NSWindow` actions.

### M15. Increase Contrast / Reduce Transparency / Reduce Motion

**Why.** PRODUCT lists them. Reduce Motion only covers artwork fade
and `EqIndicator`. Increase Contrast and Reduce Transparency are
unhandled, which matters more in Classic 2010’s low-amplitude
gradients than in Nanyin Dark.

**Effort.** M. **Risk.** `a11y`. Prefer flattening chrome tokens over
adding per-view conditionals.

### M16. Restore navigation on relaunch

**Why.** Last page, last playlist, search query, and sidebar scroll
die with the process. Local-only, account-fenced, like
`LocalPlaybackStore`. Do not restore a page by hitting Web API before
the user has a window.

**Effort.** M. **Risk.** `api` if restore eager-loads five pages.

### M17. Keyboard volume, mute, 5-second skip

**Why.** Playback menu completeness. `,` / `.` or `⌥⌘←` / `⌥⌘→` for
nudge-seek is period-correct and does not need new FFI (existing
`nanyin_seek`).

**Effort.** S. **Risk.** none.

### M18. Unavailable / explicit / region honesty

**Why.** Spirc skips `Unavailable`; the table still looks playable.
A small status glyph in the index column (Classic already has a
narrow leading column) plus a quieter “can’t play in this account’s
market” is more honest than a silent skip.

**Effort.** M. **Risk.** `api` if this probes every row with extra
requests — only render flags already on the track DTO.

### M19. Settings beyond Appearance

**Why.** `ThemeSettingsView` is one radio group. Natural neighbors:
Start paused (already the restore policy — make it visible), Remember
volume, Mini-player on close, Check for Updates interval (Sparkle),
a Diagnostics pane that **copies a redacted log path** and never
dumps tokens.

**Effort.** S–M. **Risk.** `hazard` if diagnostics ever include
refresh tokens or device ids in a shareable blob. Device id stays in
Keychain; logs get a redactor.

### M20. Single-instance lock

**Why.** Hazard #6 is currently a social rule (`pgrep` before launch).
The app can refuse a second process against the same bundle id and
activate the first. This is user-facing reliability, not just agent
hygiene.

**Effort.** S. **Risk.** none.

### M21. App Icon and About window

**Why.** `Design/` already has v2–v13 experiments; Settings has no
About. A native About panel (version, unofficial disclaimer, Sparkle
version, credits to NullSpot / cliamp / librespot) is cheap product
finish for a notarized 0.1.x.

**Effort.** S. **Risk.** `ip` if the icon quotes Spotify glyphs.

### M22. librespot #1741 watch + typed auth upstream

**Why.** The vendored path dependency exists so these two patches do
not silently vanish. An idea, not a feature: a short `docs/` or CI
note that checks upstream merge status so a future “upgrade librespot”
does not re-enter the echo loop.

**Effort.** S. **Risk.** `hazard` if someone “cleans up” Cargo.toml.

---

## Horizon — only after the player is boring

### H1. Third theme: iTunes-era library

**Why.** PRODUCT explicitly allows “multiple Spotify and iTunes
periods.” Classic 2010’s plan says do **not** force the next era into
the same shell adapter. A third `ShellAdapter` with source list +
column browser (Genre / Artist / Album) is the strongest remaining
visual bet.

**Effort.** L. **Risk.** `ip` (do not copy Apple assets), `a11y`,
`perf` (column browser is three coordinated lists).

Ship as `AppThemeID.itunesLibrary` or a Nanyin-named equivalent.
Light chrome may finally justify lifting
`.preferredColorScheme(.dark)` from the scene root.

### H2. Menu-bar extra (Stem, remapped)

**Why.** A Lody chat-session proposed a status-item-only player.
Against *this* codebase that is a companion to M4.8, not a
replacement. Popover reuses mini-player transport; the library window
remains the app.

**Effort.** M. **Risk.** `perf` (status item observing AppModel);
notification-center fights if the extra becomes a second Now Playing.

### H3. Command palette on top of Search

**Why.** ⌘K already focuses Search. A palette that also does “play
Late Night”, “shuffle this album”, “theme Classic 2010”, “go to
queue” is Cue-as-layer, not Cue-as-product.

**Effort.** M. **Risk.** inventing a parallel navigation stack.

Keep one text field. Prefix verbs (`play`, `go`, `like`) if it stays
fast; otherwise this is just Search with extra steps.

### H4. Local files

**Why.** Historically the 2010 client’s big upgrade. PRODUCT users
who miss desktop players often miss *one library of everything*.
This is a different product: file importer, matching, and a ToS
surface area Nanyin currently avoids.

**Effort.** L. **Risk.** `tos`, `ip`, and a second data plane next to
librespot. Do not start because the Classic sidebar has a hole.

### H5. Lyrics / credits pane (Liner, remapped)

**Why.** Out of scope for MVP and still a rights minefield. If it
ever happens: a right-hand inspector, not a destination, fed only
from licensed / user-provided sources. Album copyrights from
`GET /v1/albums/{id}` are a Mid-sized slice of this (see N19) and
should be done first.

**Effort.** L. **Risk.** `tos`, `api`, `ip`.

### H6. Connect as remote / House

**Why.** Explicitly out of scope. Nanyin is the speaker, the phone is
the remote — that is the safe direction given dealer limitations and
hazard #8. Revisit only if the product stops being a playback device.

**Effort.** L. **Risk.** `hazard`, `api` (`user-modify-playback-state`
is granted and unused — that is not permission to build transfer-UI
on the primary account).

### H7. Podcasts / audiobooks

**Why.** Same shell, different object. Would dilute “music client”
and drag in resume semantics Nanyin’s stall watchdog does not have.
Stay Horizon until music is done.

### H8. Offline beyond librespot’s audio cache

**Why.** Out of scope. Building a second cache is how unofficial
clients look like redistribution. Leave the decoder cache alone.

### H9. Last.fm / ListenBrainz scrobble

**Why.** Period-correct extra, independent of Spotify private APIs,
and a good citizen feature for music nerds. Needs its own OAuth and
a privacy toggle.

**Effort.** M. **Risk.** `tos` (extra traffic), credentials in
Keychain next to Spotify’s — isolate by service.

### H10. Smart crates / collection hygiene

**Why.** “Liked but not on any playlist”, “saved album whose tracks
are not liked”, duplicates in a playlist. Purely local set logic over
already-loaded snapshots. This is Crate without pretending Spotify is
a filesystem.

**Effort.** M–L. **Risk.** `api` if it pages the entire catalog to
answer one question. Honest v1 uses complete snapshots already in
memory (liked ids, saved albums, open playlist).

### H11. Gapless, crossfade, normalization, bitrate

**Why.** Audio-nerd finish. Normalization and bitrate are librespot
player config; crossfade is a renderer problem; gapless needs decoder
cooperation. Easy to spend a week on subjective quality.

**Effort.** M–L. **Risk.** `hazard` if experiments change request
shapes; `perf` on the Tokio worker pool (do not starve dealer pongs).

### H12. Intel / universal binary

**Why.** Documented as a real distribution follow-up: x86_64 Rust
staticlib + `ARCHS`. Only if a user appears. Sparkle and the cask are
arm64-shaped on purpose.

**Effort.** M. **Risk.** signing / notarization matrix doubles.

### H13. App Intents / Shortcuts, not widgets-as-app

**Why.** Chip-as-product fights Nanyin’s library window. A few
intents (Play/Pause, Love, Play Playlist X) give Shortcuts and
Spotlight a hook without a widget design language that looks like
iOS.

**Effort.** M. **Risk.** intents that start playback must go through
the same pending-play + server-context path, never a constructed URI
list.

### H14. Collaborative playlist editing

**Why.** Scope `playlist-read-collaborative` is already granted.
Live multi-user editing is a sync product. Read-only collaborative
lists in the sidebar (already listed via `/v1/me/playlists`) plus
add-if-collaborator is the honest slice; real-time is Horizon.

### H15. Sandbox

**Why.** Notarized Developer ID currently needs no entitlement
exceptions. App Store / sandbox would. Only if distribution goals
change. Loopback OAuth on :8989 and Keychain access are the landmines.

### H16. Public Homebrew tap and a one-page site

**Why.** v0.1.1 already ships. A tap and a static page (unofficial
disclaimer, screenshots of both themes, `brew install`) are
distribution, not features. Keep the ToS sentence as prominent as
the download button.

**Effort.** S–M. **Risk.** `tos` (discoverability vs staying small).

---

## Adjacent product shapes (not Nanyin, unless we pivot)

A Lody chat-session, unconstrained by this repo, proposed eight
alternative apps. Mapping them onto Nanyin so they do not get
re-litigated as features:

| Shape | Verdict |
|---|---|
| **Stem** (menu-bar-only) | Companion extra (H2), never the app. |
| **Cue** (Raycast for Spotify) | Layer on Search (H3). ⌘K is already taken. |
| **Crate** (Finder for playlists) | Mid playlist craft (M5–M8, H10). Spotify is not a filesystem. |
| **Sleeve** (one album, ritual) | Conflicts with library-first Home. A full-window now-playing *mode* could exist; do not replace Home. |
| **FocusMix** (Focus-state DJ) | Different product. Calendar/Focus automation is not listening-first. |
| **House** (multi-room brain) | Anti until we stop being a Connect device. |
| **Liner** (lyrics workspace) | H5, rights-first. |
| **Chip** (widgets are the app) | Anti. Library window is the home. |

---

## Engineering ideas (not user-facing, still product leverage)

### E1. Split `AppModel`

It owns auth, library, playback, navigation, home, queue, and
reconnect. The membership reducers are already pure and tested; the
next extraction is a `PlaybackSession` type so UI cannot call FFI
on the main actor by accident (the 2026-08-18 “login spins forever”
class of bug).

### E2. Theme-ID leakage audit

The plan says branch on `theme.id` only at shell / player / search
host / track-layout seams. Leaf views still grow `if classic`. A
periodic grep is cheaper than a registry.

### E3. Chrome preview harness as a visual unit test

`ClassicChromePreviewHarness` and the `build/screenshots` tree are
close to an offline visual gate. Wire a small fixture set into
`script/agent_check.sh` (compile + hash, not live Spotify).

### E4. FFI surface freeze

`nanyin_core.h` is the real API. Ideas that want “just one more
command” should add Swift policy first. New FFI is how control and
data planes get re-entangled.

### E5. ChouTiUI pin health

Narrow adoption, path-vendored, colliding `Shape`/`Color` names.
An idea: treat ChouTiUI like librespot — pin, patch, verify in
`agent_check`, do not float `master`.

### E6. Redacted diagnostics command

`build/nanyin-launch.log` is already the live brain. An in-app
“Open log folder” / “Copy diagnostics” that strips tokens would
make support (even solo support) faster than asking Boss to fish
in `~/Library`.

### E7. Agent-check the anti-hazards

Static checks that would have paid rent: playback-token never
passed to `SpotifyClient`; no `NSWorkspace.open` on error paths;
`nanyin_play_tracks` argument count capped; device id not derived
from pid. Some of this is grep; some is a unit test around
`PlaybackReconnectPolicy`.

---

## Anti-ideas

Things that look like features and would make Nanyin worse.

1. **Cover Flow / Milkdrop / ornamental visualizer as a home.**
   Listening first, density first. Eq dots in the index column are
   the correct amount of motion.
2. **Theme plugin platform / JSON skins / user-editable tokens.**
   The theme seam is two (later three) immutable values. A registry
   is how Classic 2010 becomes a costume chest.
3. **Copying Spotify or iTunes bitmap chrome, marks, or `#1DB954`
   as “historical accuracy.”** Independently drawn generics only.
   Current Spotify green is a brand element, not a 2009 color.
4. **Official Spotify Home / recommendations / related artists.**
   Private or deprecated. Home is recently played + top + library
   on purpose.
5. **Becoming a Connect remote** so Nanyin can “see all devices.”
   We are the device. Transfer *to* Nanyin already works; building
   the other direction on the primary account is how 2026-08-18
   started.
6. **Uploading Liked Songs or a discography as a track URI list**
   to “make shuffle work locally.” Server contexts exist because
   the other way 429’d.
7. **Refreshing the playback token on stall, TLS, or dealer
   timeout.** Typed `BadCredentials` only.
8. **Auto-opening the browser from reconnect / 401 / sparkle
   failure.** Explicit user action only.
9. **Second running instance, PID device ids, protocol experiments
   on the primary account, overnight poke-the-zombie scripts.**
10. **Notification on every track change, iOS widgets as the
    app, candy Aqua, Electron-density cards in Classic 2010.**
11. **Multiple accounts in-process.** Keychain and Connect device
    identity are one-install-one-soul. A throwaway Premium account
    is a human workflow, not a feature.
12. **Removing Spirc** to “simplify recovery.” Already decided.
    Revisit only if the product stops needing server-resolved
    contexts.

---

## Suggested pick order (opinion, not a plan)

If the goal is “daily driver that feels like software”:

1. N2 Enter + N17 Dark a11y + N13 single window
2. N1 filter + N4 album/playlist search + N12 paste any URL
3. N5 artist Play + N7 queue rows + N8/N9 playlist write-back
4. N3 mini-player
5. M1 overnight preheat + M2 stall ladder + N16 Retry
6. M4 right-pane queue *or* H1 third theme — pick one visual bet,
   not both in the same month

If the goal is “Classic 2010 becomes a complete skin”: M4, M14, M15,
N20, then stop adding chrome.

If the goal is “never think about Spotify risk-control again”: M1,
M2, M20, E7, N16. No new pages.

---

## Open questions for Boss

1. Is Nanyin allowed to feel *smaller* (mini-player + menu bar) or
   must the library window remain the identity?
2. When visual sort disagrees with Spotify context order (M5), which
   lie is worse: playing the wrong index, or refusing to sort?
3. Is a third theme actually desired, or is Classic 2010 the entire
   nostalgia budget?
4. Playlist delete / public toggle — do we want write-back at all
   on a ToS-hostile client, or is local-only library browsing the
   ceiling?
5. Secondary Premium account for daily listening: still the
   recommendation, or has the 2026-08-18 window changed how brave
   we are with live features?

---

## What this file is not

It is not permission to implement. Live Spotify commands still need
explicit authorization. Several Near items are offline-completable
(`agent_check` + UI) and should stay that way until a play path is
involved.
