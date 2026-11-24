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
    private let first: Cursor?
    private var next: Cursor?
    private var generation = 0
    private var pagesLoaded = 0
    private let fetch: (Cursor) async throws -> Page

    var hasMore: Bool { next != nil }

    init(first: Cursor, fetch: @escaping (Cursor) async throws -> Page) {
        self.first = first
        self.fetch = fetch
        next = first
        loadMore()
    }

    /// A list whose items are already known.
    init(items: [Item]) {
        self.first = nil
        self.items = items
        total = items.count
        fetch = { _ in ([], nil, nil) }
    }

    /// Loads the next page unless one is loading, all are here, or the last
    /// attempt failed (then only `retry` tries again).
    private func loadMore() {
        guard let cursor = next, !isLoading, error == nil else { return }
        isLoading = true
        let currentGeneration = generation
        Task {
            do {
                let page = try await fetch(cursor)
                guard generation == currentGeneration else { return }
                items += page.items
                total = page.total
                next = page.next
                pagesLoaded += 1
                isLoading = false
                // A page can come back empty yet not be the last (a Web API
                // playlist page of removed songs); no row will appear to ask
                // for more.
                if page.items.isEmpty { loadMore() }
            } catch {
                guard generation == currentGeneration else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func retry() {
        error = nil
        loadMore()
    }

    /// Discards loaded pages and fetches again from the beginning.
    func reload() {
        guard let first else { return }
        generation += 1
        pagesLoaded = 0
        items = []
        total = nil
        error = nil
        isLoading = false
        next = first
        loadMore()
    }

    func loadNext() {
        loadMore()
    }

    struct Removal {
        fileprivate let entries: [(index: Int, item: Item)]
        fileprivate let generation: Int
        fileprivate let pagesLoaded: Int

        var removedItems: [Item] { entries.map(\.item) }
    }

    /// Optimistically removes matching items, returning a rollback token that
    /// reinserts only the removed entries so pages loaded meanwhile stay intact.
    func remove(where shouldRemove: (Item) -> Bool) -> Removal {
        var removed: [(Int, Item)] = []
        var kept: [Item] = []
        kept.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if shouldRemove(item) {
                removed.append((index, item))
            } else {
                kept.append(item)
            }
        }
        items = kept
        if let total { self.total = max(0, total - removed.count) }
        return Removal(entries: removed, generation: generation, pagesLoaded: pagesLoaded)
    }

    func wasReloaded(since removal: Removal) -> Bool {
        generation != removal.generation
    }

    func restore(_ removal: Removal, where shouldRestore: (Item) -> Bool = { _ in true }) {
        guard generation == removal.generation else { return }
        var restored = 0
        var skipped = 0
        for (index, item) in removal.entries {
            if shouldRestore(item) {
                items.insert(item, at: min(max(0, index - skipped), items.count))
                restored += 1
            } else {
                skipped += 1
            }
        }
        guard restored > 0 else { return }
        if let total {
            self.total = pagesLoaded == removal.pagesLoaded
                ? total + restored
                : max(total, items.count)
        }
    }

    struct Snapshot {
        fileprivate let items: [Item]
        fileprivate let generation: Int
        fileprivate let pagesLoaded: Int
    }

    func snapshot() -> Snapshot {
        Snapshot(items: items, generation: generation, pagesLoaded: pagesLoaded)
    }

    func replaceItems(_ updated: [Item]) {
        items = updated
    }

    /// Restores the pre-move prefix while preserving any pages fetched while
    /// the reorder request was in flight.
    func restore(_ snapshot: Snapshot) {
        guard generation == snapshot.generation else { return }
        if pagesLoaded == snapshot.pagesLoaded {
            items = snapshot.items
        } else if items.count >= snapshot.items.count {
            items = snapshot.items + items.dropFirst(snapshot.items.count)
        } else {
            reload()
        }
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
