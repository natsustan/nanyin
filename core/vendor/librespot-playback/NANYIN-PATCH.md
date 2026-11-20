# Nanyin's change to librespot-playback

Copied from librespot `15e02e86c72d96dd39d548e3749f00abe39ffdde`
(`playback/`). The manifest inlines the workspace fields and points the
sibling crates at the same git rev; `core/Cargo.toml` swaps it in with
`[patch]`.

The only code change is in `src/player.rs`, `PlayerTrackLoader::load_track`:
when the audio key cannot be fetched, the load fails (`return None`)
instead of continuing without decryption.

Why: the key fails mostly because the session has just dropped. Upstream
then hands the still-encrypted bytes to the decoder; the MP3 demuxer does
not bail out but skips "junk" through the whole file, which held the player
thread for ~46 s in a field log (2026-11-20), and with it Spirc's shutdown
and the app's reconnect.

When moving librespot to a new rev: re-copy `playback/` from that rev,
reapply both edits, and drop this crate once upstream fails the load itself.
