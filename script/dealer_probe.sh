#!/usr/bin/env bash
# Dealer stability probe (idle, no audio). Collects evidence about dealer
# stability without touching real playback.
#
# Handles refresh-token rotation safely. The keymaster flow has been observed
# returning replacement refresh tokens and invalidating the previous token.
# A probe on 2026-08-18 discarded such a replacement and left Keychain with a
# stale credential. This script requires any returned replacement to be saved
# before starting the probe.
#
# Exit codes:
#   0  survived 300s (this idle dealer session was stable)
#   1  probe panicked / died mid-run
#   2  token is missing or the refresh request was rejected
#   3  SESSION DIED after connecting
#   5  Keychain read or write failed
#   6  Nanyin is already running
#
# Usage: script/dealer_probe.sh [device_id]

set -euo pipefail

SERVICE="com.nanyin.app.spotify"
CLIENT_ID="65b708073fc0480ea92a077233ca87bd" # keymaster (playback flow)
DEVICE_ID="${1:-nanyin_probe_check}"
KEYCHAIN_ITEM_NOT_FOUND=44

ensure_nanyin_not_running() {
    if pgrep -f '[N]anyin.app' >/dev/null; then
        echo "ERROR: Nanyin is already running; stop it before starting the dealer probe." >&2
        exit 6
    fi
}

ensure_nanyin_not_running

cd "$(dirname "$0")/../rust"
BIN=target/release/examples/dealer_test
echo "[probe] checking/building dealer_test…"
cargo build --release --example dealer_test

keychain_get() { security find-generic-password -s "$SERVICE" -a "$1" -w 2>/dev/null; }
keychain_set() { security add-generic-password -s "$SERVICE" -a "$1" -w "$2" -U; }

if RT=$(keychain_get playback_refresh_token); then
    :
else
    READ_STATUS=$?
    RT=""
    if [ "$READ_STATUS" -ne "$KEYCHAIN_ITEM_NOT_FOUND" ]; then
        echo "ERROR: could not read playback_refresh_token from Keychain (security exit=$READ_STATUS)." >&2
        exit 5
    fi
fi
if [ -z "$RT" ]; then
    # App migration: try the original single-flow keymaster token used by the
    # SpotifyAuth.storedRefreshToken legacy path.
    if RT=$(keychain_get refresh_token); then
        :
    else
        READ_STATUS=$?
        RT=""
        if [ "$READ_STATUS" -ne "$KEYCHAIN_ITEM_NOT_FOUND" ]; then
            echo "ERROR: could not read legacy refresh_token from Keychain (security exit=$READ_STATUS)." >&2
            exit 5
        fi
    fi
fi
if [ -z "$RT" ]; then
    echo "ERROR: no keymaster refresh token in Keychain (service=$SERVICE)." >&2
    echo "       Re-auth once via the app to mint a fresh one." >&2
    exit 2
fi

RESP=$(curl -s -X POST "https://accounts.spotify.com/api/token" \
    -d "grant_type=refresh_token" \
    -d "refresh_token=$RT" \
    -d "client_id=$CLIENT_ID")

TOKEN=$(printf '%s' "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || true)
if [ -z "$TOKEN" ]; then
    echo "ERROR: token refresh failed: $RESP" >&2
    echo "       invalid_grant means the credential is expired, revoked, or otherwise invalid." >&2
    exit 2
fi

NEW_RT=$(printf '%s' "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token') or '')" 2>/dev/null || true)
if [ -n "$NEW_RT" ]; then
    if ! keychain_set playback_refresh_token "$NEW_RT"; then
        echo "ERROR: refreshed token was returned but could not be saved to Keychain." >&2
        echo "       The probe was not started because the stored credential may now be stale." >&2
        exit 5
    fi
    echo "[probe] keymaster refresh token rotated -> saved to keychain (playback_refresh_token)"
else
    echo "[probe] no replacement refresh token returned; keeping the existing token"
fi

# Build, Keychain access, and token refresh can take long enough for the app to
# launch after the initial check. Refuse again at the actual dealer boundary.
ensure_nanyin_not_running
echo "[probe] starting dealer_test device_id=$DEVICE_ID (idles 300s, no audio)"
set +e
OUT=$("$BIN" "$TOKEN" "$DEVICE_ID" 2>&1)
STATUS=$?
set -e

printf '%s\n' "$OUT"
echo "[probe] exit=$STATUS"

if printf '%s' "$OUT" | grep -q "survived 300s"; then
    echo "RESULT: idle dealer session remained stable for 300s; investigate the application path next"
    exit 0
elif printf '%s' "$OUT" | grep -q "SPIRC TASK ENDED"; then
    echo "RESULT: Spirc task ended after connecting; the dealer probe failed."
    exit 3
elif printf '%s' "$OUT" | grep -q "SESSION DIED"; then
    echo "RESULT: dealer session died after connecting; this matches the suspected restriction incident but is not unique to it."
    exit 3
elif [ "$STATUS" -ne 0 ]; then
    echo "RESULT: probe failed at $(printf '%s' "$OUT" | grep -o 't+[0-9]*0s' | tail -1 || echo 'startup'); inspect network, Spotify service, credentials, and suspected restriction state."
    exit 1
else
    echo "RESULT: probe ended without verdict — inspect output above."
    exit 4
fi
