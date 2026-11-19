import SwiftUI

@main
struct NanyinApp: App {
    @State private var app = AppModel()

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
