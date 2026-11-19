import Foundation

/// When to bring the playback session back, and when to stop trying.
///
/// - A session that dropped is replaced at once, but at most `dropLimit`
///   times in `dropWindow`; past that it would only flap, so the user is
///   asked instead.
/// - A connection attempt that failed (not a rejected credential) is retried
///   after a growing delay; the last delay repeats.
public struct ReconnectPolicy: Sendable {
    public static let retryDelays: [TimeInterval] = [5, 15, 60, 120, 300, 600]
    public static let dropWindow: TimeInterval = 600
    public static let dropLimit = 6

    private var drops: [Date] = []
    private var failures = 0

    public init() {}

    /// Records a dropped session. Returns false once drops are exhausted.
    public mutating func sessionDropped(at now: Date = .now) -> Bool {
        drops.removeAll { now.timeIntervalSince($0) >= Self.dropWindow }
        guard drops.count < Self.dropLimit else { return false }
        drops.append(now)
        return true
    }

    /// Records a failed attempt and returns how long to wait before the next.
    public mutating func attemptFailed() -> TimeInterval {
        defer { failures += 1 }
        return Self.retryDelays[min(failures, Self.retryDelays.count - 1)]
    }

    /// A connection succeeded: failures start over. Drops are kept, so a
    /// session that connects and drops again keeps counting.
    public mutating func connected() {
        failures = 0
    }

    /// The user asked to try again: everything starts over.
    public mutating func reset() {
        drops.removeAll()
        failures = 0
    }
}
