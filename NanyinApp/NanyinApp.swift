//
//  NanyinApp.swift
//  Nanyin
//

import Darwin
import Sparkle
import SwiftUI

@main
private enum NanyinMain {
    private static var processLock: NanyinProcessLock?

    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let isDealerProbe = arguments.first == "--dealer-probe"
        if isDealerProbe, arguments.count > 2 {
            FileHandle.standardError.write(Data("Usage: Nanyin --dealer-probe [device_id]\n".utf8))
            Darwin.exit(64)
        }
        if isDealerProbe,
           ProcessInfo.processInfo.environment["NANYIN_ALLOW_LIVE_SPOTIFY"] != "1" {
            FileHandle.standardError.write(
                Data("ERROR: dealer_probe uses real Spotify credentials and opens a real dealer session.\n".utf8)
            )
            FileHandle.standardError.write(
                Data("       Set NANYIN_ALLOW_LIVE_SPOTIFY=1 only after explicit user authorization.\n".utf8)
            )
            Darwin.exit(64)
        }

        do {
            guard let lock = try NanyinProcessLock.acquire() else {
                FileHandle.standardError.write(
                    Data("ERROR: Nanyin is already running; stop it before starting another instance.\n".utf8)
                )
                Darwin.exit(6)
            }
            processLock = lock
        } catch {
            FileHandle.standardError.write(
                Data("ERROR: could not acquire Nanyin's process lock: \(error.localizedDescription)\n".utf8)
            )
            Darwin.exit(1)
        }

        guard isDealerProbe else {
            NanyinApp.main()
            return
        }

        let deviceId = arguments.dropFirst().first ?? "nanyin_probe_check"
        Darwin.exit(await runDealerProbe(deviceId: deviceId))
    }

    @MainActor
    private static func runDealerProbe(deviceId: String) async -> Int32 {
        guard !deviceId.isEmpty else {
            FileHandle.standardError.write(Data("ERROR: probe device id must not be empty.\n".utf8))
            return 64
        }

        let token: SpotifyAuth.Token
        do {
            token = try await SpotifyAuth.refreshAccessToken(for: .playback)
        } catch let error as KeychainStore.KeychainError {
            FileHandle.standardError.write(
                Data("ERROR: could not access Nanyin's playback credential: \(error.localizedDescription)\n".utf8)
            )
            return 5
        } catch let error as SpotifyAuth.AuthError {
            FileHandle.standardError.write(
                Data("ERROR: could not refresh the playback credential: \(error.localizedDescription)\n".utf8)
            )
            return 2
        } catch {
            FileHandle.standardError.write(Data("ERROR: token refresh failed: \(error.localizedDescription)\n".utf8))
            return 1
        }

        var disconnected = false
        Core.onDisconnected = { generation in
            if generation == 1 {
                disconnected = true
            }
        }

        print("[probe] starting Nanyin core device_id=\(deviceId) (idles 300s, no audio)")
        switch await Core.initializePlayer(
            accessToken: token.accessToken,
            deviceId: deviceId,
            generation: 1
        ) {
        case .connected:
            break
        case let .credentialsRejected(message):
            _ = Core.shutdown()
            FileHandle.standardError.write(Data("ERROR: playback credentials rejected: \(message)\n".utf8))
            return 2
        case let .failed(code, message):
            _ = Core.shutdown()
            FileHandle.standardError.write(Data("ERROR: probe initialization failed (\(code)): \(message)\n".utf8))
            return 1
        }

        print("[probe] spirc up — idling 300s, watching dealer")
        for interval in 1...30 {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if disconnected {
                _ = Core.shutdown()
                print("RESULT: dealer session died after connecting; inspect network, Spotify service, credentials, and suspected restriction state.")
                return 3
            }
            print("[probe] t+\(interval)0s")
        }

        _ = Core.shutdown()
        print("RESULT: idle dealer session remained stable for 300s; investigate the application path next")
        return 0
    }
}

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
