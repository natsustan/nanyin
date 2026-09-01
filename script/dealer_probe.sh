#!/usr/bin/env bash
# Dealer stability probe (idle, no audio). Collects evidence about dealer
# stability without touching real playback.
#
# Credential access and refresh-token rotation run inside the installed,
# signed Nanyin executable. This shell script must never read or write the
# application's Keychain items through /usr/bin/security.
#
# Exit codes:
#   0  survived 300s (this idle dealer session was stable)
#   1  probe panicked / died mid-run
#   2  token is missing or the refresh request was rejected
#   3  SESSION DIED after connecting
#   5  Keychain read or write failed
#   6  Nanyin is already running
#  64  live Spotify opt-in missing
#
# Usage: NANYIN_ALLOW_LIVE_SPOTIFY=1 script/dealer_probe.sh [device_id]

set -euo pipefail

DEVICE_ID="${1:-nanyin_probe_check}"
APP_BUNDLE="${NANYIN_APP_PATH:-/Applications/Nanyin.app}"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Nanyin"
SIGNING_REQUIREMENT='anchor apple generic and identifier "com.nanyin.app" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "V6GTS74AND"'

require_live_spotify_opt_in() {
    if [ "${NANYIN_ALLOW_LIVE_SPOTIFY:-}" != "1" ]; then
        echo "ERROR: dealer_probe uses real Spotify credentials and opens a real dealer session." >&2
        echo "       Set NANYIN_ALLOW_LIVE_SPOTIFY=1 only after explicit user authorization." >&2
        exit 64
    fi
}

ensure_nanyin_not_running() {
    if pgrep -f '[N]anyin.app' >/dev/null; then
        echo "ERROR: Nanyin is already running; stop it before starting the dealer probe." >&2
        exit 6
    fi
}

require_live_spotify_opt_in
ensure_nanyin_not_running

if [ ! -x "$APP_EXECUTABLE" ]; then
    echo "ERROR: signed Nanyin executable not found at $APP_EXECUTABLE" >&2
    echo "       Install Nanyin.app or set NANYIN_APP_PATH to its bundle path." >&2
    exit 1
fi
if ! codesign --verify --strict -R="$SIGNING_REQUIREMENT" "$APP_BUNDLE"; then
    echo "ERROR: dealer_probe requires Nanyin's Developer ID signature (Team V6GTS74AND)." >&2
    exit 1
fi
if ! grep -Fqx 'Usage: Nanyin --dealer-probe [device_id]' < <(strings "$APP_EXECUTABLE"); then
    echo "ERROR: the installed Nanyin.app does not support the headless dealer probe." >&2
    echo "       Install a release containing the --dealer-probe command first." >&2
    exit 1
fi

ensure_nanyin_not_running
echo "[probe] using $APP_EXECUTABLE"
exec "$APP_EXECUTABLE" --dealer-probe "$DEVICE_ID"
