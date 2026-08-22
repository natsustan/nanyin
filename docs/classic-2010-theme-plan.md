# Classic 2010 theme implementation plan

Status: design direction confirmed on 2026-08-22. This plan covers implementation sequencing and acceptance criteria; it does not authorize live Spotify testing.

Related: `choutiui-research-and-plan.md` records the 2026-08-22 ChouTiUI evaluation — decision (revised same day): narrow adoption. ChouTiUI is vendored at pinned revisions (librespot convention) and renders Classic-2010 chrome components (toolbar, search field, section bars, pill/transport buttons, slider tracks) behind `NSViewRepresentable` bridges; `List` rows and all Nanyin Dark surfaces stay pure SwiftUI. It inserts a Phase 2.5 (vendoring + bridge spike) between the token and shell phases.

## Outcome

Add a runtime-switchable `Classic 2010` theme to Nanyin, based on the 2006–2010 Spotify desktop design documented by founding design lead Rasmus Andersson, while retaining Nanyin's identity, features, native macOS behavior, accessibility, and performance.

The theme must be a coherent skin rather than a palette swap. It changes semantic colors and typography, information density, window chrome inside the content area, source-list treatment, track-table structure, now-playing placement, and playback controls. It must not change playback/session behavior or invent unsupported historical features.

The existing appearance remains available as `Nanyin Dark`. Theme selection persists across launches and is exposed through native macOS UI.

## Product and source decisions

- Public theme name: **Classic 2010**. Do not use `Spotify` in the theme name or imply endorsement.
- Historical baseline: Rasmus Andersson's [Spotify work archive](https://rsms.me/work/spotify/), especially `desktopapp.png`, `handcrafted-pixels.png`, and `desktopui.png`.
- Fidelity model: historical visual logic plus modern native behavior. Window management, keyboard access, VoiceOver, focus, Reduce Motion, and current data semantics win over literal historical reproduction.
- Color strategy: restrained graphite layers with a low-saturation moss-green action/state accent. Do not project today's Spotify `#1DB954` backward.
- Asset policy: independently draw generic controls and icons. Do not ship historical screenshots, logos, proprietary bitmap controls, font files, or extracted icon sheets.
- Functional mapping: omit People, Buy, Offline, social-sharing, and other unsupported features. Do not add inert UI to fill historical regions.
- Right pane: deferred. A future queue inspector may use that region, but Classic 2010 v1 remains sidebar + content so it works at Nanyin's current 900-point minimum width.
- Theme scope: all existing app surfaces, including login, restoring/signing-out states, Home, Search, Queue, playlist/album/artist detail, Saved Albums, New Playlist sheet, toolbar, context-sensitive controls, and empty/loading/error states.

## Target interaction model

```text
┌──────────────────────────────────────────────────────────────┐
│ ● ● ●  ◀ ▶  [ Search Nanyin                         ]       │
├────────────────┬─────────────────────────────────────────────┤
│ HOME           │ Page title / result summary                 │
│ Search         ├────┬────────────┬──────────┬────────┬──────┤
│ Queue          │ ☆  │ Track      │ Artist   │ Album  │ Time │
│ Library        │    │            │          │        │      │
│─────────────── │    │            │          │        │      │
│ PLAYLISTS    + │    │            │          │        │      │
│ …              │    │            │          │        │      │
│                │    │            │          │        │      │
├────────────────┤    │            │          │        │      │
│ CURRENT TRACK  │    │            │          │        │      │
│                │    │            │          │        │      │
│   Album Art    │    │            │          │        │      │
│                │    │            │          │        │      │
├────────────────┼────┴────────────────────────────────────────┤
│ ◀  ❚❚  ▶  🔊━━●│ 1:42 ━━━━━━━━━●━━━━━━━━ 3:57   🔀 ↻ Queue │
└────────────────┴─────────────────────────────────────────────┘
```

- Global search remains visible in the Classic 2010 shell. `⌘K` and `⌘F` focus it; submitting opens Search and preserves the existing debounced query/results path.
- Source-list rows use compact, square-edged selection fills. Navigation, counts, loading/empty/failure states, playlist creation, and account actions remain available.
- Track tables use compact one-line rows in Classic 2010: state/favorite, track, artist, album, and duration. Current Nanyin Dark retains its existing two-line title/artist cell.
- Single click selects, double click plays, and context menus expose less-common actions. Keyboard and accessibility paths remain available.
- Classic 2010 places large current artwork and metadata at the bottom of the source column. The segmented bottom strip contains transport, progress, volume, shuffle/repeat, and queue access.
- Theme changes are immediate and unanimated. Playback, selection, page history, search state, and scroll content must not reset.

