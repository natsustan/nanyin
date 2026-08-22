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
    "$ROOT_DIR/patches/librespot-audio-progress.patch"
)
source "$ROOT_DIR/script/vendor_choutiui.sh"
CHOUTIUI_DIR="$ROOT_DIR/research-repos/ChouTiUI"
CHOUTI_DIR="$ROOT_DIR/research-repos/ChouTi"
COMPOSEUI_DIR="$ROOT_DIR/research-repos/ComposeUI"
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

step "checking vendored ChouTiUI wiring"
[[ -d "$CHOUTIUI_DIR/.git" ]] || fail "research-repos/ChouTiUI checkout is missing; run script/vendor_choutiui.sh"
[[ -d "$CHOUTI_DIR/.git" ]] || fail "research-repos/ChouTi checkout is missing; run script/vendor_choutiui.sh"
[[ -d "$COMPOSEUI_DIR/.git" ]] || fail "research-repos/ComposeUI checkout is missing; run script/vendor_choutiui.sh"
[[ "$(git -C "$CHOUTIUI_DIR" rev-parse HEAD^)" == "$CHOUTIUI_SHA" ]] \
    || fail "ChouTiUI is not based on the pinned revision"
[[ "$(git -C "$CHOUTI_DIR" rev-parse HEAD)" == "$CHOUTI_SHA" ]] \
    || fail "ChouTi is not at the pinned revision"
[[ "$(git -C "$COMPOSEUI_DIR" rev-parse HEAD)" == "$COMPOSEUI_SHA" ]] \
    || fail "ComposeUI is not at the pinned revision"
for checkout in "$CHOUTIUI_DIR" "$CHOUTI_DIR" "$COMPOSEUI_DIR"; do
    [[ -z "$(git -C "$checkout" status --porcelain)" ]] \
        || fail "${checkout##*/} vendored checkout has local changes"
done
git -C "$CHOUTIUI_DIR" apply --reverse --check "$CHOUTIUI_PATCH" \
    || fail "required ChouTiUI path-dependency patch is not applied exactly"
rg -q '\.package\(path: "\.\./ChouTi"\)' "$CHOUTIUI_DIR/Package.swift" \
    || fail "ChouTiUI is not wired to the vendored ChouTi checkout"
rg -q '\.package\(path: "\.\./ComposeUI"\)' "$CHOUTIUI_DIR/Package.swift" \
    || fail "ChouTiUI is not wired to the vendored ComposeUI checkout"
rg -q 'path: research-repos/ChouTiUI' "$ROOT_DIR/project.yml" \
    || fail "project.yml is not wired to the vendored ChouTiUI package"
while IFS= read -r source; do
    [[ "$source" == "$ROOT_DIR/NanyinApp/Classic/Chrome/"* ]] \
        || fail "ChouTiUI import escaped Classic/Chrome: ${source#"$ROOT_DIR/"}"
    ! rg -q '^import SwiftUI$' "$source" \
        || fail "file imports both ChouTiUI and SwiftUI: ${source#"$ROOT_DIR/"}"
done < <(rg -l '^import ChouTiUI$' "$ROOT_DIR/NanyinApp" -g '*.swift')

step "checking offline Classic Chrome preview harness"
CHROME_PREVIEW="$ROOT_DIR/NanyinApp/Classic/Bridge/ClassicChromePreviewHarness.swift"
CHROME_STYLE="$ROOT_DIR/NanyinApp/Classic/Bridge/ChromeStyle.swift"
[[ -f "$CHROME_PREVIEW" ]] || fail "Classic Chrome preview harness is missing"
[[ -f "$CHROME_STYLE" ]] || fail "Classic Chrome style contract is missing"
! rg -q '^import (SwiftUI|ChouTiUI)$' "$CHROME_STYLE" \
    || fail "Classic Chrome style contract depends on a UI framework"
rg -q 'ClassicChromePreviewHarness' "$CHROME_PREVIEW" \
    || fail "Classic Chrome preview harness declaration is missing"
for state in Default Hovered Pressed Disabled; do
    rg -q "$state" "$CHROME_PREVIEW" \
        || fail "Classic Chrome preview harness is missing a required state"
