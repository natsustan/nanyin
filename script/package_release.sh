#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Nanyin"
SCHEME="Nanyin"
CONFIGURATION="Release"
DESTINATION="generic/platform=macOS"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Nanyin.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/build/ReleaseDerivedData"
RELEASE_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
BUILT_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
DMG_ROOT="$RELEASE_DIR/dmg-root"
APPCAST_DIR="$ROOT_DIR/dist/appcast"
SPARKLE_KEY_ACCOUNT="nanyin"
SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/natsustan/nanyin/releases/latest/download/"

SIGN=false
NOTARIZE=false
DMG_PATH=""

export PATH="$HOME/.local/share/mise/shims:$HOME/.cargo/bin:$PATH"

usage() {
  cat >&2 <<EOF
usage: $0 [--sign] [--notarize]

Build an arm64 Release app and DMG without launching Nanyin.

  --sign       Sign the app and DMG with a Developer ID Application identity.
  --notarize   Sign, notarize, and staple the app/DMG, then create a signed
                Sparkle appcast and update archive.

Environment for signed builds:
  NANYIN_SIGN_IDENTITY    Full Developer ID Application identity. Auto-detected
                          when exactly one matching identity is installed.
  NANYIN_NOTARY_PROFILE   notarytool Keychain profile (required by --notarize).
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sign)
        SIGN=true
        ;;
      --notarize)
        SIGN=true
        NOTARIZE=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown argument: $1" >&2
        usage
        exit 2
        ;;
    esac
    shift
  done
}

require_tools() {
  local tool
  for tool in xcodegen xcodebuild hdiutil ditto lipo otool shasum; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "ERROR: required tool not found: $tool" >&2
      exit 1
    }
  done

  [[ -x /usr/libexec/PlistBuddy ]] || {
    echo "ERROR: required tool not found: /usr/libexec/PlistBuddy" >&2
    exit 1
  }

  if [[ "$SIGN" == true ]]; then
    for tool in codesign file security; do
      command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required signing tool not found: $tool" >&2
        exit 1
      }
    done
  fi

  if [[ "$NOTARIZE" == true ]]; then
    for tool in xcrun spctl; do
      command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required notarization tool not found: $tool" >&2
        exit 1
      }
    done

    [[ -n "${NANYIN_NOTARY_PROFILE:-}" ]] || {
      echo "ERROR: NANYIN_NOTARY_PROFILE is required by --notarize" >&2
      exit 1
    }
  fi
}

build_app() {
  (
    cd "$ROOT_DIR"
    xcodegen generate
  )

  rm -rf "$DERIVED_DATA_PATH" "$RELEASE_DIR"
  mkdir -p "$RELEASE_DIR"

  local build_settings=(CODE_SIGNING_ALLOWED=NO)
  if [[ "$SIGN" == true ]]; then
    build_settings+=(SWIFT_ACTIVE_COMPILATION_CONDITIONS=NANYIN_DISTRIBUTION)
  fi

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    "${build_settings[@]}" \
    archive

  ditto "$BUILT_APP" "$APP_BUNDLE"
}

validate_release_app() {
  local executable="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  local info_plist="$APP_BUNDLE/Contents/Info.plist"
  local architectures
  local runpaths

  [[ -x "$executable" ]] || {
    echo "ERROR: release executable is missing: $executable" >&2
    exit 1
  }

  architectures="$(lipo -archs "$executable")"
  [[ "$architectures" == "arm64" ]] || {
    echo "ERROR: expected an arm64-only executable, found: $architectures" >&2
    exit 1
  }

  if find "$APP_BUNDLE" -name '*.debug.dylib' -o -name '__preview.dylib' | grep -q .; then
    echo "ERROR: debug or preview dylibs were included in the Release app" >&2
    exit 1
  fi

  runpaths="$(otool -l "$executable" | awk '/LC_RPATH/{found=1; next} found && /path /{print $2; found=0}')"
  grep -Fxq '@executable_path/../Frameworks' <<<"$runpaths" || {
    echo "ERROR: release executable cannot resolve frameworks from Contents/Frameworks" >&2
    exit 1
  }

  [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist")" == \
    "https://github.com/natsustan/nanyin/releases/latest/download/appcast.xml" ]] || {
    echo "ERROR: release app has an unexpected or missing SUFeedURL" >&2
    exit 1
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist")" == \
    "SaF/yAnjVlByAFZ+72CJyGTMBW843AP/MMd26vUridg=" ]] || {
    echo "ERROR: release app has an unexpected or missing SUPublicEDKey" >&2
    exit 1
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUScheduledCheckInterval' "$info_plist")" == "43200" ]] || {
    echo "ERROR: release app has an unexpected or missing SUScheduledCheckInterval" >&2
    exit 1
  }
}

sparkle_tool() {
  local name="$1"
  local tool
  tool="$(find "$DERIVED_DATA_PATH/SourcePackages/artifacts" \
    -type f -path "*/bin/$name" -perm -111 -print -quit 2>/dev/null || true)"
  [[ -x "$tool" ]] || {
    echo "ERROR: Sparkle tool not found after package resolution: $name" >&2
    exit 1
  }
  printf '%s\n' "$tool"
}

