import Foundation
import Observation

/// Where the main pane is, with back and forward history like a browser.
enum Route: Hashable {
    case whatsNew
    case queue
    case likedSongs
    case albums
    case artists
    case playlist(id: String, name: String)
    case album(id: String)
    case artist(id: String)
    case search(String)
}

@MainActor
@Observable
final class Navigator {
    private(set) var current: Route = .whatsNew
    private var back: [Route] = []
    private var forward: [Route] = []

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func go(to route: Route) {
        guard route != current else { return }
        // Typing a search replaces the search page instead of stacking up
        // one history entry per keystroke.
        if case .search = route, case .search = current {
            current = route
            return
        }
        back.append(current)
        forward.removeAll()
        current = route
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}
