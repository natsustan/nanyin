#!/bin/bash
# Build script for the nanyin Rust core (macOS arm64 only for now).
# Invoked by Xcode as a build phase (before Compile Sources) or manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$SCRIPT_DIR"
OUTPUT_DIR="$SCRIPT_DIR/../build/rust"

bash "$SCRIPT_DIR/../script/check_librespot.sh"

# Xcode passes CONFIGURATION (Debug/Release); default Release.
CONFIGURATION="${CONFIGURATION:-Release}"
if [ "$CONFIGURATION" = "Debug" ]; then
    CARGO_FLAGS=""
    BUILD_TYPE="debug"
else
    CARGO_FLAGS="--release"
    BUILD_TYPE="release"
fi

mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

cd "$RUST_DIR"

# Target triple and Apple Silicon flags (hardware AES/NEON/SHA — the `aes`
# crate needs the cfg for ARMv8 crypto extensions) live in the repo-root
# .cargo/config.toml so every cargo invocation shares one target dir.
echo "Building nanyin-core ($BUILD_TYPE) for aarch64-apple-darwin..."
bash "$SCRIPT_DIR/../script/cargo.sh" build --locked $CARGO_FLAGS
cp "$RUST_DIR/target/aarch64-apple-darwin/$BUILD_TYPE/libnanyin_core.a" "$OUTPUT_DIR/lib/"

# Header + modulemap are checked in; copy them so Swift compiles against a
# stable path even on the very first build.
cp "$RUST_DIR/include/nanyin_core.h" "$OUTPUT_DIR/include/"
cp "$RUST_DIR/include/module.modulemap" "$OUTPUT_DIR/include/"

echo "nanyin-core build complete: $OUTPUT_DIR/lib/libnanyin_core.a"
