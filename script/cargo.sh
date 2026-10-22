#!/usr/bin/env bash
# Use the committed toolchain even when mise/Xcode exports a floating override.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
channel="$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
[[ -n "$channel" ]] || { echo 'ERROR: missing pinned Rust toolchain' >&2; exit 1; }
if command -v rustup >/dev/null 2>&1; then
    rustup_bin="$(command -v rustup)"
else
    rustup_bin="$HOME/.cargo/bin/rustup"
fi
# Installation is an explicit setup step, never an implicit build-time update.
exec "$rustup_bin" run "$channel" cargo "$@"
