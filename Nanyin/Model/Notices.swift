import Observation

/// The one place a failed action reports to; the notice strip shows the
/// latest report over the standing playback state until it is dismissed.
@MainActor
@Observable
final class Notices {
    private(set) var message: String?

    func report(_ message: String) { self.message = message }
    func dismiss() { message = nil }
}
