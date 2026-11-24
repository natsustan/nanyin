import Sparkle
import SwiftUI

/// Sparkle checks the release feed (`SUFeedURL`). Debug builds ("Nanyin Dev")
/// never check: the feed carries the release app, which would replace them.
#if DEBUG
private let checksForUpdates = false
#else
private let checksForUpdates = true
#endif

@main
struct NanyinApp: App {
    @State private var app = AppModel()
    private let updater = SPUStandardUpdaterController(
        startingUpdater: checksForUpdates, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        // Cover art comes from Spotify's image CDN (not the Web API); keep
        // enough of it that revisiting a page does not download it again.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        Window("Nanyin", id: "main") {
            MainWindow()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                if checksForUpdates {
                    Button("Check for Updates…") { updater.checkForUpdates(nil) }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Playlist") { app.library.begin(.new) }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!app.library.canEditPlaylists)
            }
            CommandGroup(after: .textEditing) {
                Button("Search") { app.navigator.focusSearch() }
                    .keyboardShortcut("l", modifiers: .command)
            }
            CommandMenu("Playback") {
                // Space plays and pauses too, outside text fields
                // (MainWindow); as a menu shortcut it would eat typed spaces.
                Button(app.player.isPlaying ? "Pause" : "Play") { app.player.togglePlayPause() }
                Button("Next") { app.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { app.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("Shuffle") { app.player.toggleShuffle() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Repeat") { app.player.cycleRepeat() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
