#!/usr/bin/env bash
# Shared by every Rust build, agent verification, and release packaging.
# Read-only, offline; never launches an app or reads credentials.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_MANIFEST="$ROOT_DIR/rust/Cargo.toml"
fail() { printf '[librespot-check] ERROR: %s\n' "$1" >&2; exit 1; }
LIBRESPOT_DIR="$ROOT_DIR/research-repos/librespot"
source "$ROOT_DIR/script/librespot_config.sh"
[[ -d "$LIBRESPOT_DIR/.git" ]] || fail "research-repos/librespot checkout is missing"
[[ "$(git -C "$LIBRESPOT_DIR" rev-parse HEAD)" == "$LIBRESPOT_SHA" ]] \
    || fail "librespot is not at the pinned revision"
for dependency in audio core connect playback metadata protocol; do
    rg -q \
        "librespot-${dependency} = \\{ path = \\\"\.\./research-repos/librespot/${dependency}\\\" \\}" \
        "$RUST_MANIFEST" \
        || fail "librespot-${dependency} is not pinned to the vendored path"
done
git -C "$LIBRESPOT_DIR" diff --check
for patch in "${LIBRESPOT_PATCHES[@]}"; do
    git -C "$LIBRESPOT_DIR" apply --reverse --check --unidiff-zero "$patch" \
        || fail "required librespot patch is not applied exactly: ${patch##*/}"
done
