#!/usr/bin/env bash
# Deterministic verification for coding agents and CI-like local checks.
# This command must never launch Nanyin, access Keychain, or contact Spotify.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_MANIFEST="$ROOT_DIR/rust/Cargo.toml"
LIBRESPOT_DIR="$ROOT_DIR/research-repos/librespot"
LIBRESPOT_PATCHES=(
    "$ROOT_DIR/patches/librespot-pr-1741.patch"
    "$ROOT_DIR/patches/librespot-auth-error-classification.patch"
)
XCODE_PROJECT_FILE="$ROOT_DIR/Nanyin.xcodeproj/project.pbxproj"

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
for patch in "${LIBRESPOT_PATCHES[@]}"; do
    git -C "$LIBRESPOT_DIR" apply --reverse --check --unidiff-zero "$patch" \
        || fail "required librespot patch is not applied exactly: ${patch##*/}"
done

command -v mise >/dev/null 2>&1 || fail "mise is required"
command -v xcrun >/dev/null 2>&1 || fail "Xcode command-line tools are required"

step "checking Xcode source membership"
while IFS= read -r source; do
    source_name="${source##*/}"
    rg -Fq "$source_name in Sources" "$XCODE_PROJECT_FILE" \
        || fail "$source is missing from Nanyin.xcodeproj; run xcodegen generate"
done < <(rg --files "$ROOT_DIR/NanyinApp" -g '*.swift')

step "running Swift state reducer tests"
state_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/nanyin-state-tests.XXXXXX")"
cleanup() {
    rm -r -- "$state_test_dir"
}
trap cleanup EXIT
xcrun swiftc \
    "$ROOT_DIR/NanyinApp/Core/CredentialRevision.swift" \
    "$ROOT_DIR/NanyinApp/State/LikeMutation.swift" \
    "$ROOT_DIR/Tests/StateReducerTests.swift" \
    -o "$state_test_dir/state-reducer-tests"
"$state_test_dir/state-reducer-tests"

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
