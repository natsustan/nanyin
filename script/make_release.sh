#!/usr/bin/env bash
# Builds Release (signed with Developer ID) and packages it for distribution.
#
# usage: script/make_release.sh [--notarize]
#
# Without --notarize: dist/Nanyin-<version>.dmg, signed but not notarized,
# for trying the Release build locally. Nothing leaves this Mac.
#
# With --notarize: the app and the DMG are notarized by Apple and stapled,
# and Sparkle's update archive and signed appcast are written to
# dist/updates/. Publishing is a separate, deliberate step: upload the DMG
# and everything new in dist/updates/ to the GitHub release v<version>.
#
#   NANYIN_NOTARY_PROFILE  notarytool Keychain profile (default: notarization)
#   NANYIN_SPARKLE_ACCOUNT Keychain account of Sparkle's EdDSA key (default: nanyin)
#
# Keep dist/updates/ between releases: generate_appcast makes delta updates
# from the earlier archives it finds there.
set -euo pipefail

NOTARIZE=false
case "${1:-}" in
    "") ;;
    --notarize) NOTARIZE=true ;;
    *) echo "usage: $0 [--notarize]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/build/DerivedData/Build/Products/Release/Nanyin.app"
DIST="$ROOT_DIR/dist"
UPDATES="$DIST/updates"
NOTARY_PROFILE="${NANYIN_NOTARY_PROFILE:-notarization}"
SPARKLE_ACCOUNT="${NANYIN_SPARKLE_ACCOUNT:-nanyin}"
REPO_URL="https://github.com/natsustan/nanyin"

export NANYIN_CONFIGURATION=Release
"$ROOT_DIR/script/build.sh"
source "$ROOT_DIR/script/signing.sh"
SIGN_IDENTITY="${NANYIN_CODE_SIGN_IDENTITY:-$NANYIN_IDENTITY_KIND}"

# Sparkle's package ships its helpers signed ad hoc and Xcode re-signs only
# the framework around them; notarization needs every one on Developer ID.
# Sign inside out, never with --deep, then the framework and the app again.
sign() { codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign --preserve-metadata=entitlements "$APP"

codesign --verify --deep --strict "$APP"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] || {
    echo "Nanyin.app is not signed with Developer ID." >&2
    exit 1
}

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$DIST/Nanyin-$VERSION.dmg"
mkdir -p "$DIST"

# notarytool exits 0 even when Apple refuses the submission; read the status.
notarize() {
    local result id status
    result="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
    id="$(plutil -extract id raw - <<<"$result")"
    status="$(plutil -extract status raw - <<<"$result")"
    echo "Notarization of $(basename "$1"): $status ($id)"
    if [[ "$status" != "Accepted" ]]; then
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
}

if $NOTARIZE; then
    SUBMISSION="$(mktemp -d)"
    trap 'rm -rf "$SUBMISSION"' EXIT
    ditto -c -k --keepParent "$APP" "$SUBMISSION/Nanyin.zip"
    notarize "$SUBMISSION/Nanyin.zip"
    xcrun stapler staple "$APP"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "${SUBMISSION:-}"' EXIT
ditto "$APP" "$STAGE/Nanyin.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname Nanyin -srcfolder "$STAGE" -format ULMO "$DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
hdiutil verify -quiet "$DMG"

if ! $NOTARIZE; then
    echo "$DMG (not notarized)"
    exit 0
fi

notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# Sparkle installs from a zip of the stapled app; the appcast lists only this
# version, with deltas from up to five earlier archives kept in UPDATES.
SPARKLE_BIN="$(dirname "$(find "$ROOT_DIR/build/DerivedData/SourcePackages/artifacts" -type f -path "*/bin/generate_appcast" -print -quit)")"
mkdir -p "$UPDATES"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$UPDATES/Nanyin-$VERSION.zip"
# The Keychain lets only generate_keys (which created the key) read it, so
# it exports the key for generate_appcast to a private file removed on exit.
KEY_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE" "${SUBMISSION:-}" "$KEY_DIR"' EXIT
"$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -x "$KEY_DIR/key" >/dev/null
"$SPARKLE_BIN/generate_appcast" \
    --ed-key-file "$KEY_DIR/key" \
    --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
    --maximum-versions 1 \
    "$UPDATES"
grep -q 'sparkle:edSignature=' "$UPDATES/appcast.xml" || {
    echo "The appcast has no EdDSA signature." >&2
    exit 1
}

echo "Release v$VERSION ready. Upload to $REPO_URL/releases/tag/v$VERSION:"
echo "  $DMG"
echo "  $UPDATES/appcast.xml"
echo "  $UPDATES/Nanyin-$VERSION.zip"
ls "$UPDATES" | grep -E "^Nanyin$VERSION-.*\.delta$" | sed "s#^#  $UPDATES/#" || true
