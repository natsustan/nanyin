# Distribution

Nanyin currently ships as an Apple Silicon (`arm64`) macOS 15+ application.
The Rust core is a static arm64 library, so the Xcode Release configuration is
intentionally arm64-only. A universal build requires adding an x86_64 Rust
build and combining both static libraries before changing `ARCHS`.

## Local release artifact

This is offline-safe: it does not launch Nanyin, read Spotify credentials, or
contact Apple services.

```sh
./script/package_release.sh
```

The command regenerates the Xcode project, creates a clean optimized Xcode
archive, rejects debug/preview dylibs and unexpected architectures, and writes:

- `build/release/Nanyin.xcarchive` (including dSYM)
- `build/release/Nanyin.app`
- `build/release/Nanyin-<version>-arm64.dmg`
- `build/release/Nanyin-<version>-arm64.dmg.sha256`

These default artifacts are unsigned and are only suitable for local
inspection.

## Developer ID signing

Install a `Developer ID Application` certificate, then run:

```sh
./script/package_release.sh --sign
```

The script auto-detects the identity when exactly one Developer ID Application
identity is available. Otherwise select it explicitly:

```sh
NANYIN_SIGN_IDENTITY='Developer ID Application: Example (TEAMID)' \
  ./script/package_release.sh --sign
```

The app is signed with a secure timestamp and Hardened Runtime. No entitlement
exceptions are currently required: audio uses AVAudioEngine, network access
uses system networking, Keychain uses the app's own access group, and the Rust
core is statically linked. Revisit this if a helper, dynamic framework, audio
input, JIT, or sandboxing is added.

## Notarization

Store App Store Connect credentials in a Keychain profile once, or reuse an
existing profile from the same Apple Developer team. This machine uses the
same-team `notomo-api` profile:

```sh
xcrun notarytool history --keychain-profile notomo-api
```

Submitting to Apple is an external release action. Run it deliberately:

```sh
NANYIN_NOTARY_PROFILE=notomo-api \
  ./script/package_release.sh --notarize
```

The script signs the app, notarizes and staples it, rebuilds the DMG around the
stapled app, then signs, notarizes, and staples the DMG. It retains the Apple
responses as `notary-app.json` and `notary-dmg.json`, finishes with a Gatekeeper
assessment, and generates a SHA-256 file.

## Sparkle updates

Nanyin pins Sparkle 2.9.1 and exposes **Check for Updates…** in the application
menu. The update configuration is embedded in `NanyinApp/Info.plist`:

```text
Feed: https://github.com/natsustan/nanyin/releases/latest/download/appcast.xml
Keychain account: nanyin
Check interval: 12 hours
```

The Ed25519 private key remains in the login Keychain under the `nanyin`
account. Only its public key is committed. The notarized release command
temporarily exports the key with mode 0600 for `generate_appcast`, removes the
file on return or failure, and writes these ignored release assets:

```text
dist/appcast/appcast.xml
dist/appcast/Nanyin-<version>.zip
dist/appcast/*.delta     # from the second compatible release onward
```

Do not delete `dist/appcast` between releases: `generate_appcast` retains the
previous archive long enough to generate up to five deltas, then prunes old
feed entries. Back up the Sparkle private key securely before the first public
release; losing it prevents existing installations from trusting future
updates.

The stable feed uses GitHub Releases' `latest/download` redirect. Each public
release therefore needs these assets with their generated filenames:

- `appcast.xml`
- `Nanyin-<version>.zip`
- any generated `.delta` files
- `Nanyin-<version>-arm64.dmg` and its `.sha256`

Publishing a GitHub release remains a deliberate external action and is not
performed by the packaging script.

## Release checklist

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `./script/agent_check.sh`.
3. Build and inspect an unsigned artifact with `./script/package_release.sh`.
4. Build the final artifact with `--notarize`; inspect the notarytool logs and
   verify that the appcast enclosure has an EdDSA signature.
5. Test the stapled DMG on a clean macOS account or machine before publishing.
6. Publish the DMG, checksum, appcast, update ZIP, and generated deltas as one
   GitHub release.

A Homebrew cask remains a follow-up and should reference an already-published,
versioned, notarized DMG.