resolve_signing_identity() {
  if [[ -n "${NANYIN_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$NANYIN_SIGN_IDENTITY"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p')"

  if [[ "$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
    echo "ERROR: set NANYIN_SIGN_IDENTITY to one Developer ID Application identity" >&2
    exit 1
  fi

  printf '%s\n' "$identities"
}

sign_app() {
  local identity="$1"
  local executable="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  local candidate
  local sparkle_framework="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  local sparkle_version_dir="$sparkle_framework/Versions/B"

  if [[ -d "$sparkle_version_dir" ]]; then
    # Sparkle's helpers carry different entitlements. Sign them inside-out and
    # never use --deep for signing; the outer app is signed separately below.
    codesign --force --timestamp --options runtime \
      --preserve-metadata=entitlements --sign "$identity" \
      "$sparkle_version_dir/XPCServices/Installer.xpc"
    codesign --force --timestamp --options runtime \
      --preserve-metadata=entitlements --sign "$identity" \
      "$sparkle_version_dir/XPCServices/Downloader.xpc"
    codesign --force --timestamp --options runtime --sign "$identity" \
      "$sparkle_version_dir/Autoupdate"
    codesign --force --timestamp --options runtime --sign "$identity" \
      "$sparkle_version_dir/Updater.app"
    codesign --force --timestamp --options runtime --sign "$identity" \
      "$sparkle_framework"
  fi

  # Sign nested Mach-O code from the inside out. The Rust core and Swift
  # package are statically linked today. Sparkle is handled explicitly above.
  while IFS= read -r -d '' candidate; do
    [[ "$candidate" == "$executable" ]] && continue
    [[ "$candidate" == "$sparkle_framework/"* ]] && continue
    if file "$candidate" | grep -q 'Mach-O'; then
      codesign --force --timestamp --options runtime --sign "$identity" "$candidate"
    fi
  done < <(find "$APP_BUNDLE/Contents" -type f -perm -111 -print0)

  codesign --force --timestamp --options runtime --sign "$identity" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

create_dmg() {
  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
  DMG_PATH="$RELEASE_DIR/$APP_NAME-$version-arm64.dmg"

  rm -rf "$DMG_ROOT" "$DMG_PATH"
  mkdir -p "$DMG_ROOT"
  ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  rm -rf "$DMG_ROOT"
}

notarize_artifacts() {
  local profile="${NANYIN_NOTARY_PROFILE:-}"
  [[ -n "$profile" ]] || {
    echo "ERROR: NANYIN_NOTARY_PROFILE is required by --notarize" >&2
    exit 1
  }

  # Notarize and staple the app first, then rebuild the DMG so it contains the
  # stapled app. The final DMG submission makes the downloadable container
  # independently verifiable by Gatekeeper.
  local app_zip="$RELEASE_DIR/$APP_NAME-notarization.zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$app_zip"
  xcrun notarytool submit "$app_zip" \
    --keychain-profile "$profile" \
    --wait \
    --output-format json \
    | tee "$RELEASE_DIR/notary-app.json"
  rm -f "$app_zip"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"

  create_dmg
  local identity
  identity="$(resolve_signing_identity)"
  codesign --force --timestamp --sign "$identity" "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$profile" \
    --wait \
    --output-format json \
    | tee "$RELEASE_DIR/notary-dmg.json"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
}

generate_sparkle_appcast() {
  local generate_appcast
  local generate_keys
  local version
  local update_zip
  local private_key_file="$RELEASE_DIR/.sparkle-private-key"
  local previous_umask

  generate_appcast="$(sparkle_tool generate_appcast)"
  generate_keys="$(sparkle_tool generate_keys)"
  rm -f "$private_key_file"
  trap 'rm -f "$private_key_file"' RETURN
  previous_umask="$(umask)"
  umask 077
  "$generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -x "$private_key_file" >/dev/null
  umask "$previous_umask"

  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
  update_zip="$APPCAST_DIR/$APP_NAME-$version.zip"
  mkdir -p "$APPCAST_DIR"
  rm -f "$update_zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$update_zip"

  "$generate_appcast" \
    --ed-key-file "$private_key_file" \
    --download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX" \
    --maximum-versions 1 \
    --maximum-deltas 5 \
    --embed-release-notes \
    "$APPCAST_DIR"

  [[ -f "$APPCAST_DIR/appcast.xml" ]] || {
    echo "ERROR: Sparkle appcast was not generated" >&2
    exit 1
  }
  grep -Fq 'sparkle:edSignature=' "$APPCAST_DIR/appcast.xml" || {
    echo "ERROR: Sparkle appcast update is missing an EdDSA signature" >&2
    exit 1
  }

  rm -f "$private_key_file"
  trap - RETURN
  echo "Sparkle appcast: $APPCAST_DIR/appcast.xml"
  echo "Sparkle update: $update_zip"
}

main() {
  parse_args "$@"
  require_tools
  build_app
  validate_release_app

  if [[ "$SIGN" == true ]]; then
    local identity
    identity="$(resolve_signing_identity)"
    sign_app "$identity"
  fi

  create_dmg

  if [[ "$SIGN" == true && "$NOTARIZE" != true ]]; then
    local identity
    identity="$(resolve_signing_identity)"
    codesign --force --timestamp --sign "$identity" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
  fi

  if [[ "$NOTARIZE" == true ]]; then
    notarize_artifacts
    generate_sparkle_appcast
  fi

  (
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
  )
  echo "Release app: $APP_BUNDLE"
  echo "Release DMG: $DMG_PATH"
  echo "SHA-256: $DMG_PATH.sha256"
  if [[ "$SIGN" != true ]]; then
    echo "Unsigned local artifact only. Use --sign or --notarize for distribution."
  fi
}

main "$@"
