# Spirc: keep-or-remove decision and control/data-plane boundary plan

Status: ACCEPTED (Phase 1 and Phase 2 implemented; live verification pending)
Date: 2026-08-21
Related: `docs/playback-recovery-research.md` (six-tree recovery research),
AGENTS.md risk-control hazards, ROADMAP M2 exit criteria.

## 1. Decision

**Keep Spirc.** Spend the refactor budget on enforcing the control-plane /
data-plane boundary and on a one-shot pending-play replay — not on removing
Spirc.

This is an architecture decision record: revisit only if the product
direction changes (see §6), not on the next dealer flake.

## 2. Context

The recurring symptom class ("connection lost", click-play does nothing,
audio stalls mid-track) conflates two independent planes:

```text
┌─────────────────────────────────┐  ┌──────────────────────────────────┐
│ CONTROL PLANE (recoverable)     │  │ DATA PLANE (independent)         │
│ AP Session / Dealer WS / Spirc  │  │ CDN ranges / decrypt / decode /  │
│ context resolution / commands   │  │ PCM / AVAudioEngine              │
│                                 │  │                                  │
│ short outage must NOT interrupt │  │ stall recovers locally (seek /   │
│ already-playing audio           │  │ renderer restart) — never via    │
│                                 │  │ token refresh or session rebuild │
└─────────────────────────────────┘  └──────────────────────────────────┘
```

Verified facts driving the decision:

- Spirc is not required to *play audio* (psst/cliamp prove the Player-only
  route), but it is required for everything ROADMAP promises: server-resolved
  contexts (`spotify:user:<id>:collection` for 1129 Liked Songs,
  `spotify:playlist:…`, `spotify:album:…`), Connect *device* identity,
  phone → nanyin transfer, shuffle/repeat round-trip with the phone
  (M2 exit criteria), server-side unplayable/region/autoplay decisions.
