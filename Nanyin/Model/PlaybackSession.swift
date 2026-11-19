import AppKit
import NanyinKit
import Observation

/// The librespot session: its credential, its Connect device, and when to
/// bring it back.
///
/// Rules this keeps, so the account never looks like abusive traffic:
/// - the Connect device id is created once per install and never changes;
/// - the playback OAuth token is used once, to obtain librespot's reusable
///   credential; afterwards only that credential is used, and nothing is
///   ever refreshed in the background;
/// - only an explicit login refusal discards the credential, and a new
///   approval always waits for the user to click;
/// - reconnects are bounded (`ReconnectPolicy`) and never replay playback.
@MainActor
@Observable
final class PlaybackSession {
    enum State: Equatable {
        case notSetUp
        case authorizing
        case connecting
        case ready
        case waiting(until: Date, reason: String)
        case needsAuthorization(String)
        case failed(String)
    }

    private(set) var state: State = .notSetUp
    var isReady: Bool { state == .ready }

    private let secrets: any SecretStore
    private let engine = PlaybackEngine.shared
    private let oauth = SpotifyOAuth()
    private var policy = ReconnectPolicy()
    private var expectedUsername: String?
    private var retryTask: Task<Void, Never>?
    private var authorizeTask: Task<Void, Never>?
    /// Player events go here; session events are handled in this class.
    var onPlayerEvent: (CoreEvent) -> Void = { _ in }

    private static let credentialsKey = "playback-credentials"
    private static let deviceIDKey = "ConnectDeviceID"
    private static let volumeKey = "PlaybackVolume"

    init(secrets: any SecretStore) {
        self.secrets = secrets
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }

    private var storedCredentials: String? {
        (try? secrets.read(Self.credentialsKey)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Connects with the saved credential, if there is one. Called once the
    /// Web API profile is known, so the session can be bound to that account.
    func start(for username: String) {
        expectedUsername = username
        guard state == .notSetUp else { return }
        if let stored = storedCredentials {
            connect(.stored(json: stored))
        } else {
            state = .notSetUp
        }
    }

    /// Explicit user action: the browser approval for playback.
    func authorize() {
        guard expectedUsername != nil else { return }
        authorizeTask?.cancel()
        retryTask?.cancel()
        state = .authorizing
        authorizeTask = Task {
            do {
                let token = try await oauth.authorize(.playback) { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
                policy.reset()
                connect(.accessToken(token.accessToken))
            } catch is CancellationError {
            } catch LoopbackReceiver.Failure.cancelled {
            } catch LoopbackReceiver.Failure.portInUse(let port) {
                state = .needsAuthorization("Another app is using port \(port). Quit it and try again.")
            } catch {
                state = .needsAuthorization(error.localizedDescription)
            }
        }
    }

    /// Explicit user action after a failure: try the saved credential now.
    func retry() {
        policy.reset()
        guard let stored = storedCredentials else {
            state = .notSetUp
            return
        }
        connect(.stored(json: stored))
    }

    func signOut() {
        authorizeTask?.cancel()
        retryTask?.cancel()
        engine.disconnect()
        try? secrets.delete(Self.credentialsKey)
        expectedUsername = nil
        state = .notSetUp
    }

    var volume: UInt16 {
        get {
            let saved = UserDefaults.standard.object(forKey: Self.volumeKey) as? Int
            return UInt16(clamping: saved ?? Int(Double(UInt16.max) * 0.7))
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Self.volumeKey) }
    }

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: Self.deviceIDKey) { return id }
        let id = (0 ..< 20).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        UserDefaults.standard.set(id, forKey: Self.deviceIDKey)
        return id
    }

    private func connect(_ credentials: CoreConfig.Credentials) {
        retryTask?.cancel()
        state = .connecting
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        engine.connect(CoreConfig(
            deviceID: deviceID,
            deviceName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nanyin",
            initialVolume: volume,
            credentials: credentials,
            expectedUsername: expectedUsername,
            audioCacheDir: caches?.appending(path: Bundle.main.bundleIdentifier ?? "Nanyin").appending(path: "audio").path,
            audioCacheLimit: 1 << 30
        ))
    }

    private func handle(_ event: CoreEvent) {
        switch event {
        case .connected(_, let credentials):
            if let credentials {
                try? secrets.write(Data(credentials.utf8), for: Self.credentialsKey)
            }
            policy.connected()
            state = .ready
        case .connectFailed(let reason, let message):
            switch reason {
            case .authRejected:
                try? secrets.delete(Self.credentialsKey)
                state = .needsAuthorization("Spotify no longer accepts this Mac's playback sign-in.")
            case .accountMismatch:
                try? secrets.delete(Self.credentialsKey)
                state = .needsAuthorization("Playback was approved for a different Spotify account. Approve it with the account you signed in with.")
            case .timeout, .other:
                scheduleRetry(reason: message)
            }
        case .sessionEnded:
            if policy.sessionDropped(), let stored = storedCredentials {
                connect(.stored(json: stored))
            } else {
                state = .failed("The connection to Spotify keeps dropping.")
            }
            onPlayerEvent(.stopped)
        default:
            onPlayerEvent(event)
        }
    }

    private func scheduleRetry(reason: String) {
        guard storedCredentials != nil else {
            state = .needsAuthorization(reason)
            return
        }
        let delay = policy.attemptFailed()
        let until = Date.now.addingTimeInterval(delay)
        state = .waiting(until: until, reason: reason)
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let stored = storedCredentials else { return }
            connect(.stored(json: stored))
        }
    }
}