## Architecture

### Theme seam

Create one environment-injected immutable theme value. Keep its interface small enough that views ask for semantic roles, not historical implementation details:

```swift
enum AppThemeID: String, CaseIterable, Identifiable {
    case nanyinDark
    case classic2010
}

struct AppTheme {
    let id: AppThemeID
    let colors: Colors
    let typography: Typography
    let metrics: Metrics
}
```

`Colors`, `Typography`, and `Metrics` are nested value types. Their fields are semantic (`contentBackground`, `selectedRow`, `trackPrimary`, `compactRowHeight`) rather than era-specific (`spotifyGray3`, `aquaHeader`). Two concrete values, `nanyinDark` and `classic2010`, make this a real seam rather than hypothetical abstraction.

Do not introduce a theme protocol, view type erasure, a registry, dynamic plug-ins, JSON theme files, or arbitrary user-editable tokens. Future built-in iTunes-era themes can add another `AppThemeID` and value; add a registry only when built-in static definitions stop being sufficient.

### State ownership and persistence

- Keep appearance outside `AppModel`; playback and Web API state must not learn about skins.
- Store the stable raw `AppThemeID` in `UserDefaults` through `@AppStorage("appearance.theme")` at scene/UI ownership points.
- Resolve unknown or removed stored values to `nanyinDark` without rewriting unrelated preferences.
- Inject the resolved `AppTheme` at the `WindowGroup` root with a custom SwiftUI environment key.
- Use the same preference key in the Settings scene and Appearance command menu. No separate observable store is needed for one durable scalar preference.

### Structural variants

Palette/metric differences flow through the theme environment. Layout differences stay in the views that own those layouts:

- `RootView` owns auth routing only.
- Extract the current page switch into one shared `AppContentView`; both shells render the same content owner.
- Introduce two shell adapters at a real seam: `NanyinDarkShell` preserves today's layout, and `Classic2010Shell` composes the compact toolbar, source column, content, now-playing artwork, and segmented control strip.
- Keep `PlayerBar` as the owner of its local 400 ms playback-position tick and seek drag state. It selects private theme-specific presentations underneath that state owner; do not create a second timer or move position into `AppModel`.
- Keep source-list data/actions shared. Classic-only artwork placement belongs to the Classic shell/sidebar presentation, not duplicated playlist/navigation logic.
- Branch on `theme.id` only at these genuine structural ownership points. Shared leaf views consume semantic tokens and must not accumulate theme-ID conditionals.

### Reusable visual primitives

Add a named primitive only when at least two call sites need the same interaction and rendering contract. Expected candidates are:

- inset field chrome for global/page search;
- compact section/header bar;
- transport button style with default/hover/pressed/disabled states;
- themed separator and selected/hovered row treatment;
- compact period slider track/thumb treatment.

Do not create wrappers for a single gradient, one-off padding value, or a single screen. Keep those details local or in semantic tokens.

### Typography and assets

- Use system fonts only. Classic 2010 can request a compact system face/weight/size but must not bundle or claim an exact historical typeface.
- Prefer independently drawn SwiftUI `Shape`/`Canvas` glyphs for transport controls where modern SF Symbols visibly break the period language. Generic SF Symbols may remain when their silhouette is neutral and they sit inside themed chrome.
- Keep artwork remote/cache behavior unchanged. Historical screenshots are research evidence only.
- Move `Theme.fmtTime` out of the visual theme namespace into a small shared playback-time formatter because both player layouts and track tables use it independently of appearance.

## Work phases

### Phase 1 — Theme foundation with zero intended visual change

Files:

- `NanyinApp/Views/Theme.swift`
- `NanyinApp/NanyinApp.swift`
- new `NanyinApp/Views/ThemeSettingsView.swift`
- `Tests/StateReducerTests.swift` or a focused new pure Swift theme test file wired into `script/agent_check.sh`

Work:

1. Replace static global color constants with `AppThemeID`, immutable `AppTheme`, semantic nested tokens, and an environment key.
2. Define `nanyinDark` tokens to match the current rendered values before changing Classic behavior.
3. Add durable selection with safe fallback for unknown raw values.
4. Add a native `Settings` scene with one Appearance picker and a `Theme` command menu with checkmarked choices. Do not duplicate shortcuts.
5. Inject the selected theme at the root. Keep `.preferredColorScheme(.dark)` for both initial themes; reconsider only when a future light theme exists.
6. Move playback time formatting out of the theme namespace.

Acceptance:

