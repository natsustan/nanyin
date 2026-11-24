import AppKit
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
        didSet {
            if state == .ready, oldValue != .ready { onReady() }
            if !readyWaiters.isEmpty { resumeReadyWaiters() }
        }
    }
    /// The active browser approval URL while `state == .authorizing`.
    private(set) var authorizeURL: URL?
    var isReady: Bool { state == .ready }
    var hasStoredCredentials: Bool { credentials != nil }
    var localDeviceName: String { settings.effectiveDeviceName }
    var localDeviceID: String { Self.deviceID }
    /// Fires when playback reaches `.ready`.
    var onReady: () -> Void = {}
    /// Player events (everything but the session's own).
    var onPlayerEvent: (CoreEvent) -> Void = { _ in }

    private let secrets: any SecretStore
    private let settings: PlaybackSettings
    private let engine: PlaybackEngine?
    private let oauth: SpotifyOAuth
    private var policy = ReconnectPolicy()
    private var expectedUsername: String?
    private var proxyURL: String?
    private var retryTask: Task<Void, Never>?
    private var settingsReconnectTask: Task<Void, Never>?
    /// The core kept a dropped session's song playing for the next one.
    private var carrying = false
    private var authorizeTask: Task<Void, Never>?
    /// The Keychain copy of librespot's credential, read once.
    @ObservationIgnored private lazy var credentials: String? =
        (try? secrets.read(Self.credentialsKey)).flatMap { String(data: $0, encoding: .utf8) }

    private static let credentialsKey = "playback-credentials"
    private static let deviceIDKey = "ConnectDeviceID"

    init(
        secrets: any SecretStore,
        settings: PlaybackSettings,
        transport: HTTPTransport = .shared,
        proxyURL: String? = nil,
        activateEngine: Bool = true
    ) {
        self.secrets = secrets
        self.settings = settings
        self.oauth = SpotifyOAuth(transport: transport)
        self.proxyURL = proxyURL
        let engine = activateEngine ? PlaybackEngine.shared : nil
        self.engine = engine
        engine?.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Updates the optional unauthenticated HTTP proxy for librespot.
    /// Reconnects only if a session was already active or trying to connect;
    /// never opens a browser or starts an unrequested sign-in.
    func updateProxy(_ newProxyURL: String?) {
        guard proxyURL != newProxyURL else { return }
        proxyURL = newProxyURL
        settingsReconnectTask?.cancel()
        reconnectForConfigChange(dropCarried: false)
    }

    /// Reconnects with updated audio quality, volume normalization, or device
    /// name when a session is already active or connecting. Debounced briefly so
    /// rapid clicks in Settings never trigger parallel AP logins.
    func applyPlaybackSettings() {
        guard expectedUsername != nil, credentials != nil else { return }
        switch state {
        case .ready, .connecting, .waiting, .failed:
            settingsReconnectTask?.cancel()
            settingsReconnectTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.reconnectForConfigChange(dropCarried: true)
            }
        case .notSetUp, .authorizing, .needsAuthorization:
            break
        }
    }

    /// Nudges a backed-off session to reconnect promptly after Mac wakes from
    /// sleep without clearing the 10-minute drop limit or opening a browser.
    func handleSystemWake() {
        guard case .waiting = state else { return }
        retryTask?.cancel()
        connectStored()
    }

    private func reconnectForConfigChange(dropCarried: Bool) {
        guard expectedUsername != nil, credentials != nil else { return }
        switch state {
        case .ready:
            // Replacing an active engine drops its loaded track and queue;
            // let Player snapshot a resume point before connecting fresh.
            onPlayerEvent(.sessionEnded(resuming: false))
            if dropCarried { engine?.disconnect() }
        case .connecting, .waiting, .failed:
            if dropCarried {
                if carrying {
                    stopCarried()
                } else {
                    engine?.disconnect()
                }
            }
        case .notSetUp, .authorizing, .needsAuthorization:
            return
        }
        policy.reset()
        connectStored()
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
        settingsReconnectTask?.cancel()
        authorizeURL = nil
        state = .authorizing
        authorizeTask = Task {
            do {
                let token = try await oauth.authorizeInBrowser(.playback) { url in
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.authorizeURL = url
                        }
                    }
                }
                authorizeURL = nil
                policy.reset()
                connect(.accessToken(token.accessToken))
            } catch is CancellationError {
                authorizeURL = nil
            } catch {
                authorizeURL = nil
                state = .needsAuthorization(error.localizedDescription)
            }
        }
    }

    /// Re-opens the active playback approval page in the browser.
    func reopenAuthorizeURL() {
        if let authorizeURL {
            _ = NSWorkspace.shared.open(authorizeURL)
        }
    }

    /// Cancels an in-flight browser approval so the user is never stuck.
    func cancelAuthorize() {
        authorizeTask?.cancel()
        authorizeTask = nil
        authorizeURL = nil
        if state == .authorizing {
            state = .notSetUp
        }
    }

    /// Explicit user action after a failure: try the saved credential now.
    func retry() {
        settingsReconnectTask?.cancel()
        policy.reset()
        if !connectStored() { state = .notSetUp }
    }

    func signOut() {
        authorizeTask?.cancel()
        authorizeTask = nil
        authorizeURL = nil
        retryTask?.cancel()
        settingsReconnectTask?.cancel()
        carrying = false
        engine?.disconnect()
        saveCredentials(nil)
        expectedUsername = nil
        state = .notSetUp
    }

    /// Sends a command to the session; returns why it could not, if it could not.
    func send(_ command: CoreCommand) -> String? {
        guard let engine else { return "Playback is unavailable." }
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

        static let notConnected = ReadError(errorDescription: "Connect playback on this Mac to read this from Spotify.")
    }

    /// Reads waiting for a connection in progress to finish.
    @ObservationIgnored private var readyWaiters: [CheckedContinuation<Void, any Error>] = []

    /// A page of a playlist, read through the session rather than the Web API.
    func readPlaylist(id: String, offset: Int) async throws -> SessionPlaylistPage {
        try await request(.playlist(id: id, offset: offset))
    }

    /// An artist's popular songs, read through the session: the Web API
    /// answers Development Mode apps 403 for them.
    func readTopTracks(artistID: String) async throws -> [CoreTrack] {
        try await request(.topTracks(artistID: artistID))
    }

    /// A song's credits, read through the session as Spotify's own clients
    /// read them (the Web API has none). Only ever asked for by the listener.
    func readCredits(trackID: String) async throws -> CoreCredits {
        try await request(.credits(trackID: trackID))
    }

    /// Followed artists' new releases, read through Pathfinder on the session.
    func readNewReleases(force: Bool = false) async throws -> [AlbumSummary] {
        try await request(.newReleases(force: force))
    }

    /// Personalized Home shelves (Made for you and Your top mixes), read
    /// through Pathfinder over the playback session.
    func readMadeForYou(force: Bool = false) async throws -> CoreHomeShelves {
        try await request(.madeForYou(timezone: TimeZone.current.identifier, force: force))
    }

    private func request<T: Decodable>(_ ask: CoreAsk) async throws -> T {
        try await untilReady()
        guard let engine else { throw ReadError.notConnected }
        return try await engine.request(ask)
    }

    /// Waits out a connection in progress (just after launch, or a
    /// reconnect); fails at once if none is coming.
    private func untilReady() async throws {
        switch state {
        case .ready: return
        case .connecting, .authorizing, .waiting: try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        default: throw ReadError.notConnected
        }
    }

    private func resumeReadyWaiters() {
        let result: Result<Void, any Error>
        switch state {
        case .ready: result = .success(())
        case .connecting, .authorizing, .waiting: return
        default: result = .failure(ReadError.notConnected)
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
        guard let engine else { return }
        retryTask?.cancel()
        settingsReconnectTask?.cancel()
        state = .connecting
        engine.connect(CoreConfig(
            deviceID: Self.deviceID,
            deviceName: settings.effectiveDeviceName,
            initialVolume: Player.savedVolume,
            credentials: credentials,
            expectedUsername: expectedUsername,
            audioCacheDir: PlaybackSettings.audioCacheDirectory?.path,
            audioCacheLimit: 1 << 30,
            proxy: proxyURL,
            bitrate: UInt16(settings.audioQuality.rawValue),
            normalisation: settings.normalizeVolume
        ))
    }

    /// Shuts down the librespot session cleanly before the app exits.
    func disconnectForTermination() {
        authorizeTask?.cancel()
        retryTask?.cancel()
        settingsReconnectTask?.cancel()
        carrying = false
        engine?.disconnect()
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
        engine?.disconnect()
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
