# Nanyin

A native macOS Spotify client that looks like Spotify for Mac did in 2010:
Aqua metal, Lucida Grande, a charcoal track list. Swift and SwiftUI for the
app, [librespot](https://github.com/librespot-org/librespot) for playback.

> Unofficial. Not affiliated with Spotify. Playback requires Spotify Premium.

## Using it

1. Create an app in the [Spotify developer dashboard](https://developer.spotify.com/dashboard)
   with the redirect URI `http://127.0.0.1:8989/login` and **Web API** ticked.
2. Paste its Client ID into Nanyin and sign in.
3. Choose **Set Up Playback…** once to approve playback on this Mac.
   Nanyin then appears as a Spotify Connect device.

## Building

```sh
mise install                 # rust, xcodegen, xcbeautify
script/build_and_run.sh
```

Requires macOS 26 and Xcode 26 or later. See `AGENTS.md` for the layout and
the rules that keep Spotify traffic well-behaved.
