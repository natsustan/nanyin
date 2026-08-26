# Homebrew Cask

The source cask lives at `homebrew/Casks/nanyin.rb`. It installs the same
versioned, notarized DMG published by the GitHub release and leaves day-to-day
updates to Sparkle (`auto_updates true`). Nanyin currently supports Apple
Silicon and macOS 15 or later.

The cask intentionally uses an immutable release URL:

```text
https://github.com/natsustan/nanyin/releases/download/v<version>/Nanyin-<version>-arm64.dmg
```

## Release update

After producing the final release artifacts:

1. Update `version` to `MARKETING_VERSION`.
2. Copy the SHA-256 from
   `build/release/Nanyin-<version>-arm64.dmg.sha256` into `sha256`.
3. Verify the cask references the exact DMG filename attached to the GitHub
   release.
4. Run the local style check:

   ```sh
   brew style homebrew/Casks/nanyin.rb
   ```

5. After the GitHub release exists, validate download and livecheck from a tap:

   ```sh
   brew audit --cask --new nanyin
   brew livecheck --cask nanyin
   brew install --cask nanyin
   ```

Do not publish the cask before the immutable DMG URL exists. Publishing to an
official or third-party tap is an external action separate from the local
release build.
