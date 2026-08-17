//
//  NanyinApp.swift
//  Nanyin
//

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    let appModel = AppModel()

    override init() {
        super.init()
        Self.shared = self
    }
}

@main
struct NanyinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appModel.start()
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
