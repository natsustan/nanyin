#!/bin/bash
# Build script for the nanyin Rust core (macOS arm64 only for now).
# Invoked by Xcode as a build phase (before Compile Sources) or manually.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$SCRIPT_DIR"
OUTPUT_DIR="$SCRIPT_DIR/../build/rust"

# Find cargo: mise shim first, then rustup, then Homebrew.
if command -v cargo >/dev/null 2>&1; then
    :
elif [ -f "$HOME/.cargo/bin/cargo" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
elif [ -f "/opt/homebrew/bin/cargo" ]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

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

# Enable hardware AES/NEON/SHA on Apple Silicon (same flags as NullSpot —
# the `aes` crate needs the cfg to use ARMv8 crypto extensions).
export RUSTFLAGS="${RUSTFLAGS:-} -C target-cpu=apple-m1 --cfg aes_armv8"

echo "Building nanyin-core ($BUILD_TYPE) for aarch64-apple-darwin..."
cargo build $CARGO_FLAGS --target aarch64-apple-darwin
cp "$RUST_DIR/target/aarch64-apple-darwin/$BUILD_TYPE/libnanyin_core.a" "$OUTPUT_DIR/lib/"

# Header + modulemap are checked in; copy them so Swift compiles against a
# stable path even on the very first build.
cp "$RUST_DIR/include/nanyin_core.h" "$OUTPUT_DIR/include/"
cp "$RUST_DIR/include/module.modulemap" "$OUTPUT_DIR/include/"

echo "nanyin-core build complete: $OUTPUT_DIR/lib/libnanyin_core.a"
