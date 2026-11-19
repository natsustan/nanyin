import SwiftUI

@main
struct NanyinApp: App {
    @State private var app = AppModel()

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
            CommandMenu("Playback") {
                Button(app.player.isPlaying ? "Pause" : "Play") { app.player.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
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
    }
}
