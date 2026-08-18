#!/usr/bin/env bash
# Dealer stability probe (idle, no audio). Answers "is the account still
# penalized?" without touching real playback.
#
# Handles keymaster refresh-token ROTATION correctly: keymaster
# (65b70807…) returns a NEW refresh token on every refresh and kills the old
# one immediately. The naive AGENTS.md one-liner (refresh without capturing
# the rotated token) silently burns the keychain credential — that cost a
# full probe session on 2026-08-19. This script writes the rotated token
# back to keychain.
#
# Exit codes:
#   0  survived 300s (account fine → investigate code instead)
#   1  probe panicked / died mid-run (65s–130s = penalized, wait it out)
#   2  token refresh failed (dead keymaster token → re-auth via the app)
#   3  SESSION DIED (server ghosting → penalized, wait it out)
#
# Usage: script/dealer_probe.sh [device_id]

set -euo pipefail

SERVICE="com.nanyin.app.spotify"
CLIENT_ID="65b708073fc0480ea92a077233ca87bd" # keymaster (playback flow)
DEVICE_ID="${1:-nanyin_probe_check}"

keychain_get() { security find-generic-password -s "$SERVICE" -a "$1" -w 2>/dev/null || true; }
keychain_set() { security add-generic-password -s "$SERVICE" -a "$1" -w "$2" -U 2>/dev/null || true; }

RT=$(keychain_get playback_refresh_token)
if [ -z "$RT" ]; then
    # App migration: the original single-flow keymaster token works as the
    # playback refresh token (SpotifyAuth.storedRefreshToken legacy path).
    RT=$(keychain_get refresh_token)
fi
if [ -z "$RT" ]; then
    echo "ERROR: no keymaster refresh token in keychain (service=$SERVICE)." >&2
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
    echo "       invalid_grant = credential dead (rotated without being saved, or revoked by risk control)." >&2
    exit 2
fi

NEW_RT=$(printf '%s' "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token') or '')" 2>/dev/null || true)
if [ -n "$NEW_RT" ]; then
    keychain_set playback_refresh_token "$NEW_RT"
    echo "[probe] keymaster refresh token rotated -> saved to keychain (playback_refresh_token)"
else
    echo "[probe] note: no rotated token in refresh response (unexpected for keymaster)"
fi

cd "$(dirname "$0")/../rust"
BIN=target/release/examples/dealer_test
if [ ! -x "$BIN" ]; then
    echo "[probe] building dealer_test (first run)…"
    cargo build --release --example dealer_test
fi

echo "[probe] starting dealer_test device_id=$DEVICE_ID (idles 300s, no audio)"
set +e
OUT=$("$BIN" "$TOKEN" "$DEVICE_ID" 2>&1)
STATUS=$?
set -e

printf '%s\n' "$OUT"
echo "[probe] exit=$STATUS"

if printf '%s' "$OUT" | grep -q "survived 300s"; then
    echo "RESULT: account fine (dealer stable) -> investigate code, not the account"
    exit 0
elif printf '%s' "$OUT" | grep -q "SESSION DIED"; then
    echo "RESULT: penalized (server ghosting). Wait it out (hours to ~a day); do NOT retry playback."
    exit 3
elif [ "$STATUS" -ne 0 ]; then
    echo "RESULT: penalized (died at $(printf '%s' "$OUT" | grep -o 't+[0-9]*0s' | tail -1 || echo 'startup')). TLS-drop at Spirc::new = deepest tier, softens first."
    exit 1
else
    echo "RESULT: probe ended without verdict — inspect output above."
    exit 4
fi
