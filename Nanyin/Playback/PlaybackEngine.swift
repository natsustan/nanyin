import Foundation
import NanyinCore

/// The Rust core, seen from Swift. One per process; `PlaybackSession` is
/// its only user.
///
/// Every `connect` starts a new generation. Events are delivered on the main
/// queue in order, and any that belong to an older generation are dropped,
/// so a replaced session can never update the interface.
@MainActor
final class PlaybackEngine {
    static let shared = PlaybackEngine()

    var onEvent: (CoreEvent) -> Void = { _ in }
    private var generation: UInt64 = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        nanyin_init({ _, generation, json in
            guard let json else { return }
            let text = String(cString: json)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { PlaybackEngine.shared.receive(generation, text) }
            }
        }, nil)
    }

    func connect(_ config: CoreConfig) {
        guard let json = try? String(decoding: encoder.encode(config), as: UTF8.self) else { return }
        generation = json.withCString { nanyin_connect($0) }
    }

    /// Returns false when there is no session to take the command.
    func send(_ command: CoreCommand) -> Bool {
        guard let json = try? String(decoding: encoder.encode(command), as: UTF8.self) else { return false }
        return json.withCString { nanyin_command($0) } == 0
    }

    func disconnect() {
        generation = 0
        nanyin_disconnect()
    }

    private func receive(_ eventGeneration: UInt64, _ json: String) {
        guard eventGeneration == generation, generation != 0 else { return }
        do {
            onEvent(try decoder.decode(CoreEvent.self, from: Data(json.utf8)))
        } catch {
            NSLog("Nanyin: undecodable core event %@", json)
        }
    }
}
