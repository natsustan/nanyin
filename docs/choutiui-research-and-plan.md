# ChouTiUI research and integration plan for Classic 2010

Status: research completed 2026-08-22; decision revised same day to **narrow
adoption** (owner preference: reuse ChouTiUI's ready-made implementations and
accept the bridging cost). Companion to `classic-2010-theme-plan.md`. This
document does not authorize live Spotify testing.

## Question

Can [honghaoz/ChouTiUI](https://github.com/honghaoz/ChouTiUI) serve as the
drawing foundation for the Classic 2010 theme — glossy gradients, etched text,
inset search fields, pill buttons, gradient section headers?

## Research summary (verified against source, 2026-08-22)

### What ChouTiUI is

- Swift framework for macOS 10.15+ / iOS 13+, SwiftPM, Swift 5.9.
- Core stack: **AppKit/UIKit + CALayer + ComposeUI**. There is no SwiftUI
  import anywhere in the source and no `NSViewRepresentable` bridge.
- Two source dependencies, both tracked at **`branch: "master"`** (not
  semver): `honghaoz/ChouTi` (utilities) and `honghaoz/ComposeUI`
  (declarative AppKit/UIKit UI). `import ChouTiUI` re-exports ComposeUI.
- One published release: `0.0.1` (2025-04). README labels the project WIP.
  Active maintenance through 2026-08; 100+ test files; daily CI on
  macOS/iOS/tvOS/visionOS. Real shipped apps use it.

### Capabilities relevant to Classic 2010

| Capability | Quality | Notes |
|---|---|---|
| Multi-stop linear/radial/angular gradients | Excellent | `LinearGradientColor` with stops/locations/unit points; draws into `CGContext` or auto-managed `CAGradientLayer` sublayer via `layer.setBackgroundColor(_:)` |
| Skeuomorphic presets | Excellent | `silverChrome`, `concaveGray`, `convexGray` built-in — directly in the 2010 visual language |
| Solid/gradient unified tokens | Excellent | `UnifiedColor` enum; `ThemedUnifiedColor` for light/dark pairs |
| Gradient borders, inset/offset borders | Good | `Border` + `BorderLayer`; plain `CALayer.border` limited to solid colors |
| Continuous corners / superellipse / capsule | Excellent | Custom `Shape` protocol (CGPath-based) + auto-maintained mask layers |
| Etched/engraved text | Adequate | Fluent `NSAttributedString` styling with `NSShadow`; no gradient text or emboss engine |
| Unified layer shadows | Weak | No `Shadow` value type symmetric to `Border`; falls back to raw `CALayer.shadow*` |
| SwiftUI components | **None** | No SwiftUI API surface at all |

### Frictions specific to Nanyin

1. **No SwiftUI bridge.** Nanyin is a pure SwiftUI app (zero
   `NSViewRepresentable` usages today, zero SPM dependencies). Every ChouTiUI
   use requires a hand-written representable wrapper plus state
   synchronization for hover/pressed/focus/disabled — exactly the interaction
   states Phase 2 of the theme plan enumerates.
2. **Namespace collisions.** ChouTiUI declares `Shape`, `Rectangle`,
   `Circle`, `Capsule`, `Ellipse`, `Color`, `UnitPoint` — all colliding with
   SwiftUI. Any file importing both needs pervasive qualification. Since
   every themed view in Nanyin imports SwiftUI, this cost lands on the whole
   `Views/` tree if the library leaks past a wrapper boundary.
3. **Reproducibility.** Pinning a ChouTiUI tag still resolves `ChouTi` and
   `ComposeUI` at `master`. Nanyin currently ships with no third-party Swift
   dependencies; the first one should not be an `0.0.1` package with
   branch-tracked transitive deps.
4. **List performance rules.** Track tables must keep `List` (NSTableView
   recycling) with row-local hover state. AppKit-wrapped rows inside `List`
   risk recycling and invalidation regressions that the AGENTS.md 60Hz rules
   forbid.
5. **Redundancy at macOS 15.** Nanyin's deployment target is macOS 15.0.
   Native SwiftUI already covers the required effects:
   - multi-stop `Gradient(stops:)` / `LinearGradient`
   - inset shadows: `ShapeStyle.shadow(.inner(...))` (macOS 13+)
   - continuous corners: `UnevenRoundedRectangle`, `.rect(cornerRadius:style:.continuous)`
   - etched text: layered `Text` shadow (offset ±1pt, zero blur)
   - gradient strokes: `.strokeBorder(LinearGradient(...))`

   ChouTiUI's payoff is real in AppKit codebases; Nanyin is not one.

## Decision

**Narrow adoption.** Add ChouTiUI as a real dependency and reuse its
ready-made implementations (`convexGray`/`concaveGray`/`silverChrome`
presets, `UnifiedColor` gradient layers, `Capsule`/`SuperEllipse` masks,
border layers) for Classic 2010 **chrome components only**, each wrapped in a
dedicated `NSViewRepresentable`. The owner accepts the bridging cost in
exchange for direct reuse instead of re-deriving the recipes in SwiftUI.

Hard boundaries that make the adoption "narrow":

1. **Chrome only, never list content.** Track tables, source-list rows,
   selected-row fills, popularity bars, and every `List` row stay pure
   SwiftUI. The AGENTS.md 60Hz rules (NSTableView recycling, row-local hover)
   forbid AppKit-wrapped rows.
2. **Two-file-layer isolation.** ChouTiUI is imported only inside
   `NanyinApp/Classic/Chrome/` (AppKit view classes; `import AppKit` +
   `import ChouTiUI`, no SwiftUI). The representable wrappers live in
   `NanyinApp/Classic/Bridge/` (`import SwiftUI`, no ChouTiUI). This sidesteps
   the `Shape`/`Capsule`/`Color`/`Rectangle` name collisions entirely: no
   file ever imports both frameworks.
3. **Our theme system stays authoritative.** Do not use ChouTiUI's
   `Themed*`/`effectiveAppearance` theming — both Nanyin themes are dark and
   theme selection flows through the `AppTheme` environment. Bridges pass
   resolved role/state values into the chrome views in `updateNSView`.
4. **Pinned, vendored, offline.** Dependencies are vendored checkouts at
   pinned revisions following the existing librespot convention (see
   Dependency strategy), keeping `script/agent_check.sh` deterministic and
   network-free.

### Rejected alternatives

- "Port the recipes, not the dependency" (initial recommendation): avoids the
  dependency but re-derives what the library already ships. Owner prefers
  direct reuse; superseded 2026-08-22.
- Full adoption (ChouTiUI as the app-wide drawing foundation): conflicts with
  the environment-injected semantic-token architecture and the List-recycling
  performance rules. Still rejected.

## Bridge architecture

```diagram
┌───────────────────────────────────────────────────────────────┐
│ SwiftUI: Classic2010Shell / PlayerBar Classic presentation     │
│   reads AppTheme environment, owns interaction-independent     │
│   layout and all text                                          │
└───────────────┬───────────────────────────────────────────────┘
                │ role enum + metrics + isEnabled + callbacks
┌───────────────▼───────────────────────────────────────────────┐
│ NanyinApp/Classic/Bridge/  (import SwiftUI only)               │
│   ChromeButton, ChromeSearchField, ChromeSectionBar,           │
│   ChromeSliderTrack — NSViewRepresentable, sizing, focus,      │
│   accessibility labels                                         │
└───────────────┬───────────────────────────────────────────────┘
                │ plain value types (no ChouTiUI, no SwiftUI)
┌───────────────▼───────────────────────────────────────────────┐
│ NanyinApp/Classic/Chrome/  (import AppKit + ChouTiUI)          │
│   ClassicChromeButtonView, ClassicSearchFieldView, …           │
│   layer.shape = Capsule() / SuperEllipse(...)                  │
│   layer.setBackgroundColor(.convexGray / .concaveGray / …)     │
│   NSTrackingArea hover, mouseDown pressed, BorderLayer         │
└───────────────────────────────────────────────────────────────┘
```

- The Bridge↔Chrome contract is a small plain configuration struct
  (`ChromeStyle`: role, corner treatment, metrics) plus state flags and an
  action callback. Chrome maps role → ChouTiUI preset internally, so ChouTiUI
  types never appear in a public signature.
- Hover and pressed state are tracked inside the AppKit view
  (`NSTrackingArea`, `mouseDown`/`mouseUp`), not synchronized from SwiftUI;
  SwiftUI only supplies enabled/disabled, focus, and semantic state
  (e.g. playing/paused glyph). This keeps `updateNSView` cheap and avoids
  representable state ping-pong.
- Each wrapped component reports a fixed intrinsic size from theme metrics so
  SwiftUI layout stays deterministic.
- Text inside chrome (button captions, section titles) is rendered by SwiftUI
  overlays where possible so etched-text styling stays in one place; the
  AppKit layer renders background, gloss, border, and glyph shapes only.

## Dependency strategy (vendored, librespot convention)

ChouTiUI's manifest tracks `ChouTi` and `ComposeUI` at `branch: "master"`, so
a remote SPM reference is not reproducible and would force network access in
`agent_check.sh`. Follow the existing vendored-librespot pattern instead:

1. Vendor `research-repos/ChouTiUI`, `research-repos/ChouTi`, and
   `research-repos/ComposeUI` as git checkouts at pinned revisions
   (git-ignored, like librespot).
2. Add `patches/choutiui-path-dependencies.patch`: a minimal patch to
   ChouTiUI's `Package.swift` replacing the two `branch: "master"` URL
   dependencies with `path: "../ChouTi"` / `path: "../ComposeUI"`.
3. Add a `script/vendor_choutiui.sh` setup script that clones the three
   repositories, checks out the pinned SHAs (recorded in the script), and
   applies the patch. Pinned SHAs live in-repo because the checkouts are
   git-ignored.
4. Declare the local package in `project.yml`:

   ```yaml
   packages:
     ChouTiUI:
       path: research-repos/ChouTiUI
   # target Nanyin dependencies: add `- package: ChouTiUI`
   ```

5. Extend `script/agent_check.sh` (same shape as the librespot checks):
   checkout exists, HEAD equals the pinned SHA, patch applies in reverse
   exactly, and the working trees are clean.
6. Upgrades are deliberate: bump the SHAs in `vendor_choutiui.sh`, re-run it,
   re-verify the patch, run the full agent check. Never track `master`.

## Component mapping: 2010 reference → owner → implementation

Reference regions from the Rasmus-era screenshots, mapped to who renders them
(wrapped ChouTiUI chrome vs pure SwiftUI) and how:

```diagram
┌──────────────────────────────────────────────────────────────┐
│ ● ● ●  ◀ ▶  ( 🔍 search           )        ← A  toolbar      │
├────────────────┬─────────────────────────────────────────────┤
│ SIDEBAR    + ← B│ Page title                    ← C  header  │
│  What's new    ├─────────────────────────────────────────────┤
│  Radio         │ ▓ Top hits ▓                  ← D  section  │
│  ★ Starred     ├────┬────────────┬─────────┬────────┬───────┤
│  Playlists     │ ☆  │ Track      │ (Buy) ←F│ Time   │▮▮▮▯▯←G│
│────────────────│░░░░│░selected░░░░░░░░░░░░░░░░░░░░░ ← E ░░░░│
│ CURRENT TRACK  │    │            │         │        │       │
│  [Album Art]   │    │            │         │        │       │
├────────────────┴─────────────────────────────────────────────┤
│ ◀ ❚❚ ▶  🔊─●  0:06 ━━●━━━━━━━━━ 3:14   🔀 ↻    ← H  deck    │
└──────────────────────────────────────────────────────────────┘
```

| # | Component | Owner | Implementation |
|---|---|---|---|
| A | Glossy graphite toolbar surface | **Chrome (ChouTiUI)** | `ClassicToolbarView`: `convexGray`-family vertical gradient via `layer.setBackgroundColor`, hairline highlight/shadow sublayers |
| A | Inset rounded search field | **Chrome (ChouTiUI)** | `ClassicSearchFieldView`: `concaveGray` fill, `Capsule` shape, inset `BorderLayer`; text editing stays an embedded `NSTextField`/SwiftUI overlay decision in Phase 3 |
| B | Sidebar section headers, etched labels | Pure SwiftUI | `Text` + `.shadow(color:radius:0,x:0,y:1)`; wrapping every label is not worth a bridge |
| C | Page/tab header bar | **Chrome (ChouTiUI)** | shares `ClassicSectionBarView` treatment (square corners, two-stop gradient) |
| D | Section header strips ("Top hits", "Albums") | **Chrome (ChouTiUI)** | `ClassicSectionBarView` background; caption text as SwiftUI overlay |
| E | Selected row (glossy blue) | Pure SwiftUI (hard rule) | row background `LinearGradient` + top/bottom hairlines; stays inside `List` rows |
| F | Pill buttons (Nanyin's own actions in the period pill language) | **Chrome (ChouTiUI)** | `ClassicChromeButtonView`: `Capsule` mask, `convexGray`↔`concaveGray` swap on pressed, tracked in AppKit |
| G | Popularity/level bars | Pure SwiftUI (hard rule) | `Canvas` or fixed segment `HStack` inside rows |
| H | Transport buttons (back/play/next), shuffle/repeat | **Chrome (ChouTiUI)** | circular `ClassicChromeButtonView` variant; glyphs as CGPath shapes drawn in the chrome layer |
| H | Progress/volume slider tracks | **Chrome (ChouTiUI)** | `ClassicSliderView`: `silverChrome`/`concaveGray` track, capsule mask; drag/seek events forwarded through the bridge callback to the existing `PlayerBar` seek owner |

Gradient stop values, hairline colors, and metrics still live as **semantic
tokens in `AppTheme`** (the main plan's Phase 1/2 seam); bridges resolve
tokens to plain values before handing them to Chrome. Where a ChouTiUI preset
matches the reference closely enough, Chrome uses the preset directly and the
token records that choice.

## Concrete work items (amendments to classic-2010-theme-plan.md)

The main plan's phases stay in order. One new phase is inserted; it can run
in parallel with Phase 1/2 because it touches no existing view.

### New Phase 2.5 — dependency vendoring and bridge spike

Files: `script/vendor_choutiui.sh`, `patches/choutiui-path-dependencies.patch`,
`project.yml`, `script/agent_check.sh`, new `NanyinApp/Classic/Chrome/` and
`NanyinApp/Classic/Bridge/` directories, an offline preview harness.

1. Vendor the three checkouts at pinned SHAs; apply and commit the manifest
   patch artifact; wire `project.yml` `packages:`; regenerate with xcodegen.
2. Extend `agent_check.sh` with the vendored-ChouTiUI checks (existence,
   pinned SHA, patch applied, clean tree) and confirm the xcodebuild step
   still passes offline.
3. Build one end-to-end spike: `ClassicChromeButtonView` + `ChromeButton`
   representable rendered in an offline SwiftUI preview with hover, pressed,
   and disabled states. This validates the two-layer isolation, intrinsic
   sizing, and List-independence before Phase 3 depends on it.
4. Acceptance: `./script/agent_check.sh` passes on a clean checkout after
   running only `vendor_choutiui.sh`; the spike preview shows all interaction
   states; no file imports both SwiftUI and ChouTiUI.

### Phase 1/2 (unchanged scope, one addition)

Semantic tokens must be expressible as solid-or-gradient fills so both the
SwiftUI-rendered surfaces (rows, labels) and the Chrome-rendered surfaces
(buttons, bars) resolve from one token set. `nanyinDark` tokens stay solid,
preserving the zero-visual-change gate.

### Phase 3/4 — consume wrapped chrome

The main plan's primitive candidates map to bridges as follows: inset field
chrome → `ChromeSearchField`; compact section/header bar → `ChromeSectionBar`;
transport button style → `ChromeButton`; period slider treatment →
`ChromeSliderTrack`. Themed separator and row treatments remain pure SwiftUI.
`NanyinDarkShell` never instantiates a bridge; Chrome components are
Classic-2010-only.

### Explicitly out of scope for v1

- Using ChouTiUI inside any `List` row or any Nanyin Dark surface.
- ChouTiUI's `Themed*` appearance system and ComposeUI's declarative node API
  (it is re-exported but unused; treat it as off-limits in review).
- Animated gradient cross-fades between interaction states. Classic 2010
  states may switch instantly (period-accurate) — reassess in Phase 5
  calibration.

## Risks specific to narrow adoption

- **Bridge sprawl.** The wrapped-component list above is closed; adding a new
  bridge requires updating this document. Review rule: reject PRs that import
  ChouTiUI outside `NanyinApp/Classic/Chrome/`.
- **0.0.1 API drift.** Pinned SHAs mean drift only lands on deliberate
  upgrades; the spike + agent check gate catches breakage before it reaches
  theme work.
- **Focus/keyboard/VoiceOver parity.** AppKit-wrapped controls must expose
  accessibility labels, focus rings, and key equivalents equal to their
  SwiftUI counterparts — Phase 4 acceptance criteria in the main plan apply
  to bridges unchanged.
- **Theme switching.** Switching to Nanyin Dark tears down Chrome views with
  the Classic shell; verify no CALayer animation or tracking-area callback
  fires after teardown (same discipline as the main plan's
  playback-continuity gate).

## License note

ChouTiUI, ChouTi, and ComposeUI are MIT. Vendored checkouts keep their
LICENSE files; ship the MIT notices in an acknowledgements section of the app
(same obligation as any bundled MIT dependency). Reference screenshots remain
research-only per the main plan's asset policy.

## Revisit triggers

Re-evaluate the integration shape if any of these become true:

1. ChouTiUI reaches a tagged release whose manifest pins semver ranges for
   ChouTi/ComposeUI — consider replacing vendored checkouts with a pinned
   remote SPM reference.
2. Bridge count pressure grows beyond the closed list above — reconsider
   whether the marginal component belongs in SwiftUI instead.
3. Upstream ships a SwiftUI bridge layer — simplify `Classic/Bridge/`
   accordingly.
