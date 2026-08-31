//
//  NanyinApp.swift
//  Nanyin
//

import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    /// The single app-wide model (shared by UI, media keys, and remote commands).
    let appModel = AppModel()
    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        Self.shared = self
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Cheap Liked Songs probe when coming back from another app (phone like
    /// → look at nanyin). No dealer library push exists for third-party clients.
    func applicationDidBecomeActive(_ notification: Notification) {
        appModel.handleAppDidBecomeActive()
    }

    func applicationDidResignActive(_ notification: Notification) {
        appModel.handleAppDidResignActive()
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
    @AppStorage(AppThemeID.preferenceKey)
    private var storedThemeID = AppThemeID.nanyinDark.rawValue

    var body: some Scene {
        WindowGroup("NanYin") {
            RootView()
                .environment(delegate.appModel)
                .environment(\.appTheme, AppTheme.resolve(selectedThemeID))
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .background {
                    ClassicTitleBarBridge(
                        isClassic: selectedThemeID == .classic2010,
                        app: delegate.appModel,
                        theme: AppTheme.resolve(selectedThemeID)
                    )
                }
                .onAppear {
                    delegate.appModel.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    delegate.checkForUpdates()
                }
            }
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
            CommandMenu("Navigate") {
                Button("Back") { delegate.appModel.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!delegate.appModel.canGoBack)
                Button("Forward") { delegate.appModel.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!delegate.appModel.canGoForward)
            }
            CommandMenu("Theme") {
                ForEach(AppThemeID.allCases) { themeID in
                    Toggle(themeID.displayName, isOn: themeSelection(for: themeID))
                }
            }
        }

        Settings {
            ThemeSettingsView()
                .preferredColorScheme(.dark)
        }
    }

    private var selectedThemeID: AppThemeID {
        AppThemeID(storedValue: storedThemeID)
    }

    private func themeSelection(for themeID: AppThemeID) -> Binding<Bool> {
        Binding(
            get: { selectedThemeID == themeID },
            set: { selected in
                if selected {
                    storedThemeID = themeID.rawValue
                }
            }
        )
    }
}
