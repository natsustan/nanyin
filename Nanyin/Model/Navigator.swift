import Foundation
import Observation

/// Where the main pane is, with back and forward history like a browser.
enum Route: Hashable {
    case whatsNew
    case queue
    case likedSongs
    case albums
    case artists
    case playlist(id: String)
    case album(id: String)
    case artist(id: String)
    case search(String)
}

extension Route {
    /// The page a `spotify:album:…` or `spotify:artist:…` URI opens.
    init?(uri: String) {
        guard let (kind, id) = Self.parse(uri) else { return nil }
        switch kind {
        case "album": self = .album(id: id)
        case "artist": self = .artist(id: id)
        default: return nil
        }
    }

    /// The open.spotify.com address of a `spotify:kind:id` URI.
    static func webLink(for uri: String) -> String {
        guard let (kind, id) = parse(uri) else { return uri }
        return "https://open.spotify.com/\(kind)/\(id)"
    }

    /// The id of a `spotify:track:…` URI, or nil for anything else.
    static func trackID(_ uri: String) -> String? {
        parse(uri).flatMap { $0.kind == "track" ? $0.id : nil }
    }

    private static func parse(_ uri: String) -> (kind: String, id: String)? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        return (String(parts[1]), String(parts[2]))
    }
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

    /// Drops a page that no longer exists from history, leaving it if shown.
    func forget(_ route: Route) {
        back.removeAll { $0 == route }
        forward.removeAll { $0 == route }
        if current == route { show(.whatsNew) }
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
