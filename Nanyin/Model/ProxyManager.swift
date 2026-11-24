import Foundation
import NanyinKit
import Observation

/// Owns the app's proxy settings, Keychain-stored proxy password, and the
/// shared `HTTPTransport` used by OAuth, the Web API, and artwork.
@MainActor
@Observable
final class ProxyManager {
    var mode: ProxyMode
    var host: String
    var port: String
    var username: String
    var password: String

    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var appliedSettings: ProxySettings
    private(set) var appliedPassword: String

    let transport = HTTPTransport()
    /// Called when the playback proxy URL changes so `PlaybackSession` can
    /// pick up the new route.
    var onPlaybackProxyChanged: (String?) -> Void = { _ in }

    private let secrets: any SecretStore
    private static let settingsKey = "ProxySettings"
    private static let passwordKey = "proxy-password"

    init(secrets: any SecretStore) {
        self.secrets = secrets
        let saved: ProxySettings = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(ProxySettings.self, from: $0) }
            ?? ProxySettings()
        let savedPassword = (try? secrets.read(Self.passwordKey))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        self.mode = saved.mode
        self.host = saved.host
        self.port = saved.port
        self.username = saved.username
        self.password = savedPassword
        self.appliedSettings = saved
        self.appliedPassword = savedPassword

        do {
            try transport.apply(saved, password: savedPassword, blockOnFailure: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var currentDraft: ProxySettings {
        ProxySettings(
            mode: mode,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var hasPendingManualChanges: Bool {
        mode.isManual && (currentDraft != appliedSettings || password != appliedPassword)
    }

    /// HTTP proxy URL passed to librespot, when using an unauthenticated HTTP proxy.
    var playbackProxyURL: String? {
        appliedSettings.playbackProxyURL(password: appliedPassword)
    }

    func discardUnsavedChanges() {
        mode = appliedSettings.mode
        host = appliedSettings.host
        port = appliedSettings.port
        username = appliedSettings.username
        password = appliedPassword
        statusMessage = nil
        if (try? transport.currentSession()) != nil {
            errorMessage = nil
        }
    }

    /// Applies any unsaved manual proxy edits before an auth flow starts.
    /// Returns `false` (keeping `errorMessage` visible) if the draft or saved
    /// proxy configuration is invalid.
    @discardableResult
    func applyPendingIfNeeded() -> Bool {
        if hasPendingManualChanges {
            return apply()
        }
        guard (try? transport.currentSession()) != nil else { return false }
        errorMessage = nil
        return true
    }

    func selectMode(_ newMode: ProxyMode) {
        mode = newMode
        statusMessage = nil
        errorMessage = nil
        if !newMode.isManual {
            apply()
        }
    }

    @discardableResult
    func apply() -> Bool {
        statusMessage = nil
        errorMessage = nil
        let draft = currentDraft
        let secret = draft.mode.isManual ? password : ""
        let previousPlayback = playbackProxyURL

        do {
            try transport.apply(draft, password: secret)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        host = draft.host
        port = draft.port
        username = draft.username
        appliedSettings = draft
        appliedPassword = secret

        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        if secret.isEmpty {
            try? secrets.delete(Self.passwordKey)
        } else {
            try? secrets.write(Data(secret.utf8), for: Self.passwordKey)
        }

        let newPlayback = playbackProxyURL
        if newPlayback != previousPlayback {
            onPlaybackProxyChanged(newPlayback)
        }
        statusMessage = draft.mode == .system
            ? "Using macOS system proxy."
            : draft.mode == .off
                ? "Proxy disabled."
                : "Proxy settings applied."
        return true
    }
}
