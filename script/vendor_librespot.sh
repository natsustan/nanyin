#!/usr/bin/env bash
# Prepare a missing or partially patched checkout without resetting local work.
# Optional source path supports an entirely offline fixture clone.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/librespot_config.sh"
checkout="$ROOT_DIR/research-repos/librespot"
if [[ ! -e "$checkout" ]]; then
    mkdir -p "$ROOT_DIR/research-repos"
    git clone --no-checkout "${1:-https://github.com/librespot-org/librespot.git}" "$checkout"
    git -C "$checkout" checkout --detach "$LIBRESPOT_SHA"
fi
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$LIBRESPOT_SHA" ]] || {
    echo 'ERROR: existing librespot is at another revision; leaving it untouched' >&2
    exit 1
}
# Validate all missing patches first, so an incompatible checkout is not left
# half changed. These patches have independent edit regions.
missing=()
for patch in "${LIBRESPOT_PATCHES[@]}"; do
    if git -C "$checkout" apply --reverse --check --unidiff-zero "$patch" 2>/dev/null; then
        continue
    fi
    git -C "$checkout" apply --check --unidiff-zero "$patch"
    missing+=("$patch")
done
for patch in "${missing[@]+${missing[@]}}"; do
    git -C "$checkout" apply --unidiff-zero "$patch"
done
bash "$ROOT_DIR/script/check_librespot.sh"
