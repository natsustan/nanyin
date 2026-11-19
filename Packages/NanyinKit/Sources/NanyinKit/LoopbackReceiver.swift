import Foundation
import Network

/// Receives one OAuth redirect on `http://127.0.0.1:<port><path>`.
///
/// `start` returns only once the port is bound, so the browser is never sent
/// to a redirect nobody is listening on. Requests for other paths (a browser
/// asking for a favicon) are answered 404 and the receiver keeps waiting.
public final class LoopbackReceiver: @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case portInUse(UInt16)
        case cancelled
        case failed(String)
    }

    private let listener: NWListener
    private let path: String
    private let queue = DispatchQueue(label: "nanyin.loopback")
    private let lock = NSLock()
    private var result: Result<[URLQueryItem], Failure>?
    private var waiter: CheckedContinuation<[URLQueryItem], Error>?

    private init(listener: NWListener, path: String) {
        self.listener = listener
        self.path = path
    }

    public static func start(port: UInt16, path: String) async throws -> LoopbackReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Failure.portInUse(port)
        }
        let receiver = LoopbackReceiver(listener: listener, path: path)
        try await receiver.waitUntilReady(port: port)
        return receiver
    }

    private func waitUntilReady(port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error):
                    self?.finish(.failure(.failed(error.localizedDescription)))
                    once.run {
                        if case .posix(let code) = error, code == .EADDRINUSE {
                            continuation.resume(throwing: Failure.portInUse(port))
                        } else {
                            continuation.resume(throwing: Failure.failed(error.localizedDescription))
                        }
                    }
                case .cancelled:
                    once.run { continuation.resume(throwing: Failure.cancelled) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// The redirect's query items. Throws `Failure.cancelled` after `cancel()`.
    public func callback() async throws -> [URLQueryItem] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result.mapError { $0 as Error })
                } else {
                    waiter = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            cancel()
        }
    }

    public func cancel() {
        finish(.failure(.cancelled))
    }

    private func finish(_ outcome: Result<[URLQueryItem], Failure>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        listener.cancel()
        waiter?.resume(with: outcome.mapError { $0 as Error })
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let target = data.flatMap { Self.requestTarget(in: $0) }
            guard let target, let components = URLComponents(string: target), components.path == self.path else {
                Self.respond(connection, status: "404 Not Found", body: "Not found")
                return
            }
            let items = components.queryItems ?? []
            let denied = items.contains { $0.name == "error" }
            Self.respond(
                connection,
                status: "200 OK",
                body: denied
                    ? "Nanyin was not authorized. You can close this window."
                    : "Nanyin is signed in. You can close this window and return to the app."
            )
            self.finish(.success(items))
        }
    }

    /// The target of an HTTP `GET` request line.
    static func requestTarget(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\r\n", maxSplits: 1).first
        else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private static func respond(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=utf-8><title>Nanyin</title>"
            + "<body style=\"font:15px -apple-system;margin:3em\">\(body)</body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Runs a closure at most once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
