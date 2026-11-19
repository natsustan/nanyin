import Foundation
import NanyinCore

/// The Rust core, seen from Swift. One per process.
///
/// Every `connect` starts a new generation; events that arrive for an older
/// one are dropped, so a replaced session can never update the interface.
@MainActor
final class PlaybackEngine {
    static let shared = PlaybackEngine()

    var onEvent: (CoreEvent) -> Void = { _ in }
    private var generation: UInt64 = 0

    private init() {
        nanyin_init({ _, generation, json in
            guard let json else { return }
            let text = String(cString: json)
            // The main queue keeps the core's event order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { PlaybackEngine.shared.receive(generation, text) }
            }
        }, nil)
    }

    func connect(_ config: CoreConfig) {
        guard let json = try? String(data: JSONEncoder().encode(config), encoding: .utf8) else { return }
        generation = json.withCString { nanyin_connect($0) }
    }

    /// Returns false when there is no session to take the command.
    @discardableResult
    func send(_ command: CoreCommand) -> Bool {
        guard let json = try? String(data: JSONEncoder().encode(command), encoding: .utf8) else { return false }
        return json.withCString { nanyin_command($0) } == 0
    }

    func disconnect() {
        generation = 0
        nanyin_disconnect()
    }

    private func receive(_ eventGeneration: UInt64, _ json: String) {
        guard eventGeneration == generation, generation != 0 else { return }
        do {
            onEvent(try JSONDecoder().decode(CoreEvent.self, from: Data(json.utf8)))
        } catch {
            NSLog("Nanyin: undecodable core event %@", json)
        }
    }
}