- `Nanyin Dark` is the default for fresh and unknown preferences.
- Changing the preference updates the environment immediately and survives process restart.
- With `Nanyin Dark` selected, no deliberate geometry, color, typography, or behavior change is introduced.
- Theme preference tests cover default, round trip, and unknown-value fallback.
- `./script/agent_check.sh` passes without launching Nanyin or contacting Spotify.

### Phase 2 — Token migration and visual-state inventory

Files:

- all files under `NanyinApp/Views/`
- optional root `DESIGN.md` generated from the settled semantic tokens

Work:

1. Replace hard-coded `.white`, `.black`, `Color(white:)`, ad hoc orange/error surfaces, divider colors, corner radii, shadows, row heights, and common paddings with semantic tokens where the value participates in the theme.
2. Preserve semantic system colors for errors/warnings where they already provide accessibility, but give each theme an appropriate container treatment.
3. Define every interactive state used by both themes: default, hover, focus, pressed, selected, disabled, loading, error, and current-playing.
4. Keep hover state row/card-local and preserve `List` recycling.
5. Do not restructure screens in this phase; this isolates behavior-preserving migration from the visual change.

Acceptance:

- A targeted search finds no unexplained app-wide visual literals in feature views; intentional content-specific colors are commented or locally named.
- Nanyin Dark remains visually equivalent by review.
- No same-axis nested scrolling is introduced, no app-wide playback-position observation is added, and list rows retain local hover state.
- `./script/agent_check.sh` passes.

### Phase 3 — Classic 2010 shell and playback deck

Files:

- `NanyinApp/Views/RootView.swift`
- `NanyinApp/Views/SidebarView.swift`
- `NanyinApp/Views/PlayerBar.swift`
- `NanyinApp/NanyinApp.swift`
- small new shell/chrome files only if extraction leaves each owner clearer than keeping private subviews

Work:

1. Extract shared page routing into `AppContentView` and preserve auth routing in `RootView`.
2. Preserve the current shell as `NanyinDarkShell` and add `Classic2010Shell`.
3. Build the graphite toolbar with back/forward controls and persistent global search.
4. Add compact source-list headers, rows, separators, playlist creation, account state, and large current artwork/metadata region.
5. Add the segmented Classic control strip while preserving the single local player tick/seek owner.
6. Keep the current Queue page and button; do not add a right inspector in this phase.
7. Ensure Classic geometry collapses safely at 900×600 and scales up without oversized empty chrome.

Acceptance:

- Switching themes during active playback does not interrupt audio, reset position, recreate `AppModel`, change page/history, or lose search state.
- Both shells expose every existing navigation and playback action.
- Classic 2010 renders coherently at 900×600, 1280×800, and a wide desktop window.
- All primary controls have visible hover, pressed, focus, and disabled states.
- Position remains locally ticked in `PlayerBar`; no track-list-wide periodic invalidation occurs.
- `./script/agent_check.sh` passes.

### Phase 4 — Classic tables and content surfaces

Files, in implementation order:

1. `NanyinApp/Views/TrackListView.swift`
2. `NanyinApp/Views/SearchView.swift`
3. `NanyinApp/Views/PlaylistDetailView.swift`
4. `NanyinApp/Views/ArtistDetailView.swift`
5. `NanyinApp/Views/SavedAlbumsView.swift`
6. `NanyinApp/Views/HomeView.swift`
7. `NanyinApp/Views/QueueView.swift`
8. `NanyinApp/Views/LoginView.swift`
9. `NanyinApp/Views/NewPlaylistSheet.swift`

Work:

1. Add Classic's one-line table presentation with separate Track/Artist/Album/Time columns and compact row metrics; keep stable occurrence IDs, selection, double-click, context menus, likes, and current-playing indication.
2. Reuse the shell search field in Classic instead of rendering a second large page field. Keep Nanyin Dark's current Search layout.
3. Restyle detail headers into compact period bars and aligned metadata without removing existing actions.
4. Reduce modern card cues in Classic: small corner radii, no broad soft shadows, square-edged section structure, denser album/artist displays. Preserve bounded horizontal scrollers and the single vertical scroll region.
5. Theme all empty/loading/error/partial-error states; do not hide failures to match a historical screenshot.
6. Theme login and playlist creation last so the app never presents a half-themed modal or auth state.

Acceptance:

- Every existing page and state has a coherent Classic presentation with no fallback Nanyin Dark islands.
- Track lists remain virtualized and smooth with large libraries.
- Rapid hover movement only invalidates involved rows/cards.
- Long track/artist/album names truncate without overlapping duration or action columns.
- Current, selected, hover, liked, disabled, and unavailable states remain distinguishable without relying on color alone.
- Keyboard, VoiceOver labels, context menus, and tooltips remain available.
- `./script/agent_check.sh` passes.