- Removing Spirc re-opens the exact hazards this repo learned the hard way:
  client-side context assembly means paging + uploading large URI lists
  (hazard #5, 429 incident) and novel request shapes from the primary
  account (hazard #8b).
- The codebase is past the "early project" window: `rust/src/lib.rs` routes
  all transport commands (play/pause/next/prev/shuffle/repeat/volume/queue/
  context-play) through Spirc, and that surface is live-verified. A removal
  is a control-plane rewrite plus full re-verification under risk-control
  constraints, for negative feature delta.
- The actual bugs are boundary violations, not Spirc itself:
  1. A play command accepted during a dealer outage window returns rc=0 but
     is never confirmed nor replayed by librespot (verified: librespot does
     not replay commands accepted before a dealer reconnect).
  2. The current 8s `scheduleContextFallback` degrades a *connection-window*
     failure into a 50-URI upload — the wrong tool (it was designed for
     server-side context-resolution stalls) and a step toward hazard #5.
  3. Mid-track audio stalls (~1:06 symptom) are data-plane events; they are
     already handled locally by `audioStallWatchdog` + seek/renderer
     recovery and must never trigger token/session work.

## 3. Alternatives considered

| Option | Verdict |
|---|---|
| Remove Spirc, drive `Player` directly (psst/cliamp route) | Rejected for now. Loses Connect device + transfer + server contexts; forces client-side queue/shuffle/repeat/autoplay engine; re-introduces large-URI uploads and novel traffic shapes on the primary account. |
| Keep Spirc, treat dealer loss as whole-player death | Rejected. Already partially the status quo; rebuilds are handshake-heavy, and short dealer outages provably do not harm an already-loaded stream. |
| Keep Spirc + enforce plane boundary + one-shot pending-play replay | **Chosen.** Smallest change that fixes the observed failure, no new traffic shapes, aligned with `docs/playback-recovery-research.md` conclusions. |

## 4. Implementation plan

### Phase 1 — Pending-play intent with one-shot replay

The core fix: `rc=0` means "command submitted", not "playback started".
Success is the matching `PlayerEvent::Playing`. If the dealer reconnects
while an intent is unconfirmed, replay the original server-resolved call
exactly once.

**New state (AppModel):**

```swift
struct PendingPlayIntent {
    enum Call {
        case context(uri: String, index: Int)   // Core.playContext
    }
    let call: Call
    let trackURI: String?        // best-effort confirmation match
    let accountEpoch: UInt64
    let createdAt: ContinuousClock.Instant
    var replayed: Bool
}
```

**Lifecycle:**

- SET when `Core.playContext` returns rc=0 in `play(track:contextKey:)` and
  `playAlbum(id:)`.
- CLEARED on the first `.playing` event, on any user transport command
  (pause/stop/next/prev/new play), on sign-out, and on account-epoch change.
  A new intent supersedes the old one (latest-intent-wins, same pattern as
  `MembershipMutation`).
- REPLAYED at most once: when `reconnect()` reaches `.connected` and an
  unconfirmed, non-replayed intent younger than 60s exists, wait 3s for a
  `.playing` confirmation; if none arrives, re-issue the *original*
  `Core.playContext(uri, startIndex:)` with `replayed = true`.
- On replay failure (rc != 0) or a second unconfirmed timeout: surface
  `playbackConnectionState = .unavailable(…)` and stop. Never loop, never
  refresh a token, never degrade to a URI window from this path.

**Explicit non-behaviors (guardrails):**

- No replay of windowed `playTracks` calls in Phase 1 — server-resolved
  contexts only. Ad-hoc windows (search/artist/queue pages) are small and
  the user can re-click; keeping replay context-only means the replay path
  can never upload URI lists.
- Generation fencing: replay runs under the *new* generation but is keyed by
  account epoch, because the intent is user-level (the context URI is
  server-resolved and session-independent).
- Intent expiry (60s) prevents a stale morning-after replay from a zombie
  session recovery (hazard #9 scenario).

**Touch points:**

- `NanyinApp/State/AppModel.swift`: `play(track:contextKey:)`,
  `playAlbum(id:)`, `handle(_:generation:)` (`.playing` / `.paused` /
  `.stopped` clear the intent), `reconnect(disconnectedGeneration:)`
  (post-`.connected` replay hook), sign-out path.
- No Rust changes required: `nanyin_play_context` is already idempotent from
  the server's perspective (same context + index).

### Phase 2 — Narrow `scheduleContextFallback` to its real purpose

Today (`AppModel.swift`, `scheduleContextFallback`): any 8s without audio
falls back to a 50-URI window. Change:

- If `playbackConnectionState != .ready` when the watchdog fires (i.e. we
  are inside a disconnect/reconnect window), do NOT fall back to windowed
  tracks. Keep the pending intent alive for the Phase 1 replay and keep
  `isBuffering` until the intent resolves or expires.
- The windowed fallback remains only for the case it was built for: a
  healthy connection where server-side context resolution genuinely stalls.

### Phase 3 (optional hardening, separate PR) — Foreground staleness re-init

AGENTS.md hazard #9 direction: on app foreground with session age above a
few hours, proactively `nanyin_init_player` before the user's first click,
so the first `activate()` never lands on an overnight-zombie session.
Bounded to once per foreground transition; skipped while audio is playing.

### Explicit non-goals

- No Spirc removal, no custom queue/context engine.
- No new Rust-side replay logic (Swift owns intent state; Rust stays a thin
  command bridge).
- No changes to the data-plane stall watchdog (already correct and local).
- No token-refresh behavior changes (`reconnect()` discipline stays as-is).

## 5. Verification

Offline (default, `./script/agent_check.sh` + unit tests):

- Deterministic intent-reducer tests in `Tests/` (same style as
  `StateReducerTests.swift`): supersede ordering, clear-on-playing,
  clear-on-user-command, single-replay flag, expiry, epoch fencing,
  sign-out wins over a late replay.
- Fallback-narrowing test: watchdog firing during `.reconnecting` state
  does not call the windowed path.

Live (requires explicit Boss authorization, per repo policy):

1. Normal play on healthy connection — intent sets and clears on `Playing`,
   no replay fires (log assertion).
2. Simulated dealer window: toggle network off, click play (rc=0, no
   `Playing`), restore network → observe exactly one replay and audible
   playback, no windowed fallback, no token refresh in logs.
3. Stop-loss discipline applies: first sign of spirc/dealer trouble beyond
   the scripted scenario → kill all instances, switch to idle probe.

## 6. Revisit criteria (when Spirc removal becomes worth it)

Reopen this decision only if ALL of these hold:

- Product drops Connect-device identity and phone transfer from scope.
- A throwaway account is available to shake out the custom control plane's
  traffic shape before it ever touches the primary account.
- upstream librespot #1741 status no longer matters to us (we would still
  need the session/audio-key/CDN layers either way — removal does not free
  us from the vendored checkout).
