//
//  NanyinApp.swift
//  Nanyin
//

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    /// The single app-wide model (shared by UI, media keys, and remote commands).
    let appModel = AppModel()

    override init() {
        super.init()
        Self.shared = self
    }

    /// Send the Connect "goodbye" so this device disappears immediately
    /// instead of lingering as a zombie until the server times it out.
    func applicationWillTerminate(_ notification: Notification) {
        appModel.shutdown()
    }
}

@main
struct NanyinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.appModel)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    delegate.appModel.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") { delegate.appModel.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next") { delegate.appModel.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous") { delegate.appModel.prev() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}
