import Foundation
import Darwin

enum PlaybackReconnectPolicy {
    static func shouldDeferRebuild(
        isPlaying: Bool,
        isBuffering: Bool,
        hasPendingPlay: Bool
    ) -> Bool {
        isPlaying && !isBuffering && !hasPendingPlay
    }

    static func shouldWaitForActivation(
        isAppActive: Bool,
        isPlaying: Bool,
        isBuffering: Bool,
        hasPendingPlay: Bool
    ) -> Bool {
        !isAppActive && !isPlaying && !isBuffering && !hasPendingPlay
    }
}

/// Only recovery consumes this budget; ordinary successful launches do not.
/// Keep recent recoveries across successes to bound short-lived sessions.
enum PlaybackReconnectBudget {
    static let window: Double = 600
    static let limit = 6
    static let retryDelays: [Double] = [5, 15, 60, 120, 300, 600]
}

struct PlaybackConnectionWait: Equatable {
    enum Reason { case service, recoveryBudget, backoff }
    let reason: Reason
    let deadline: Double

    func remaining(now: Double = ProcessInfo.processInfo.systemUptime) -> Double {
        max(0, deadline - now)
    }

    func message(now: Double = ProcessInfo.processInfo.systemUptime) -> String {
        let seconds = remaining(now: now).rounded(.up)
        guard seconds > 0 else { return "Playback can reconnect — click Retry" }
        let duration: String
        if seconds >= 86_400 { duration = String(format: "%.0f days", (seconds / 86_400).rounded(.up)) }
        else if seconds >= 60 { duration = "\(Int(seconds) / 60)m \(Int(seconds) % 60)s" }
        else { duration = "\(Int(seconds))s" }
        switch reason {
        case .service: return "Spotify requested a pause — retry in \(duration)"
        case .recoveryBudget: return "Repeated connection failures — retry in \(duration)"
        case .backoff: return "Playback connection interrupted — retry in \(duration)"
        }
    }
}

/// One command in flight. Selections replace queued intent; relative skips
/// retain their order. Only a new, matching player event releases the next
/// command. A timeout discards the queue and never retries the uncertain call.
@MainActor
final class PlaybackCommandQueue {
    enum Kind { case selection, next, previous }
    struct Receipt {
        let previousRequestID: UInt64
        var expectedURI: String? = nil
        var acceptsSeek = false
        var acceptsPaused = false
    }
    private struct Command {
        let action: @MainActor () -> Receipt?
    }
    private let minimumInterval: Duration
    private let timeout: Duration
    private var nextStart = ContinuousClock.now
    private var queued: [Command] = []
    private var inFlight: Receipt?
    private var drainTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    var onTimeout: (@MainActor () -> Void)?
    static let maximumPending = 8

    init(minimumInterval: Duration = .milliseconds(350), timeout: Duration = .seconds(8)) {
        self.minimumInterval = minimumInterval
        self.timeout = timeout
    }

    @discardableResult
    func submit(kind: Kind, _ action: @escaping @MainActor () -> Receipt?) -> Bool {
        if kind == .selection { queued.removeAll() }
        guard queued.count < Self.maximumPending else { return false }
        queued.append(Command(action: action))
        if inFlight == nil, drainTask == nil, ContinuousClock.now >= nextStart {
            drain()
        } else {
            scheduleDrain()
        }
        return true
    }

    func acknowledge(uri: String?, requestID: UInt64, seekPosition: Int? = nil, paused: Bool = false) {
        if paused, inFlight?.acceptsPaused != true {
            cancel() // remote pause wins, including while an acknowledged command awaits dispatch
            return
        }
        guard let receipt = inFlight, requestID != UInt64.max else { return }
        if let seekPosition {
            guard receipt.acceptsSeek, requestID == receipt.previousRequestID,
                  seekPosition <= 500 else { return }
        } else {
            guard requestID != receipt.previousRequestID,
                  receipt.expectedURI == nil || receipt.expectedURI == uri else { return }
        }
        inFlight = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        // Defer dispatch until AppModel has finished handling the confirming event.
        scheduleDrain()
    }

    private func scheduleDrain() {
        guard inFlight == nil, !queued.isEmpty, drainTask == nil else { return }
        let delay = max(.zero, ContinuousClock.now.duration(to: nextStart))
        drainTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.drainTask = nil
            self.drain()
        }
    }

    private func drain() {
        guard inFlight == nil, !queued.isEmpty else { return }
        let command = queued.removeFirst()
        nextStart = .now.advanced(by: minimumInterval)
        guard let receipt = command.action() else {
            cancel() // FFI rejection is not permission to send the next command
            return
        }
        inFlight = receipt
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.cancel()
            self.onTimeout?()
        }
    }

    func cancel() {
        queued.removeAll()
        inFlight = nil
        drainTask?.cancel()
        drainTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

/// Coalesced refresh work. The caller captures and checks account/generation
/// before performing the action; cancel also prevents old timers from firing.
@MainActor
final class PlaybackDeferredRefresh {
    private var task: Task<Void, Never>?
    func schedule(delay: Duration = .milliseconds(1500), _ action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.task = nil
            action()
        }
    }
    func cancel() { task?.cancel(); task = nil }
}

/// Installation-wide service budgets: signing out or recreating a transport
/// cannot escape a cooldown. No account identifiers or credentials are stored.
/// Same-boot time is monotonic. After an OS reboot, conservatively retain the
/// saved remaining duration rather than trusting a changed wall clock.
final class TrafficSafetyStore: @unchecked Sendable {
    static let shared = TrafficSafetyStore(url: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("Nanyin/traffic-safety.json"))

