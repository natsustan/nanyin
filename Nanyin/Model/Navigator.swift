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
    /// Runs before the new route is shown, so its content can be prepared.
    @ObservationIgnored var willShow: (Route) -> Void = { _ in }

    /// Bumped to put the cursor in the search field.
    private(set) var searchFocusRequests = 0

    func focusSearch() { searchFocusRequests += 1 }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// `replacing` swaps the current entry instead of adding one (a search
    /// refined while typing).
    func go(to route: Route, replacing: Bool = false) {
        guard route != current else { return }
        if !replacing {
            back.append(current)
            forward.removeAll()
        }
        show(route)
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        show(previous)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        show(next)
    }

    func reset() {
        back.removeAll()
        forward.removeAll()
        current = .whatsNew
    }

    private func show(_ route: Route) {
        willShow(route)
        current = route
    }
}
