import Foundation
import NanyinKit
import Observation

/// Which tracks the listener has starred (saved to Liked Songs), learned in
/// batches for the rows on screen and changed optimistically on a click.
@MainActor
@Observable
final class Stars {
    /// Bumped whenever any answer changes, so tables know to redraw stars.
    private(set) var version = 0
    @ObservationIgnored private var known: [String: Bool] = [:]
    @ObservationIgnored private var wanted: [String] = []
    @ObservationIgnored private var flush: Task<Void, Never>?
    private let api: SpotifyWebAPI

    /// The contains endpoint's batch limit.
    private static let batch = 40

    init(api: SpotifyWebAPI) {
        self.api = api
    }

    /// The answer if known; `hint` is what the row's source already says
    /// (a Liked Songs row is starred).
    func isStarred(_ uri: String, hint: Bool? = nil) -> Bool? {
        known[uri] ?? hint
    }

    /// Asks about `uri` soon, together with the other rows that appear
    /// meanwhile, so scrolling costs one request per screenful at most.
    func need(_ uri: String) {
        guard known[uri] == nil, !wanted.contains(uri), uri.hasPrefix("spotify:track:") else { return }
        wanted.append(uri)
        guard flush == nil else { return }
        flush = Task {
            try? await Task.sleep(for: .milliseconds(300))
            flush = nil
            await lookUp()
        }
    }

    private func lookUp() async {
        while !wanted.isEmpty {
            let uris = Array(wanted.prefix(Self.batch))
            wanted.removeFirst(uris.count)
            // On failure the rows just show no star; they are asked again
            // when they next appear.
            guard let answers = try? await api.libraryContains(uris), answers.count == uris.count else { continue }
            for (uri, starred) in zip(uris, answers) where known[uri] == nil {
                known[uri] = starred
            }
            version += 1
        }
    }

    func toggle(_ uri: String, hint: Bool? = nil) {
        let starred = !(isStarred(uri, hint: hint) ?? false)
        known[uri] = starred
        version += 1
        Task {
            do {
                if starred { try await api.save([uri]) } else { try await api.remove([uri]) }
            } catch {
                known[uri] = !starred
                version += 1
            }
        }
    }

    func reset() {
        flush?.cancel()
        flush = nil
        known = [:]
        wanted = []
        version += 1
    }
}
