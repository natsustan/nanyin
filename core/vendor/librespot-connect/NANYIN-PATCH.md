# Nanyin's changes to librespot-connect

Copied from librespot `15e02e86c72d96dd39d548e3749f00abe39ffdde`
(`connect/`). The manifest inlines the workspace fields and points the
sibling crates at the same git rev; `core/Cargo.toml` swaps it in with
`[patch]`.

Code changes:

1. librespot-org/librespot#1765 (commit b44dc2c, "Preserve playback context
   and queue across disconnected sessions"), applied unchanged to `src/`:
   `Spirc::disconnected_playback`, `Spirc::restore_playback` and
   `PlaybackSnapshot`.
2. `PlaybackSnapshot::track_uri`, so the core can tell whether the track the
   kept player holds is the snapshot's current one.
3. `PlaybackSnapshot::playing_on`: a position that keeps advancing until
   the restore is applied, capped at the track's end. A new Spirc handles
   commands only after its dealer connects, a second or two after
   `restore_playback` is called; a fixed position took the song back by
   that much.

Why: on an unexpected disconnect the core keeps the `Player` playing what it
has already fetched, hands it to the next session with `Player::set_session`
and restores the snapshot there, as spotifast does.

When moving librespot to a new rev: re-copy `connect/` from that rev,
reapply #1765 (or drop it once merged) and changes 2 and 3.
