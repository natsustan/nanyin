#!/usr/bin/env bash
# Offline fixture; never changes the real vendored checkout.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/nanyin-vendor-tests.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/script" "$fixture/rust" "$fixture/patches" "$fixture/research-repos"
cp "$ROOT_DIR/script/"{check_librespot,librespot_config,vendor_librespot}.sh "$fixture/script/"
cp "$ROOT_DIR/rust/Cargo.toml" "$fixture/rust/"
cp "$ROOT_DIR"/patches/librespot-*.patch "$fixture/patches/"
git clone --quiet --shared --no-hardlinks "$ROOT_DIR/research-repos/librespot" "$fixture/research-repos/librespot"
if bash "$fixture/script/check_librespot.sh" > "$fixture/check.log" 2>&1; then
    echo 'ERROR: unpatched checkout passed the build guard' >&2
    exit 1
fi
# Exercise the missing-checkout bootstrap too, using only the local source.
rm -rf "$fixture/research-repos/librespot"
bash "$fixture/script/vendor_librespot.sh" "$ROOT_DIR/research-repos/librespot" > "$fixture/bootstrap.log" 2>&1
# Idempotent bootstrap must preserve exactly the same diff.
before="$(git -C "$fixture/research-repos/librespot" diff | shasum -a 256)"
bash "$fixture/script/vendor_librespot.sh"
[[ "$before" == "$(git -C "$fixture/research-repos/librespot" diff | shasum -a 256)" ]]
git -C "$fixture/research-repos/librespot" apply --reverse --unidiff-zero "$fixture/patches/librespot-auth-error-classification.patch"
if bash "$fixture/script/check_librespot.sh" > "$fixture/check.log" 2>&1; then
    echo 'ERROR: missing authentication patch passed the build guard' >&2
    exit 1
fi
printf 'Librespot build guard tests passed\n'