done
rg -q 'List' "$CHROME_PREVIEW" \
    || fail "Classic Chrome preview harness does not exercise List independence"
rg -q 'fixedSize\(\)' "$ROOT_DIR/NanyinApp/Classic/Bridge/ChromeButton.swift" \
    || fail "Classic Chrome button preview does not exercise intrinsic sizing"
! rg -q 'ClassicChromeButtonConfiguration' "$ROOT_DIR/NanyinApp/Classic" \
    || fail "Classic Chrome bridge still exposes the old implementation configuration"

step "checking shell and playback ownership seams"
for source in \
    "$ROOT_DIR/NanyinApp/Views/AppContentView.swift" \
    "$ROOT_DIR/NanyinApp/Views/NanyinDarkShell.swift" \
    "$ROOT_DIR/NanyinApp/Views/Classic2010Shell.swift" \
    "$ROOT_DIR/NanyinApp/Views/ClassicToolbarView.swift" \
    "$ROOT_DIR/NanyinApp/Views/ClassicShellGeometryFixture.swift"; do
    [[ -f "$source" ]] || fail "required shell source is missing: ${source##*/}"
done
rg -q 'AppContentView\(\)' "$ROOT_DIR/NanyinApp/Views/NanyinDarkShell.swift" \
    || fail "shared AppContentView is not owned by the shell scaffold"
rg -q 'app\.searchQuery' "$ROOT_DIR/NanyinApp/Views/SearchView.swift" \
    || fail "SearchView is not bound to the shared search query"
rg -q 'ChromeSliderTrack' "$ROOT_DIR/NanyinApp/Views/PlayerBar.swift" \
    || fail "Classic playback deck is missing the chrome slider bridge"
[[ "$(rg -c 'task\(id: app\.nowPlaying\?\.uri\)' "$ROOT_DIR/NanyinApp/Views/PlayerBar.swift")" == "1" ]] \
    || fail "PlayerBar must retain exactly one local playback-position ticker"
for size in '900, height: 600' '1280, height: 800' '1600, height: 900'; do
    rg -q "$size" "$ROOT_DIR/NanyinApp/Views/ClassicShellGeometryFixture.swift" \
        || fail "Classic shell geometry fixture is missing a required canvas size"
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
    "$ROOT_DIR/NanyinApp/Core/DebugLog.swift" \
    "$ROOT_DIR/NanyinApp/Core/SpotifyClient.swift" \
    "$ROOT_DIR/NanyinApp/Core/CredentialRevision.swift" \
    "$ROOT_DIR/NanyinApp/Audio/PlaybackStallDetector.swift" \
    "$ROOT_DIR/NanyinApp/State/MembershipMutation.swift" \
    "$ROOT_DIR/NanyinApp/State/PendingPlayIntent.swift" \
    "$ROOT_DIR/NanyinApp/State/PlaybackReconnectPolicy.swift" \
    "$ROOT_DIR/NanyinApp/State/LocalPlaybackStore.swift" \
    "$ROOT_DIR/NanyinApp/State/SavedAlbumCache.swift" \
    "$ROOT_DIR/NanyinApp/State/PlaylistLibraryMerge.swift" \
    "$ROOT_DIR/NanyinApp/State/HomeFeed.swift" \
    "$ROOT_DIR/Tests/StateReducerTests.swift" \
    -o "$state_test_dir/state-reducer-tests"
"$state_test_dir/state-reducer-tests"

step "running theme preference tests"
xcrun swiftc \
    "$ROOT_DIR/NanyinApp/Classic/Bridge/ChromeStyle.swift" \
    "$ROOT_DIR/NanyinApp/Views/Theme.swift" \
    "$ROOT_DIR/Tests/ThemePreferenceTests.swift" \
    -framework AppKit \
    -framework SwiftUI \
    -o "$state_test_dir/theme-preference-tests"
"$state_test_dir/theme-preference-tests"

step "running artwork cache tests"
xcrun swiftc \
    "$ROOT_DIR/NanyinApp/Core/ArtworkCache.swift" \
    "$ROOT_DIR/Tests/ArtworkCacheTests.swift" \
    -framework AppKit \
    -framework ImageIO \
    -o "$state_test_dir/artwork-cache-tests"
"$state_test_dir/artwork-cache-tests"

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