### Phase 5 — Visual calibration and release gate

Work:

1. Build an offline visual fixture/preview for shell, track table, source list, player states, empty/loading/error states, and long text. It must not read Keychain or contact Spotify.
2. Capture Nanyin at 1× and 2× backing scale where available and compare geometry, hierarchy, and control states against the research references. Do not use source screenshots as composited app assets.
3. Verify text/background contrast, keyboard focus, VoiceOver navigation order, Increase Contrast, Reduce Motion, and system accent independence.
4. Profile or instrument only if visual inspection reveals scrolling or theme-switch regressions; do not add speculative caching.
5. Run `./script/agent_check.sh` as the required non-live release gate.
6. Run the real app only after explicit live authorization. At the first dealer/spirc warning, follow the repository stop-loss rules; visual QA never justifies continued Spotify traffic.

Acceptance:

- Offline reference captures cover both themes and the required state matrix.
- No historical Spotify production asset or mark exists in the app bundle.
- Theme switching has no network, auth, playback-token, Rust-core, or Keychain side effect.
- Non-live agent checks pass.
- Any remaining visual differences from the source are documented as deliberate Nanyin adaptations, not called pixel-perfect fidelity.

## File-by-file impact map

| File | Planned responsibility |
|---|---|
| `NanyinApp/Views/Theme.swift` | Theme IDs, immutable definitions, semantic tokens, environment key, repeated theme-aware visual primitives only. |
| `NanyinApp/NanyinApp.swift` | Persisted selection, root injection, Settings scene, Theme menu, existing dark color-scheme policy. |
| `NanyinApp/Views/ThemeSettingsView.swift` | Native Appearance picker and brief non-affiliation/history-safe labels. |
| `NanyinApp/Views/RootView.swift` | Auth routing, shared page owner, shell adapter selection. |
| `NanyinApp/Views/SidebarView.swift` | Shared source-list data/actions and theme-aware source presentation; Classic now-playing region. |
| `NanyinApp/Views/PlayerBar.swift` | One position/seek state owner with Nanyin Dark and Classic 2010 presentations. |
| `NanyinApp/Views/TrackListView.swift` | Existing comfortable rows plus Classic compact columnar adapter; shared identity/actions. |
| `NanyinApp/Views/SearchView.swift` | Shared search state/behavior; shell-hosted Classic field versus page-hosted Nanyin Dark field. |
| `HomeView`, detail views, `QueueView`, `SavedAlbumsView` | Semantic tokens first; Classic density/chrome adaptations without data-flow changes. |
| `LoginView`, `NewPlaylistSheet` | Complete theme coverage and native accessibility states. |
| tests / `script/agent_check.sh` | Pure preference resolution tests and any offline fixture compilation required by the existing agent gate. |

## Risks and mitigations

### Theme branches spread through every view

Mitigation: theme IDs are inspected only at shell, player, search-hosting, and track-layout ownership seams. Leaf views consume semantic values. Reject helper flags such as `isAqua`, `usesBevel`, and `isCompact` scattered across callers.

### Future themes require different topology

Mitigation: two shell adapters establish the first real structural seam. Do not force future iTunes-era themes into Classic 2010's geometry; add a third adapter only when that theme is designed.

### Visual migration accidentally changes playback behavior

Mitigation: separate behavior-preserving token migration from shell/layout changes. Keep `AppModel`, Rust FFI, reconnect logic, player generation, and token flows out of this work. Keep the existing local position tick owner.

### Historical density harms accessibility

Mitigation: compact visible rows may use larger hit regions where geometry permits; preserve keyboard/context-menu alternatives, focus rings, VoiceOver labels, and Increase Contrast. Use icon plus shape/text state, not color alone.

### Exact copying creates brand or asset risk

Mitigation: ship Nanyin naming, independently drawn generic symbols, system fonts, and independently reconstructed gradients. Keep source images linked from research only.

### Refactor blast radius becomes too large to review

Mitigation: execute phases in order and keep each phase independently buildable. Phase 1 and Phase 2 must preserve appearance; Phase 3 changes only shell/player; Phase 4 migrates screens one at a time. Do not combine playback behavior changes with any phase.

## Definition of done

Classic 2010 is done when a user can select it from native macOS UI, see the complete app adopt the confirmed dense Rasmus-era visual system, quit and reopen with the choice preserved, use every existing listening/browsing action without relearning its semantics, and switch back to Nanyin Dark without playback or state interruption. Both themes pass the non-live agent check, accessibility/state review, large-list performance review, and offline visual reference matrix.
