//
//  NanyinApp.swift
//  Nanyin
//

import SwiftUI

@main
struct NanyinApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appModel.start()
                    appModel.startPositionPolling()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") { appModel.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { appModel.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { appModel.prev() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}
