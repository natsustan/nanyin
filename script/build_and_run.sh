#!/usr/bin/env bash
# Builds Nanyin and launches it.
#
# usage: script/build_and_run.sh [run|--debug|--logs]
#   NANYIN_CONFIGURATION  Debug (default, "Nanyin Dev") or Release ("Nanyin")
#
# Only one Nanyin may run: two processes would share one Connect device id
# and hold two sessions for it. Every running copy of this variant is
# stopped before launching, after the build has succeeded.
set -euo pipefail

MODE="${1:-run}"
CONFIGURATION="${NANYIN_CONFIGURATION:-Debug}"
case "$CONFIGURATION" in
    Debug) APP_NAME="Nanyin Dev" ;;
    Release) APP_NAME="Nanyin" ;;
    *) echo "Unsupported NANYIN_CONFIGURATION: $CONFIGURATION" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/development_signing.sh"
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
LOG_FILE="$ROOT_DIR/build/nanyin.log"

[[ -d "$ROOT_DIR/Nanyin.xcodeproj" ]] || "$ROOT_DIR/script/generate_project.sh"

xcodebuild \
    -project "$ROOT_DIR/Nanyin.xcodeproj" \
    -scheme Nanyin \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -quiet \
    "${NANYIN_SIGNING_SETTINGS[@]}" \
    build

# Stop every instance of this variant, wherever it was built.
pkill -x "$APP_NAME" 2>/dev/null || true
for _ in {1..30}; do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.1
done
pkill -KILL -x "$APP_NAME" 2>/dev/null || true

case "$MODE" in
    run)
        # Run the binary directly so the core's stderr lands in the log.
        nohup "$APP_BINARY" >"$LOG_FILE" 2>&1 &
        echo "Launched $APP_NAME (log: $LOG_FILE)"
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        "$APP_BINARY" 2>&1 | tee "$LOG_FILE"
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs]" >&2
        exit 2
        ;;
esac
