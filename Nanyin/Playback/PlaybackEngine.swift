import Foundation
import NanyinCore

/// The Rust core, seen from Swift. One per process; `PlaybackSession` is
/// its only user.
///
/// Every `connect` starts a new generation. Events are delivered on the main
/// queue in order, and any that belong to an older generation are dropped,
/// so a replaced session can never update the interface. Requests are
/// awaited here; a new generation or the session's end fails those pending.
@MainActor
final class PlaybackEngine {
    static let shared = PlaybackEngine()

    var onEvent: (CoreEvent) -> Void = { _ in }
    private var generation: UInt64 = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pending: [UInt64: Pending] = [:]
    private var lastRequest: UInt64 = 0

    private struct Pending {
        let resume: (Result<Data, any Error>) -> Void
        let timeout: Task<Void, Never>
    }

    struct RequestError: LocalizedError {
        let errorDescription: String?
    }

    private init() {
        Self.logURL.path.withCString { nanyin_init(receiveCoreEvent, nil, $0) }
    }

    /// `~/Library/Logs/<app name>/core.log`, rotated by the core at 5 MB.
    static var logURL: URL {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nanyin"
        return URL.libraryDirectory.appending(path: "Logs").appending(path: name).appending(path: "core.log")
    }

    func connect(_ config: CoreConfig) {
        failPending()
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
        failPending()
        nanyin_disconnect()
    }

    /// Asks the core and waits for its answer, decoded as `T`.
    func request<T: Decodable>(_ ask: CoreAsk, timeout: Duration = .seconds(45)) async throws -> T {
        lastRequest += 1
        let request = lastRequest
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            pending[request] = Pending(
                resume: { continuation.resume(with: $0) },
                timeout: Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(request, .failure(RequestError(errorDescription: "Spotify did not answer in time.")))
                })
            let sent = (try? encoder.encode(CoreRequest(request: request, ask: ask)))
                .map { String(decoding: $0, as: UTF8.self).withCString { nanyin_request($0) } == 0 } ?? false
            if !sent {
                finish(request, .failure(RequestError(errorDescription: "Playback is not connected.")))
            }
        }
        let reply = try decoder.decode(CoreReply<T>.self, from: data)
        guard let ok = reply.ok else { throw RequestError(errorDescription: reply.error ?? "Spotify gave no answer.") }
        return ok
    }

    private func finish(_ request: UInt64, _ result: Result<Data, any Error>) {
        guard let entry = pending.removeValue(forKey: request) else { return }
        entry.timeout.cancel()
        entry.resume(result)
    }

    private func failPending() {
        for request in pending.keys {
            finish(request, .failure(RequestError(errorDescription: "The connection to Spotify was reset.")))
        }
    }

    fileprivate func receive(_ eventGeneration: UInt64, _ json: String) {
        guard eventGeneration == generation, generation != 0 else { return }
        let data = Data(json.utf8)
        if let reply = try? decoder.decode(ReplyHeader.self, from: data), reply.type == "reply" {
            return finish(reply.request, .success(data))
        }
        do {
            let event = try decoder.decode(CoreEvent.self, from: data)
            if case .sessionEnded = event { failPending() }
            onEvent(event)
        } catch {
            NSLog("Nanyin: undecodable core event %@", json)
        }
    }
}

/// The core's event callback. Rust calls it on its own worker threads, so it
/// must not be isolated to the main actor: a closure written inside
/// `PlaybackEngine` would inherit `@MainActor`, and Swift 6 checks that
/// isolation on entry (in Release the failed check traps).
private func receiveCoreEvent(_: UnsafeMutableRawPointer?, generation: UInt64, json: UnsafePointer<CChar>?) {
    guard let json else { return }
    let text = String(cString: json)
    DispatchQueue.main.async {
        MainActor.assumeIsolated { PlaybackEngine.shared.receive(generation, text) }
    }
}

private struct CoreRequest: Encodable {
    let request: UInt64
    let ask: CoreAsk

    private enum Key: CodingKey { case request }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(request, forKey: .request)
        try ask.encode(to: encoder)
    }
}

private struct ReplyHeader: Decodable {
    let type: String
    let request: UInt64
}

private struct CoreReply<T: Decodable>: Decodable {
    let ok: T?
    let error: String?
}
