import AppKit
import Foundation

/// Detects an already-running copy of Nanyin with the same bundle identifier so
/// two processes never hold two Spotify Connect sessions for the same device ID.
enum AppInstance {
    static var isSecondary: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NANYIN_DEMO"] == "1" { return false }
        #endif
        return existingRunningInstance() != nil
    }

    static func existingRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
    }
}

/// Handles macOS application lifecycle hooks that SwiftUI's `App` protocol does
/// not cover directly: single-instance enforcement, clean librespot disconnect
/// on quit, system wake reconnection, and Dock reopen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?
    private var wakeTask: Task<Void, Never>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if AppInstance.isSecondary, let existing = AppInstance.existingRunningInstance() {
            NSApp.yieldActivation(to: existing)
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppInstance.isSecondary else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWakeReconnect() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let target = sender.windows.first { $0.frameAutosaveName == "Main" }
                ?? sender.windows.first { $0.canBecomeMain }
            if let target {
                target.deminiaturize(nil)
                target.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeTask?.cancel()
        wakeTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        AppModel.active?.prepareForTermination()
    }

    /// Gives Wi-Fi / network interfaces a moment to come back after wake before
    /// nudging a backed-off playback session to reconnect.
    private func scheduleWakeReconnect() {
        wakeTask?.cancel()
        wakeTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            AppModel.active?.handleSystemWake()
        }
    }
}
