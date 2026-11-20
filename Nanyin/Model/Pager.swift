import Foundation
import NanyinKit
import Observation

/// Items fetched a page at a time as a list scrolls towards its end. The
/// cursor is whatever the endpoint pages by: an offset, or Spotify's `after`.
@MainActor
@Observable
final class Pager<Item: Sendable, Cursor: Sendable> {
    /// A fetched page and the cursor of the next one (nil at the end).
    typealias Page = (items: [Item], total: Int?, next: Cursor?)

    private(set) var items: [Item] = []
    private(set) var total: Int?
    private(set) var isLoading = false
    private(set) var error: String?
    private var next: Cursor?
    private let fetch: (Cursor) async throws -> Page

    init(first: Cursor, fetch: @escaping (Cursor) async throws -> Page) {
        self.fetch = fetch
        next = first
        loadMore()
    }

    /// A list whose items are already known.
    init(items: [Item]) {
        self.items = items
        total = items.count
        fetch = { _ in ([], nil, nil) }
    }

    /// Loads the next page unless one is loading, all are here, or the last
    /// attempt failed (then only `retry` tries again).
    private func loadMore() {
        guard let cursor = next, !isLoading, error == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let page = try await fetch(cursor)
                items += page.items
                total = page.total
                next = page.items.isEmpty ? nil : page.next
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func retry() {
        error = nil
        loadMore()
    }

    /// Called as items appear: fetches more when the end is near.
    func appeared(_ index: Int) {
        if index >= items.count - 20 { loadMore() }
    }
}

extension Pager where Item == Album, Cursor == Int {
    static func savedAlbums(api: SpotifyWebAPI) -> Pager {
        Pager(first: 0) { offset in
            let page = try await api.savedAlbums(offset: offset)
            return (page.items.map(\.album), page.total, page.next == nil ? nil : offset + page.items.count)
        }
    }
}

extension Pager where Item == Artist, Cursor == String? {
    static func followedArtists(api: SpotifyWebAPI) -> Pager {
        Pager(first: nil) { after in
            let page = try await api.followedArtists(after: after)
            return (page.items, page.total, page.next == nil ? nil : .some(page.cursors?.after))
        }
    }
}
