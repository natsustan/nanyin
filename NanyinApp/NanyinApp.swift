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

    /// Cheap Liked Songs probe when coming back from another app (phone like
    /// → look at nanyin). No dealer library push exists for third-party clients.
    func applicationDidBecomeActive(_ notification: Notification) {
        appModel.handleAppDidBecomeActive()
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
            CommandGroup(after: .newItem) {
                Button("Search") { delegate.appModel.focusSearch() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Find") { delegate.appModel.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { delegate.appModel.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!delegate.appModel.isPlaybackReady)
                Button("Next") { delegate.appModel.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!delegate.appModel.isPlaybackReady)
                Button("Previous") { delegate.appModel.prev() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!delegate.appModel.isPlaybackReady)
            }
        }
    }
}
