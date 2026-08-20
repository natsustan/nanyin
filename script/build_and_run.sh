#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

APP_NAME="Nanyin"
SCHEME="Nanyin"
CONFIGURATION="Debug"
DESTINATION="platform=macOS,arch=arm64"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Nanyin.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/build/XcodeDerivedData"
BUILT_APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
# Match instances launched from any location (DerivedData, dist/, Finder).
PROCESS_PATTERN="Nanyin.app/Contents/MacOS/Nanyin"
LOG_FILE="$ROOT_DIR/build/nanyin-launch.log"

# mise-managed toolchains (xcodegen, cargo) + librespot log level (AGENTS.md).
export PATH="$HOME/.local/share/mise/shims:$HOME/.cargo/bin:$PATH"
export RUST_LOG="${RUST_LOG:-librespot_connect=debug,librespot_core::dealer=warn}"

usage() {
  echo "usage: NANYIN_ALLOW_LIVE_SPOTIFY=1 $0 [run|--debug|--logs|--live-smoke]" >&2
}

validate_mode() {
  case "$MODE" in
    run|--debug|debug|--logs|logs|--live-smoke|live-smoke)
      ;;
    --verify|verify)
      echo "ERROR: --verify was renamed to --live-smoke because it launches Nanyin and contacts Spotify." >&2
      usage
      exit 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

require_live_spotify_opt_in() {
  if [[ "${NANYIN_ALLOW_LIVE_SPOTIFY:-}" != "1" ]]; then
    echo "ERROR: this command launches Nanyin and may use real Spotify credentials." >&2
    echo "       Set NANYIN_ALLOW_LIVE_SPOTIFY=1 only after explicit user authorization." >&2
    echo "       For agent-safe verification, run ./script/agent_check.sh instead." >&2
    exit 64
  fi
}

terminate_running_app() {
  # AGENTS.md hazard #6: exactly one running instance, always — stop any
  # existing instance before launching a new one.
  local pids
  pids="$(pgrep -f "$PROCESS_PATTERN" 2>/dev/null || true)"
  if [[ -z "$pids" ]]; then
    return
  fi

  while IFS= read -r pid; do
    kill "$pid" 2>/dev/null || true
  done <<< "$pids"

  for _ in {1..20}; do
    if ! pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done

  while IFS= read -r pid; do
    kill -KILL "$pid" 2>/dev/null || true
  done <<< "$(pgrep -f "$PROCESS_PATTERN" 2>/dev/null || true)"
}

generate_project_if_needed() {
  if [[ ! -d "$PROJECT_PATH" ]]; then
    command -v xcodegen >/dev/null 2>&1 || {
      echo "xcodegen not found — install via mise: mise use -g xcodegen" >&2
      exit 1
    }
    (cd "$ROOT_DIR" && xcodegen generate)
  fi
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
}

package_app() {
  rm -rf "$APP_BUNDLE"
  mkdir -p "$DIST_DIR"
  ditto "$BUILT_APP_BUNDLE" "$APP_BUNDLE"
}

wait_for_app() {
  for _ in {1..50}; do
    if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

print_recent_launch_logs() {
  tail -n 80 "$LOG_FILE" >&2 2>/dev/null || true
}

run_app() {
  # Launch the inner binary directly so Swift dlog + Rust eprintln stderr is
  # captured to LOG_FILE (AGENTS.md: diagnostics stream unbuffered to stderr;
  # `open` would lose them).
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  nohup "$APP_BINARY" >> "$LOG_FILE" 2>&1 < /dev/null &

  if wait_for_app; then
    local first_pid
    first_pid="$(pgrep -f "$PROCESS_PATTERN" 2>/dev/null | sed -n '1p')"
    echo "Launched $APP_NAME with PID $first_pid (stderr: $LOG_FILE)"
    return 0
  fi

  echo "Failed to launch $APP_NAME from $APP_BUNDLE" >&2
  print_recent_launch_logs
  return 1
}

live_smoke_app() {
  if ! run_app >/dev/null; then
    return 1
  fi

  sleep 3
  if pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1; then
    echo "live-smoke: OK — $APP_NAME alive 3s after launch"
    return 0
  fi

  echo "live-smoke: FAILED — $APP_NAME exited within 3s of launch" >&2
  print_recent_launch_logs
  return 1
}

main() {
  if [[ $# -gt 1 ]]; then
    usage
    exit 2
  fi

  validate_mode
  require_live_spotify_opt_in
  terminate_running_app
  generate_project_if_needed
  build_app
  package_app

  case "$MODE" in
    run)
      run_app
      ;;
    --debug|debug)
      lldb -- "$APP_BINARY"
      ;;
    --logs|logs)
      run_app
      tail -n 50 -F "$LOG_FILE"
      ;;
    --live-smoke|live-smoke)
      live_smoke_app
      ;;
  esac
}

main "$@"
