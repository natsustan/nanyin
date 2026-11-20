#!/usr/bin/env bash
# Builds Release and packages it as build/Nanyin-<version>.dmg: the app and
# an Applications link, ready to drag-install. Signed like build.sh signs;
# not notarized.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/build/DerivedData/Build/Products/Release/Nanyin.app"

NANYIN_CONFIGURATION=Release "$ROOT_DIR/script/build.sh"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT_DIR/build/Nanyin-$VERSION.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname Nanyin -srcfolder "$STAGE" -format ULMO "$DMG"
hdiutil verify -quiet "$DMG"
echo "$DMG"
