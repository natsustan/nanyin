# Nanyin — agent guide

Native macOS Spotify client in the style of the 2010 Spotify-for-Mac (Aqua
era). Swift/SwiftUI app, librespot (Rust) for playback.

## Layout

| Path | What |
|---|---|
| `core/` | Rust staticlib `nanyin_core`: librespot session, player, Spotify Connect device. C ABI in `core/include/nanyin_core.h`; commands and events are JSON. |
| `Packages/NanyinKit/` | Swift package, testable without the app: OAuth (PKCE + loopback), Keychain, Web API client, reconnect policy. |
| `Nanyin/Playback/` | Swift side of the core ABI (`PlaybackEngine`, message types). |
| `Nanyin/Model/` | `@Observable` models: `Account`, `PlaybackSession`, `Player`, `Library`, `Navigator`, `TrackList`, wired in `AppModel`. |
| `Nanyin/UI/` | `Chrome/` (Aqua window parts), `Shell/` (window, toolbar, sidebar, player bar), `Tracks/` (the NSTableView track table), `Pages/`. |
| `research-repos/` | Git-ignored reference checkouts (spotifast, librespot). |

## Toolchain and commands

Everything comes from mise (`mise install`): rust, xcodegen, xcbeautify.

```sh
script/generate_project.sh   # after adding/removing files or editing project.yml
script/build.sh              # build only (Debug = "Nanyin Dev", com.cosmoss.nanyin.dev)
script/build_and_run.sh      # build, stop every running copy, launch; log in build/nanyin.log
script/make_release.sh       # Release (Developer ID) as dist/Nanyin-<version>.dmg; --notarize also notarizes and writes Sparkle's appcast
swift test --package-path Packages/NanyinKit
(cd core && mise exec -- cargo test && mise exec -- cargo clippy --all-targets)
```

The core logs to stderr and to `~/Library/Logs/<app name>/core.log`
(5 MB, then rotated to `core.log.1`); panics land there with a backtrace.
`RUST_LOG` overrides the default filter.

Never edit `Nanyin.xcodeproj` by hand; it is generated and git-ignored.

## Releases

Bump `MARKETING_VERSION` in `project.yml` (the build number follows it;
Sparkle compares it), run `script/make_release.sh --notarize`, then upload
the DMG, `appcast.xml`, the update zip and any `.delta` it lists to the
GitHub release `v<version>`. Publishing is the user's call. The app checks
`releases/latest/download/appcast.xml`; Debug builds never check. Notarizing
uses the notarytool profile `notarization`; Sparkle's EdDSA key lives in the
login Keychain under account `nanyin` (public half in `Info.plist`). Keep
`dist/updates/` between releases: deltas are made from the archives there.

## librespot fork

librespot comes from [natsustan/librespot](https://github.com/natsustan/librespot),
branch `nanyin`: upstream `dev` plus one commit per change, listed in
`core/Cargo.toml`. Change librespot there, never by copying its code here:
commit on `nanyin` (formatted and clippy-clean), push, then move every
librespot crate in `core/Cargo.toml` to the new rev together. The fork's
changes are not being offered upstream for now. To follow upstream, rebase
`nanyin` on `upstream/dev` and drop commits upstream has merged.
`research-repos/librespot` stays a read-only reference.

## Spotify account safety (do not regress)

Spotify watches for abusive traffic. These rules keep a normal listener's
account safe; most come from spotifast's experience (`research-repos/spotifast/docs/_reference/`).

1. **Two independent grants.** Web API: the listener's own Client ID
   (port 8989). Shared IDs no longer admit sign-ins and the desktop client ID
   gets 429 on the Web API. Playback: keymaster client, `streaming` scope
   only (port 8898), used once to obtain librespot's reusable credential.
   Never use one grant's token for the other's job.
2. **No background refresh storms.** Web API tokens renew only near expiry
   or after a 401 for that exact token, coalesced (`WebAPIAuth`). Replacement
   refresh tokens are saved before use. Playback never refreshes: it reuses
   the stored librespot credential.
3. **Only an explicit login refusal discards a credential**
   (`FailureReason::AuthRejected`). Timeouts and other errors back off
   (`ReconnectPolicy`: 5/15/60/120/300/600 s; ≤ 6 session drops per 10 min).
   A dropped session's song plays on from the kept player; the next session
   takes it over and restores its queue once (librespot#1765, in the fork).
   Nothing new ever starts on its own.
4. **The browser opens only from a user's click.** Never from an error path.
5. **One Connect device id per install**, never derived per launch.
6. **One running instance.** `build_and_run.sh` stops every copy first.
   Two processes would hold two sessions for one device.
7. **Respect 429.** A `Retry-After` stops all Web API traffic until it
   passes, persists across launches, and is never replayed automatically.
8. **Large contexts by URI.** Play playlists/albums/Liked Songs with a context
   URI (`spotify:user:<id>:collection`), never by uploading track lists.
9. **No live automation without the user's say-so.** Launching the app with a
   signed-in account makes real Spotify traffic. UI automation against a real
   account needs explicit permission in the current task; stop at the first
   sign of session trouble.
10. **Page sizes ≤ 50, search ≤ 10 per type** (Development Mode limits).
11. **Playlists the listener does not own are read through the session**
    (`core/src/reads.rs`): Development Mode apps get 403 for them. One
    playlist fetch, then one batched metadata request per 50 rows; the play
    queue resolves through the same cached lookup. An artist's top tracks
    (also 403 on the Web API) come the same way: one artist fetch, one
    batched lookup of the first 10. Swift asks with
    `PlaybackEngine.request` (`nanyin_request`, answered by a `reply` event).

## Conventions

- Commit often, one topic per commit, conventional English messages.
- UI: Lucida Grande (`AquaFont`), colours only from `Theme`, light metal
  chrome around a charcoal library, `Theme.green` used sparingly.
- Playback position is an anchor (`Player.Position`); only views showing
  the time tick (TimelineView). Never publish position app-wide.
- Interface is optimistic: show the result of a control at once, let core
  events confirm it.
- Callbacks that other threads call (the core's C callback, MediaPlayer
  handlers) must be `nonisolated`: a closure written inside a `@MainActor`
  type inherits that isolation, and Release builds trap on the check.
