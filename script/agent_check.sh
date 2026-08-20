#!/usr/bin/env bash
# Deterministic verification for coding agents and CI-like local checks.
# This command must never launch Nanyin, access Keychain, or contact Spotify.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_MANIFEST="$ROOT_DIR/rust/Cargo.toml"
LIBRESPOT_DIR="$ROOT_DIR/research-repos/librespot"
LIBRESPOT_PATCH="$ROOT_DIR/patches/librespot-pr-1741.patch"

export PATH="$HOME/.local/share/mise/shims:$HOME/.cargo/bin:$PATH"
export CARGO_NET_OFFLINE=true

step() {
    printf '[agent-check] %s\n' "$1"
}

fail() {
    printf '[agent-check] ERROR: %s\n' "$1" >&2
    exit 1
}

cd "$ROOT_DIR"

step "checking the working-tree diff"
git diff HEAD --check

step "checking vendored librespot wiring"
[[ -d "$LIBRESPOT_DIR/.git" ]] || fail "research-repos/librespot checkout is missing"
for dependency in core connect playback metadata protocol; do
    rg -q \
        "librespot-${dependency} = \\{ path = \\\"\.\./research-repos/librespot/${dependency}\\\" \\}" \
        "$RUST_MANIFEST" \
        || fail "librespot-${dependency} is not pinned to the vendored path"
done
git -C "$LIBRESPOT_DIR" diff --check
git -C "$LIBRESPOT_DIR" apply --reverse --check "$LIBRESPOT_PATCH" \
    || fail "required librespot PR #1741 patch is not applied exactly"

command -v mise >/dev/null 2>&1 || fail "mise is required"

step "running Rust unit tests offline"
mise exec rust@stable -- cargo test \
    --offline \
    --manifest-path "$RUST_MANIFEST" \
    --lib

step "building the macOS app without launching it"
xcodebuild \
    -quiet \
    -project "$ROOT_DIR/Nanyin.xcodeproj" \
    -scheme Nanyin \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    CODE_SIGNING_ALLOWED=NO \
    build

step "OK"
