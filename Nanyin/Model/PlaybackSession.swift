import Foundation
import NanyinKit
import Observation

/// The librespot session: its credential, its Connect device, and when to
/// bring it back. The only owner of `PlaybackEngine`.
///
/// Rules this keeps, so the account never looks like abusive traffic:
/// - the Connect device id is created once per install and never changes;
/// - the playback OAuth token is used once, to obtain librespot's reusable
///   credential; afterwards only that credential is used, and nothing is
///   ever refreshed in the background;
/// - only an explicit login refusal discards the credential, and a new
///   approval always waits for the user to click;
/// - reconnects are bounded (`ReconnectPolicy`); one picks up only the song
///   the dropped session left playing, which plays on meanwhile, once.
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

    private(set) var state: State = .notSetUp {
        didSet { if !readyWaiters.isEmpty { resumeReadyWaiters() } }
    }
    var isReady: Bool { state == .ready }
    /// Player events (everything but the session's own).
    var onPlayerEvent: (CoreEvent) -> Void = { _ in }

    private let secrets: any SecretStore
    private let engine = PlaybackEngine.shared
    private let oauth = SpotifyOAuth()
    private var policy = ReconnectPolicy()
    private var expectedUsername: String?
    private var retryTask: Task<Void, Never>?
    /// The core kept a dropped session's song playing for the next one.
    private var carrying = false
    private var authorizeTask: Task<Void, Never>?
    /// The Keychain copy of librespot's credential, read once.
    @ObservationIgnored private lazy var credentials: String? =
        (try? secrets.read(Self.credentialsKey)).flatMap { String(data: $0, encoding: .utf8) }

    private static let credentialsKey = "playback-credentials"
    private static let deviceIDKey = "ConnectDeviceID"

    init(secrets: any SecretStore) {
        self.secrets = secrets
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Connects with the saved credential, if there is one. Called once the
    /// Web API profile is known, so the session can be bound to that account.
    func start(for username: String) {
        expectedUsername = username
        guard state == .notSetUp else { return }
        connectStored()
    }

    /// Explicit user action: the browser approval for playback.
    func authorize() {
        guard expectedUsername != nil else { return }
        authorizeTask?.cancel()
        retryTask?.cancel()
        state = .authorizing
        authorizeTask = Task {
            do {
                let token = try await oauth.authorizeInBrowser(.playback)
                policy.reset()
                connect(.accessToken(token.accessToken))
            } catch is CancellationError {
            } catch {
                state = .needsAuthorization(error.localizedDescription)
            }
        }
    }

    /// Explicit user action after a failure: try the saved credential now.
    func retry() {
        policy.reset()
        if !connectStored() { state = .notSetUp }
    }

    func signOut() {
        authorizeTask?.cancel()
        retryTask?.cancel()
        carrying = false
        engine.disconnect()
        saveCredentials(nil)
        expectedUsername = nil
        state = .notSetUp
    }

    /// Sends a command to the session; returns why it could not, if it could not.
    func send(_ command: CoreCommand) -> String? {
        switch state {
        case .ready:
            return engine.send(command) ? nil : "Playback stopped responding."
        case .connecting, .waiting:
            // The song a dropped session left still takes play, pause, seek
            // and volume; the rest waits for the new session.
            return engine.send(command) ? nil : "Reconnecting to Spotify. Try again in a moment."
        default:
            return "Set up playback on this Mac first."
        }
    }

    // MARK: Reads

    struct ReadError: LocalizedError {
        let errorDescription: String?
    }

    /// Reads waiting for a connection in progress to finish.
    @ObservationIgnored private var readyWaiters: [CheckedContinuation<Void, any Error>] = []

    /// A page of a playlist, read through the session rather than the Web API.
    func readPlaylist(id: String, offset: Int) async throws -> SessionPlaylistPage {
        try await untilReady()
        return try await engine.request(.playlist(id: id, offset: offset))
    }

    /// Waits out a connection in progress (just after launch, or a
    /// reconnect); fails at once if none is coming.
    private func untilReady() async throws {
        switch state {
        case .ready: return
        case .connecting, .authorizing, .waiting: try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        default: throw ReadError(errorDescription: "Connect playback on this Mac to open this playlist.")
        }
    }

    private func resumeReadyWaiters() {
        let result: Result<Void, any Error>
        switch state {
        case .ready: result = .success(())
        case .connecting, .authorizing, .waiting: return
        default: result = .failure(ReadError(errorDescription: "Connect playback on this Mac to open this playlist."))
        }
        let waiters = readyWaiters
        readyWaiters = []
        for waiter in waiters { waiter.resume(with: result) }
    }

    // MARK: Connecting

    @discardableResult
    private func connectStored() -> Bool {
        guard let credentials else { return false }
        connect(.stored(json: credentials))
        return true
    }

    private func connect(_ credentials: CoreConfig.Credentials) {
        retryTask?.cancel()
        state = .connecting
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        engine.connect(CoreConfig(
            deviceID: Self.deviceID,
            deviceName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nanyin",
            initialVolume: Player.savedVolume,
            credentials: credentials,
            expectedUsername: expectedUsername,
            audioCacheDir: caches?.appending(path: Bundle.main.bundleIdentifier ?? "Nanyin").appending(path: "audio").path,
            audioCacheLimit: 1 << 30
        ))
    }

    private func saveCredentials(_ value: String?) {
        guard value != credentials else { return }
        credentials = value
        if let value {
            try? secrets.write(Data(value.utf8), for: Self.credentialsKey)
        } else {
            try? secrets.delete(Self.credentialsKey)
        }
    }

    private static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceIDKey) { return id }
        let id = (0 ..< 20).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
    }

    private func handle(_ event: CoreEvent) {
        switch event {
        case .connected(_, let credentials):
            carrying = false
            if let credentials { saveCredentials(credentials) }
            policy.connected()
            state = .ready
        case .connectFailed(let reason, let message):
            switch reason {
            case .authRejected:
                stopCarried()
                saveCredentials(nil)
                state = .needsAuthorization("Spotify no longer accepts this Mac's playback sign-in.")
            case .accountMismatch:
                stopCarried()
                saveCredentials(nil)
                state = .needsAuthorization("Playback was approved for a different Spotify account. Approve it with the account you signed in with.")
            case .timeout, .other:
                scheduleRetry(reason: message)
            }
        case .sessionEnded(let resuming):
            carrying = resuming
            onPlayerEvent(event)
            if !(policy.sessionDropped() && connectStored()) {
                stopCarried()
                state = .failed("The connection to Spotify keeps dropping.")
            }
        default:
            onPlayerEvent(event)
        }
    }

    /// No session will take the kept song over: stop it. A failed attempt
    /// that will be retried leaves it playing.
    private func stopCarried() {
        guard carrying else { return }
        carrying = false
        engine.disconnect()
        onPlayerEvent(.sessionEnded(resuming: false))
    }

    private func scheduleRetry(reason: String) {
        guard credentials != nil else {
            stopCarried()
            state = .needsAuthorization(reason)
            return
        }
        let delay = policy.attemptFailed()
        state = .waiting(until: .now.addingTimeInterval(delay), reason: reason)
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            connectStored()
        }
    }
}

#if DEBUG
extension PlaybackSession {
    func showDemoReady() { state = .ready }
}
#endif
