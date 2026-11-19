#!/usr/bin/env bash
# Builds the Rust playback core as a static library. Run by Xcode before
# compiling Swift; Debug uses Cargo's dev profile, Release the release one.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/core"
# Xcode runs scripts without the login shell's PATH.
export PATH="$HOME/.local/share/mise/shims:/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"
# Xcode exports SDK settings that confuse cc-rs when building C dependencies.
unset SDKROOT MACOSX_DEPLOYMENT_TARGET_SETTING_NAME
export MACOSX_DEPLOYMENT_TARGET=26.0
if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
    exec mise exec -- cargo build --release
else
    exec mise exec -- cargo build
fi
