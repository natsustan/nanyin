import Foundation

private final class MockSpotify: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [(Int, String?)] = []
    nonisolated(unsafe) private static var requests = 0

    static func reset(_ replies: [(Int, String?)]) {
        lock.withLock { responses = replies; requests = 0 }
    }
    static var count: Int { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock {
            Self.requests += 1
            return Self.responses.isEmpty ? (200, nil) : Self.responses.removeFirst()
        }
        let headers = reply.1.map { ["Retry-After": $0] }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0,
                                       httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"id\":\"offline-test\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class DelayedSpotify: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var calls = 0
    nonisolated(unsafe) private static var active = 0
    nonisolated(unsafe) private static var peak = 0
    nonisolated(unsafe) private static var delay: Double = 0.3
    private let stateLock = NSLock()
    private var finished = false
    private var work: DispatchWorkItem?
    static func reset(delay: Double = 0.3) {
        lock.withLock { assert(active == 0); calls = 0; peak = 0; self.delay = delay }
    }
    static var counts: (calls: Int, active: Int, peak: Int) { lock.withLock { (calls, active, peak) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let delay = Self.lock.withLock {
            Self.calls += 1; Self.active += 1; Self.peak = max(Self.peak, Self.active)
            return Self.delay
        }
        let work = DispatchWorkItem { [self] in
            guard finish() else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("ok".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        stateLock.withLock { self.work = work }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func finish() -> Bool {
        let first = stateLock.withLock { if finished { return false }; finished = true; return true }
        if first { Self.lock.withLock { Self.active -= 1 } }
        return first
    }
    override func stopLoading() {
        stateLock.withLock { work?.cancel() }
        _ = finish()
    }
}

@main
private enum PlaybackTrafficTests {
    static func main() async throws {
        try testPersistence()
        try await testCommandBursts()
        try await testWebCooldown()
        try await testWebConcurrency()
        print("Playback traffic tests passed")
    }

    private static func check(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
        assert(value, file: file, line: line)
    }

    private static func testPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("limits.json")
        var now: Double = 1000
        var store = TrafficSafetyStore(url: url, boot: "boot-one", uptime: { now })

        // Healthy launches never consume recovery capacity, even rapid rebuilds.
        for _ in 0..<20 {
            check(try store.connectionDelay(admit: true) == 0)
            try store.connectionSucceeded()
            store = TrafficSafetyStore(url: url, boot: "boot-one", uptime: { now })
        }
        // Six genuinely dropped sessions may recover. Success must not erase
        // their history, or short-lived dealer connections could loop forever.
        for _ in 0..<6 {
            check(try store.connectionDelay(admit: true, recovery: true) == 0)
            try store.connectionSucceeded()
            now += 1
        }
        // A healthy relaunch remains free even with a full recovery history.
        check(try store.connectionDelay(admit: true) == 0)
        try store.connectionSucceeded()
        let blockedRecovery = try store.connectionWait(admit: true, recovery: true)
        check(blockedRecovery?.reason == .recoveryBudget)
        check(blockedRecovery?.remaining(now: now) == 594)
        store = TrafficSafetyStore(url: url, boot: "boot-one", uptime: { now })
        check(try store.connectionDelay(admit: true) == 594)
        now += 10
        check(try store.connectionDelay(admit: false) == 584)
        // OS reboot retains the last saved remaining hold conservatively;
        // the next same-boot relaunch ages it instead of resetting it again.
        let reboot = TrafficSafetyStore(url: url, boot: "boot-two", uptime: { now })
        check(try reboot.connectionDelay(admit: false) == 594)
        now += 10
        let relaunched = TrafficSafetyStore(url: url, boot: "boot-two", uptime: { now })
        check(try relaunched.connectionDelay(admit: false) == 584)
        now += 584
        check(try relaunched.connectionDelay(admit: true) == 0)

        // A failed or interrupted first startup is not a fresh free attempt
        // after restarting; retries use 5/15/60/120/300/600 second backoff.
        let failureURL = directory.appendingPathComponent("failure.json")
        now = 2000
        var failed = TrafficSafetyStore(url: failureURL, boot: "boot-one", uptime: { now })
        check(try failed.connectionDelay(admit: true) == 0)
        for delay in [5.0, 15, 60, 120, 300, 600] {
            failed = TrafficSafetyStore(url: failureURL, boot: "boot-one", uptime: { now })
            let waiting = try failed.connectionWait(admit: false)
            check(waiting?.reason == .backoff)
            check(waiting?.remaining(now: now) == delay)
            check(try failed.connectionDelay(admit: true) == delay)
            now += delay
            check(try failed.connectionDelay(admit: true) == 0)
        }
        try failed.connectionSucceeded()
        check(try failed.connectionDelay(admit: false) == 0)

        // Service holds override both normal startup and recovery, survive
        // success/sign-out/relaunch, and cannot be shortened by a smaller 429.
        try failed.recordCooldown(.web, seconds: 86400)
        try failed.recordCooldown(.playback, seconds: 120)
        try failed.connectionSucceeded()
        now += 10
        failed = TrafficSafetyStore(url: failureURL, boot: "boot-one", uptime: { now })
        check(try failed.cooldown(.web) == 86390)
        check(try failed.connectionWait(admit: true)?.reason == .service)
        check(try failed.connectionDelay(admit: true) == 110)
        try failed.recordCooldown(.playback, seconds: 1)
        check(try failed.connectionDelay(admit: false) == 110)
        now += 110
        check(try failed.connectionDelay(admit: true) == 0)

        // V1 entries mixed healthy startups with failures. Migrate those local
        // counters once, preserving the server's full Web/playback holds.
        now = 1000
        let legacy = #"{"version":1,"cooldowns":{"web":{"boot":"boot-one","uptime":1000,"duration":86400},"playback":{"boot":"boot-one","uptime":1000,"duration":120}},"attempts":[{"boot":"boot-one","uptime":1000,"duration":600},{"boot":"boot-one","uptime":1000,"duration":600},{"boot":"boot-one","uptime":1000,"duration":600}],"spacing":{"boot":"boot-one","uptime":1000,"duration":30}}"#
        try Data(legacy.utf8).write(to: url)
        let migrated = TrafficSafetyStore(url: url, boot: "boot-one", uptime: { now })
        check(try migrated.connectionDelay(admit: true) == 120)
        check(try migrated.cooldown(.web) == 86400)
        now += 120
        check(try migrated.connectionDelay(admit: true) == 0)
        try migrated.connectionSucceeded()
        for _ in 0..<6 {
            check(try migrated.connectionDelay(admit: true, recovery: true) == 0)
            try migrated.connectionSucceeded()
        }
        check(try migrated.connectionDelay(admit: true, recovery: true) == 600)
        let migratedAgain = TrafficSafetyStore(url: url, boot: "boot-one", uptime: { now })
        check(try migratedAgain.connectionDelay(admit: true) == 600)

        let notice = PlaybackConnectionWait(reason: .recoveryBudget, deadline: 1411)
        check(notice.message(now: 1000).contains("6m 51s"))
        check(notice.message(now: 1410).contains("1s"))
        check(notice.message(now: 1411) == "Playback can reconnect — click Retry")
        check(notice.remaining(now: 1500) == 0)
        let longHold = PlaybackConnectionWait(reason: .service, deadline: 1e100)
        check(longHold.message(now: 0).contains("days"))

        // Corrupt/unwritable persistence must never admit untracked traffic.
        try Data("corrupt".utf8).write(to: url)
        let corrupt = TrafficSafetyStore(url: url, boot: "boot-two", uptime: { now })
        do { _ = try corrupt.connectionDelay(admit: true); assertionFailure("corrupt store admitted") }
        catch TrafficSafetyStore.StoreError.unavailable {}
        let blocked = TrafficSafetyStore(url: url.appendingPathComponent("child"), boot: "test")
        do { _ = try blocked.connectionDelay(admit: true); assertionFailure("unwritable store admitted") }
        catch TrafficSafetyStore.StoreError.unavailable {}
    }

    /// Positive async assertions wait for their observable event, not a 10ms
    /// scheduler assumption. Failure still has a bounded deadline.
    @MainActor private static func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        assert(predicate(), "Expected async event did not arrive")
    }

    @MainActor private static func testCommandBursts() async throws {
        let commands = PlaybackCommandQueue(minimumInterval: .milliseconds(10), timeout: .seconds(5))
        var sent: [Int] = []
        var current: UInt64 = 0
        for index in 0..<100 {
            commands.submit(kind: .selection) {
                sent.append(index)
                return .init(previousRequestID: current, expectedURI: "track-\(index)")
            }
        }
        assert(sent == [0], "first click starts immediately")
        commands.acknowledge(uri: "track-0", requestID: 0) // stale
        commands.acknowledge(uri: "wrong-track", requestID: 1)
        try await Task.sleep(for: .milliseconds(20))
        assert(sent == [0], "old/wrong events must not release a queued command")
        current = 1
        commands.acknowledge(uri: "track-0", requestID: current)
        try await eventually { sent == [0, 99] }
        assert(sent == [0, 99], "only the latest pending selection is dispatched")
        commands.cancel()
        let skips = PlaybackCommandQueue(minimumInterval: .milliseconds(5), timeout: .seconds(5))
        sent = []
        current = 10
        for index in 0..<3 {
            skips.submit(kind: .next) {
                sent.append(index)
                return .init(previousRequestID: current)
            }
        }
        assert(sent == [0])
        for expected in 2...3 {
            current += 1
            skips.acknowledge(uri: "new", requestID: current)
            try await eventually { sent.count == expected }
            assert(sent.count == expected, "relative skips must survive the burst")
        }
        skips.submit(kind: .next) { sent.append(999); return .init(previousRequestID: current) }
        skips.cancel() // pause, takeover, sign-out, disconnect, generation replacement
        skips.acknowledge(uri: "new", requestID: current + 1)
        try await Task.sleep(for: .milliseconds(20))
        assert(sent == [0, 1, 2])
        let previous = PlaybackCommandQueue(minimumInterval: .zero, timeout: .seconds(5))
        var count = 0
        for _ in 0..<2 {
            previous.submit(kind: .previous) {
                count += 1
                return .init(previousRequestID: 44, acceptsSeek: count == 1)
            }
        }
        previous.acknowledge(uri: nil, requestID: 43, seekPosition: 0)
        previous.acknowledge(uri: nil, requestID: 44, seekPosition: 1000)
        assert(count == 1)
        previous.acknowledge(uri: nil, requestID: 44, seekPosition: 0)
        try await eventually { count == 2 }
        assert(count == 2, "previous-to-zero confirms without changing track ID")
        previous.submit(kind: .next) { count += 1; return .init(previousRequestID: 45) }
        previous.acknowledge(uri: nil, requestID: 44, seekPosition: 0)
        try await Task.sleep(for: .milliseconds(10))
        assert(count == 2, "a late seek must not confirm the next Previous track transition")
        previous.cancel()
        let stalled = PlaybackCommandQueue(minimumInterval: .zero, timeout: .milliseconds(30))
        var timedOut = false
        var calls = 0
        stalled.onTimeout = { timedOut = true }
        var accepted = 0
        for _ in 0..<100 {
            if stalled.submit(kind: .next, { calls += 1; return .init(previousRequestID: 1) }) { accepted += 1 }
        }
        assert(accepted == 1 + PlaybackCommandQueue.maximumPending)
        try await eventually { timedOut }
        stalled.acknowledge(uri: nil, requestID: 2)
        try await Task.sleep(for: .milliseconds(10))
        assert(timedOut && calls == 1, "missing confirmation drops the queue; no replay")
        let paused = PlaybackCommandQueue(minimumInterval: .milliseconds(5), timeout: .seconds(5))
        var pausedCalls = 0
        for _ in 0..<2 {
            paused.submit(kind: .selection) { pausedCalls += 1; return .init(previousRequestID: 10) }
        }
        paused.acknowledge(uri: "track", requestID: 11, paused: true)
        paused.acknowledge(uri: "track", requestID: 11)
        try await Task.sleep(for: .milliseconds(20))
        assert(pausedCalls == 1, "remote pause cannot release a queued selection")
        let pauseBetween = PlaybackCommandQueue(minimumInterval: .milliseconds(30), timeout: .seconds(5))
        var betweenCalls = 0
        for _ in 0..<2 {
            pauseBetween.submit(kind: .next) { betweenCalls += 1; return .init(previousRequestID: 20) }
        }
        pauseBetween.acknowledge(uri: "track", requestID: 21)
        pauseBetween.acknowledge(uri: "track", requestID: 21, paused: true)
        try await Task.sleep(for: .milliseconds(50))
        assert(betweenCalls == 1, "pause cancels a command waiting for its minimum dispatch interval")
        let pausedSkip = PlaybackCommandQueue(minimumInterval: .milliseconds(5), timeout: .seconds(5))
        var pausedSkips = 0
        for _ in 0..<2 {
            pausedSkip.submit(kind: .next) {
                pausedSkips += 1
                return .init(previousRequestID: 30, acceptsPaused: true)
            }
        }
        pausedSkip.acknowledge(uri: "track", requestID: 31, paused: true)
        try await eventually { pausedSkips == 2 }
        assert(pausedSkips == 2, "intentional skips while already paused still confirm")
        pausedSkip.cancel()
        let refresh = PlaybackDeferredRefresh()
        var refreshes = 0
        for _ in 0..<100 { refresh.schedule(delay: .milliseconds(10)) { refreshes += 1 } }
        try await eventually { refreshes == 1 }
        assert(refreshes == 1)
        refresh.schedule(delay: .milliseconds(10)) { refreshes += 1 }
        refresh.cancel()
        try await Task.sleep(for: .milliseconds(30))
        assert(refreshes == 1, "account/generation cancellation must discard delayed refreshes")
    }

    private static func testWebConcurrency() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedSpotify.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let gate = SpotifyRequestGate(limit: 2)
        let transport = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil), gate: gate)
        let request = URLRequest(url: URL(string: "https://offline.invalid/shared")!)
        DelayedSpotify.reset()
        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<12 { group.addTask { try await transport.send(request) } }
            for try await result in group { assert(result == Data("ok".utf8)) }
        }
        assert(DelayedSpotify.counts.calls == 1, "identical reads share one actual request")
        DelayedSpotify.reset(delay: 0.6)
        try await withThrowingTaskGroup(of: Data.self) { group in
            for index in 0..<8 {
                var distinct = request
                distinct.url = URL(string: "https://offline.invalid/item/\(index)")!
                let value = distinct
                group.addTask { try await transport.send(value) }
            }
            for try await _ in group {}
        }
        assert(DelayedSpotify.counts.calls == 8 && DelayedSpotify.counts.peak == 2)
        DelayedSpotify.reset()
        var write = request; write.httpMethod = "PUT"
        let mutation = write
        async let firstWrite = transport.send(mutation)
        async let secondWrite = transport.send(mutation)
        _ = try await (firstWrite, secondWrite)
        assert(DelayedSpotify.counts.calls == 2, "writes must never be deduplicated")
        DelayedSpotify.reset()
        var changedToken = request; changedToken.setValue("offline-token", forHTTPHeaderField: "Authorization")
        let tokenRequest = changedToken
        async let oldToken = transport.send(request)
        async let newToken = transport.send(tokenRequest)
        _ = try await (oldToken, newToken)
        assert(DelayedSpotify.counts.calls == 2, "different authorization must not share a result")
        DelayedSpotify.reset()
        let survivor = Task { try await transport.send(request) }
        let cancelled = Task { try await transport.send(request) }
        try await Task.sleep(for: .milliseconds(60))
        cancelled.cancel()
        do { _ = try await cancelled.value; assertionFailure("cancelled waiter succeeded") }
        catch is CancellationError {}
        _ = try await survivor.value
        assert(DelayedSpotify.counts.calls == 1, "one cancellation must not abort another caller's read")
        DelayedSpotify.reset(delay: 0.5)
        let singleSlot = SpotifyRequestGate(limit: 1)
        let active = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil), gate: singleSlot)
        let queued = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil), gate: singleSlot)
        let inFlight = Task { try await active.send(request) }
        // Wait for the first actual request so the second is definitely queued.
        for _ in 0..<50 {
            if DelayedSpotify.counts.calls == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = Task { try await queued.send(request) }
        try await Task.sleep(for: .milliseconds(30))
        queued.invalidate()
        do { _ = try await pending.value; assertionFailure("invalidated queued request succeeded") }
        catch is CancellationError {}
        active.invalidate()
        do { _ = try await inFlight.value; assertionFailure("invalidated active request succeeded") }
        catch is CancellationError {}
        for _ in 0..<50 {
            if DelayedSpotify.counts.active == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        assert(DelayedSpotify.counts.calls == 1 && DelayedSpotify.counts.active == 0)
        // Cancelled permits must be reusable, including by a replacement account.
        let replacement = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil), gate: singleSlot)
        _ = try await replacement.send(request)
        assert(DelayedSpotify.counts.calls == 2)
    }

    private static func testWebCooldown() async throws {
        assert(SpotifyWebTransport.retryAfter("120") == 120)
        assert(SpotifyWebTransport.retryAfter("86400") == 86400)
        assert(SpotifyWebTransport.retryAfter("NaN") == 5)
        assert(SpotifyWebTransport.retryAfter("-10") == 5)
        assert(SpotifyWebTransport.retryAfter(nil) == 5)
        assert(SpotifyWebTransport.retryAfter("Thu, 01 Jan 1970 00:02:00 GMT",
                                             now: Date(timeIntervalSince1970: 0)) == 120)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSpotify.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://offline.invalid/test")!)
        let transport = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil))
        MockSpotify.reset([(429, "120")])
        await expectHTTP(429) { _ = try await transport.send(request, retries: 0) }
        // A refreshed token cannot escape the same account's cooldown.
        let refreshed = SpotifyClient(accessToken: "offline-new-token", transport: transport)
        await expectHTTP(429) { _ = try await refreshed.currentUser() }
        assert(MockSpotify.count == 1)
        transport.invalidate()
        do {
            _ = try await transport.send(request)
            assertionFailure("invalidated session sent a request")
        } catch is CancellationError {} catch { assertionFailure("wrong error: \(error)") }
        assert(MockSpotify.count == 1)
        // An isolated installation has a separate quota. Within one installation,
        // replacing a transport/account or relaunching retains the service hold.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("web.json")
        let store = TrafficSafetyStore(url: url)
        MockSpotify.reset([(429, "120")])
        let oldAccount = SpotifyWebTransport(session: session, safetyStore: store)
        await expectHTTP(429) { _ = try await oldAccount.send(request, retries: 0) }
        oldAccount.invalidate()
        let newAccount = SpotifyWebTransport(session: session, safetyStore: store)
        await expectHTTP(429) { _ = try await newAccount.send(request) }
        let relaunched = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: url))
        await expectHTTP(429) { _ = try await relaunched.send(request) }
        assert(MockSpotify.count == 1, "relaunch/account change must not send during cooldown")
        for status in [401, 403, 500] {
            MockSpotify.reset([(status, nil)])
            do {
                _ = try await SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil)).send(request)
                assertionFailure("error was swallowed")
            } catch {}
            assert(MockSpotify.count == 1, "ambiguous failures must not be replayed")
        }
        // Exhausting the last retry must still install a shared deadline.
        MockSpotify.reset([(429, "1"), (429, "120")])
        let bounded = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil))
        await expectHTTP(429) { _ = try await bounded.send(request, retries: 1) }
        await expectHTTP(429) { _ = try await bounded.send(request) }
        assert(MockSpotify.count == 2)
        // Cancellation while waiting must not turn into a later request.
        MockSpotify.reset([(200, nil)])
        let paced = SpotifyWebTransport(session: session, safetyStore: TrafficSafetyStore(url: nil))
        _ = try await paced.send(request)
        let pending = Task { try await paced.send(request) }
        pending.cancel()
        do { _ = try await pending.value; assertionFailure("cancelled request succeeded") }
        catch is CancellationError {} catch { assertionFailure("wrong error: \(error)") }
        assert(MockSpotify.count == 1)
    }

    private static func expectHTTP(_ status: Int, _ action: () async throws -> Void) async {
        do { try await action(); assertionFailure("expected HTTP \(status)") }
        catch SpotifyClient.APIError.http(let actual, _) { assert(actual == status) }
        catch { assertionFailure("unexpected error: \(error)") }
    }
}
