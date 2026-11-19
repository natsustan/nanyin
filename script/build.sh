#!/usr/bin/env bash
# Builds Nanyin without launching it. NANYIN_CONFIGURATION picks Debug/Release.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/development_signing.sh"
[[ -d "$ROOT_DIR/Nanyin.xcodeproj" ]] || "$ROOT_DIR/script/generate_project.sh"
xcodebuild \
    -project "$ROOT_DIR/Nanyin.xcodeproj" \
    -scheme Nanyin \
    -configuration "${NANYIN_CONFIGURATION:-Debug}" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$ROOT_DIR/build/DerivedData" \
    -quiet \
    "${NANYIN_SIGNING_SETTINGS[@]}" \
    build 2> >(grep -v "multiple matching destinations" >&2)
