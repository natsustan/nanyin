import Foundation
import NanyinKit
import Observation

/// Which tracks the listener has starred (saved to Liked Songs). Asking
/// about an unknown track looks it up soon, batched with the other tracks
/// drawn meanwhile; a toggle shows at once and reverts if Spotify refuses.
@MainActor
@Observable
final class Stars {
    /// Bumped whenever any answer changes, so tables know to redraw stars.
    private(set) var version = 0
    @ObservationIgnored private var known: [String: Bool] = [:]
    /// Asked about since the last lookup, oldest first.
    @ObservationIgnored private var wanted: [String] = []
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var flush: Task<Void, Never>?
    private let api: SpotifyWebAPI

    /// The contains endpoint's batch limit.
    private static let batch = 40

    init(api: SpotifyWebAPI) {
        self.api = api
    }

    /// The answer if known; otherwise nil, and the answer is on its way.
    func isStarred(_ uri: String) -> Bool? {
        if let answer = known[uri] { return answer }
        want(uri)
        return nil
    }

    /// Records answers that came with other data (Liked Songs rows).
    func learn(_ uris: [String], starred: Bool) {
        for uri in uris { known[uri] = starred }
        version += 1
    }

    func toggle(_ uri: String) {
        let starred = !(known[uri] ?? false)
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
        pending = []
        version += 1
    }

    /// Waits for scrolling to settle, then asks only about the tracks drawn
    /// last (what is on screen); the others are asked again if they return.
    private func want(_ uri: String) {
        guard uri.hasPrefix("spotify:track:"), pending.insert(uri).inserted else { return }
        wanted.append(uri)
        flush?.cancel()
        flush = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let uris = Array(wanted.suffix(Self.batch * 2))
            pending.subtract(wanted.dropLast(uris.count))
            wanted = []
            await lookUp(uris)
        }
    }

    private func lookUp(_ uris: [String]) async {
        for start in stride(from: 0, to: uris.count, by: Self.batch) {
            let batch = Array(uris[start ..< min(start + Self.batch, uris.count)])
            let answers = try? await api.libraryContains(batch)
            if let answers, answers.count == batch.count {
                for (uri, starred) in zip(batch, answers) where known[uri] == nil {
                    known[uri] = starred
                }
                version += 1
            }
        }
        // Whatever was not answered may be asked again when drawn again.
        pending.subtract(uris)
    }
}