    enum Service: String, Codable { case web, playback }
    private struct Hold: Codable {
        var boot: String
        var uptime: Double
        var duration: Double
        func remaining(boot currentBoot: String, now: Double) -> Double {
            guard boot == currentBoot, now >= uptime else { return duration }
            return max(0, duration - (now - uptime))
        }
        var valid: Bool { !boot.isEmpty && uptime.isFinite && uptime >= 0
            && duration.isFinite && duration >= 0 }
    }
    private struct State: Codable {
        var version = 2
        var cooldowns: [String: Hold] = [:]
        var attempts: [Hold] = []
        var spacing: Hold?
        var recoveryRequired: Bool? = false
        var retryStep: Int? = 0
    }
    enum StoreError: Error { case unavailable }
    private let lock = NSLock()
    private let url: URL?
    private let boot: String
    private let uptime: () -> Double
    private var state = State()
    private var failed = false

    /// nil URL is an isolated, in-memory store for offline tests.
    init(url: URL?, boot: String = TrafficSafetyStore.bootID(),
         uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.url = url
        self.boot = boot
        self.uptime = uptime
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            guard (1...2).contains(state.version),
                  state.version == 1 || (state.recoveryRequired != nil && state.retryStep != nil),
                  (0..<PlaybackReconnectBudget.retryDelays.count).contains(state.retryStep ?? 0),
                  state.cooldowns.values.allSatisfy(\.valid),
                  state.attempts.allSatisfy(\.valid), state.spacing?.valid != false else {
                throw StoreError.unavailable
            }
            if state.version == 1 {
                // V1 counted every launch, even healthy ones. These entries
                // cannot identify failures; migrate only that local budget.
                // Server cooldowns are retained exactly as before.
                state.version = 2
                state.attempts = []
                state.spacing = nil
                state.recoveryRequired = false
                state.retryStep = 0
            }
            // Rebase once per OS boot. Subsequent app launches count elapsed
            // uptime instead of starting the same hold over again.
            let now = uptime()
            func rebase(_ hold: Hold) -> Hold {
                Hold(boot: boot, uptime: now, duration: hold.remaining(boot: boot, now: now))
            }
            state.cooldowns = state.cooldowns.mapValues(rebase)
            state.attempts = state.attempts.map(rebase)
            state.spacing = state.spacing.map(rebase)
            try save()
        } catch { failed = true }
    }

    static func bootID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            return UUID().uuidString // conservative if boot identity is unavailable
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else {
            return UUID().uuidString
        }
        return String(cString: bytes)
    }

    private func save() throws {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            failed = true // never silently discard a failed durable admission
            throw StoreError.unavailable
        }
    }

    func cooldown(_ service: Service) throws -> Double {
        try lock.withLock {
            guard !failed else { throw StoreError.unavailable }
            return state.cooldowns[service.rawValue]?.remaining(boot: boot, now: uptime()) ?? 0
        }
    }

    func recordCooldown(_ service: Service, seconds: Double) throws {
        try lock.withLock {
            guard !failed, seconds.isFinite, seconds >= 0 else { throw StoreError.unavailable }
            let now = uptime()
            let old = state.cooldowns[service.rawValue]?.remaining(boot: boot, now: now) ?? 0
            state.cooldowns[service.rawValue] = Hold(boot: boot, uptime: now, duration: max(old, seconds))
            try save()
        }
    }

    /// Reserve recovery before authentication/handshake. An unfinished attempt
    /// stays marked across relaunch, so a crash or failed init is not a free
    /// normal startup. A successful connection clears only that marker/backoff.
    func connectionWait(admit: Bool, recovery: Bool = false) throws -> PlaybackConnectionWait? {
        try lock.withLock {
            guard !failed else { throw StoreError.unavailable }
            let now = uptime()
            state.attempts.removeAll { $0.remaining(boot: boot, now: now) <= 0 }
            let needsRecovery = recovery || state.recoveryRequired == true
            let cooldown = state.cooldowns[Service.playback.rawValue]?.remaining(boot: boot, now: now) ?? 0
            let spacing = needsRecovery ? (state.spacing?.remaining(boot: boot, now: now) ?? 0) : 0
            let budget = needsRecovery && state.attempts.count >= PlaybackReconnectBudget.limit
                ? (state.attempts.map { $0.remaining(boot: boot, now: now) }.min() ?? 0) : 0
            let delay = max(cooldown, spacing, budget)
            if delay > 0 {
                if admit, recovery, state.recoveryRequired != true {
                    state.recoveryRequired = true
                    try save()
                }
                let reason: PlaybackConnectionWait.Reason = cooldown >= max(spacing, budget)
                    ? .service : (budget >= spacing ? .recoveryBudget : .backoff)
                return PlaybackConnectionWait(reason: reason, deadline: now + delay)
            }
            if admit {
                if needsRecovery {
                    state.attempts.append(Hold(boot: boot, uptime: now, duration: PlaybackReconnectBudget.window))
                }
                state.recoveryRequired = true
                let step = min(state.retryStep ?? 0, PlaybackReconnectBudget.retryDelays.count - 1)
                state.spacing = Hold(boot: boot, uptime: now, duration: PlaybackReconnectBudget.retryDelays[step])
                state.retryStep = min(step + 1, PlaybackReconnectBudget.retryDelays.count - 1)
                try save()
            }
            return nil
        }
    }

    func connectionDelay(admit: Bool, recovery: Bool = false) throws -> Double {
        try connectionWait(admit: admit, recovery: recovery)?.remaining(now: uptime()) ?? 0
    }

    func connectionSucceeded() throws {
        try lock.withLock {
            guard !failed else { throw StoreError.unavailable }
            state.recoveryRequired = false
            state.retryStep = 0
            state.spacing = nil
            // Do not erase recovery history or server-requested holds.
            try save()
        }
    }
}
