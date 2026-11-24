import Foundation
import Network

/// Receives one OAuth redirect on `http://127.0.0.1:<port><path>`.
///
/// `start` returns only once the port is bound, so the browser is never sent
/// to a redirect nobody is listening on. Requests for other paths (a browser
/// asking for a favicon) or stale sign-in tabs with a mismatched `state` are
/// answered cleanly while the receiver keeps waiting for the real redirect.
public final class LoopbackReceiver: @unchecked Sendable {
    public enum Failure: Error, Equatable, LocalizedError {
        case portInUse(UInt16)
        case cancelled
        case timedOut
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .portInUse(let port):
                "Another app is using port \(port), which Spotify sends you back to. Quit it and try again."
            case .cancelled: "Sign-in was cancelled."
            case .timedOut: "Sign-in timed out before Spotify answered. Try again."
            case .failed(let reason): "Could not wait for Spotify's answer (\(reason))."
            }
        }
    }

    public static let defaultTimeout: Duration = .seconds(10 * 60)
    private static let connectionReadTimeout: DispatchTimeInterval = .seconds(5)

    private let listener: NWListener
    private let path: String
    private let expectedState: String?
    private let queue = DispatchQueue(label: "nanyin.loopback")
    private let lock = NSLock()
    private var result: Result<[URLQueryItem], Failure>?
    private var waiter: CheckedContinuation<[URLQueryItem], Error>?

    private init(listener: NWListener, path: String, expectedState: String?) {
        self.listener = listener
        self.path = path
        self.expectedState = expectedState
    }

    public static func start(
        port: UInt16,
        path: String,
        expectedState: String? = nil
    ) async throws -> LoopbackReceiver {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Failure.portInUse(port)
        }
        let receiver = LoopbackReceiver(listener: listener, path: path, expectedState: expectedState)
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

    /// The redirect's query items. Throws `Failure.cancelled` after `cancel()`,
    /// or `Failure.timedOut` if Spotify never answers within `timeout`.
    public func callback(timeout: Duration = LoopbackReceiver.defaultTimeout) async throws -> [URLQueryItem] {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(.timedOut))
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
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
        let done = Once()
        queue.asyncAfter(deadline: .now() + Self.connectionReadTimeout) {
            done.run { connection.cancel() }
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            done.run {
                guard let self else { return connection.cancel() }
                let target = data.flatMap { Self.requestTarget(in: $0) }
                guard let target, let components = URLComponents(string: target), components.path == self.path else {
                    Self.respond(
                        connection,
                        status: "404 Not Found",
                        html: Self.htmlPage(
                            title: "Nanyin",
                            heading: "Not Found",
                            body: "This address is reserved for Spotify sign-in.",
                            accent: "#8A8A8A",
                            success: false,
                            autoClose: false))
                    return
                }
                let items = components.queryItems ?? []
                let value = { (name: String) in items.first { $0.name == name }?.value }
                let state = value("state")
                let error = value("error")
                let code = value("code")

                // Ignore stale browser tabs or stray visits whose state doesn't match this flow.
                if let expectedState = self.expectedState {
                    if state != expectedState {
                        Self.respond(
                            connection,
                            status: "400 Bad Request",
                            html: Self.htmlPage(
                                title: "Outdated Sign-In",
                                heading: "This sign-in tab is out of date",
                                body: "A newer sign-in is waiting in Nanyin. You can close this tab.",
                                accent: "#E07A5F",
                                success: false,
                                autoClose: false))
                        return
                    }
                    if error == nil && code == nil {
                        Self.respond(
                            connection,
                            status: "400 Bad Request",
                            html: Self.htmlPage(
                                title: "Incomplete Sign-In",
                                heading: "Sign-in didn't complete",
                                body: "Spotify did not return an authorization code. Return to Nanyin and try again.",
                                accent: "#E07A5F",
                                success: false,
                                autoClose: false))
                        return
                    }
                }

                if error != nil {
                    Self.respond(
                        connection,
                        status: "200 OK",
                        html: Self.htmlPage(
                            title: "Sign-In Cancelled",
                            heading: "Nanyin was not authorized",
                            body: "You can close this tab and return to Nanyin.",
                            accent: "#E07A5F",
                            success: false,
                            autoClose: true))
                } else {
                    Self.respond(
                        connection,
                        status: "200 OK",
                        html: Self.htmlPage(
                            title: "Signed In to Nanyin",
                            heading: "You're signed in",
                            body: "Returning to Nanyin. You can close this tab if it stays open.",
                            accent: "#84BD00",
                            success: true,
                            autoClose: true))
                }
                self.finish(.success(items))
            }
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

    private static func htmlPage(
        title: String,
        heading: String,
        body: String,
        accent: String,
        success: Bool,
        autoClose: Bool
    ) -> String {
        let iconPath = success
            ? "M9.5 16.5L5 12l1.4-1.4 3.1 3.1 8.1-8.1L19 7z"
            : "M18.3 5.7L12 12l6.3 6.3-1.4 1.4L10.6 13.4 4.3 19.7 2.9 18.3 9.2 12 2.9 5.7 4.3 4.3l6.3 6.3 6.3-6.3z"
        let script = autoClose ? "<script>setTimeout(function(){window.close()},1500)</script>" : ""
        return """
        <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title>\
        <style>:root{color-scheme:dark}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#242424;color:#e2e2e2;font-family:"Lucida Grande",-apple-system,sans-serif}\
        main{max-width:26rem;padding:2.25rem 2.5rem;border-radius:12px;background:#323232;border:1px solid #1c1c1c;box-shadow:0 18px 48px rgba(0,0,0,.45);text-align:center}\
        .mark{width:54px;height:54px;border-radius:50%;background:\(accent);display:grid;place-items:center;margin:0 auto 1.15rem;box-shadow:inset 0 1px 0 rgba(255,255,255,.35)}\
        .mark svg{width:26px;height:26px;fill:#1b1b1b}h1{font-size:1.25rem;margin:.2rem 0 .5rem;font-weight:700}p{color:#a8a8a8;font-size:.9rem;line-height:1.5;margin:0}</style>\
        <main><div class="mark"><svg viewBox="0 0 24 24"><path d="\(iconPath)"/></svg></div>\
        <h1>\(heading)</h1><p>\(body)</p></main>\(script)</html>
        """
    }

    private static func respond(_ connection: NWConnection, status: String, html: String) {
        let response = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Cache-Control: no-store\r\n"
            + "Content-Length: \(html.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
            + html
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
