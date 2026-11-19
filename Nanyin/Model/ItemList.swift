import Foundation
import NanyinKit
import Observation

/// A grid's items (saved albums, followed artists), fetched a page at a time
/// as the grid scrolls towards the end. Pages are addressed by an opaque
/// cursor: an offset for some endpoints, Spotify's `after` for others.
@MainActor
@Observable
final class ItemList<Item: Identifiable & Sendable> {
    typealias Page = (items: [Item], next: String?)

    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var cursor: String? = ""
    private let fetch: (_ cursor: String) async throws -> Page

    init(fetch: @escaping (_ cursor: String) async throws -> Page) {
        self.fetch = fetch
        loadMore()
    }

    private func loadMore() {
        guard let cursor, !isLoading, error == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let page = try await fetch(cursor)
                items += page.items
                self.cursor = page.items.isEmpty ? nil : page.next
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func retry() {
        error = nil
        loadMore()
    }

    func itemAppeared(_ item: Item) {
        guard let index = items.lastIndex(where: { $0.id == item.id }), index >= items.count - 12 else { return }
        loadMore()
    }
}

extension ItemList where Item == Album {
    static func saved(api: SpotifyWebAPI) -> ItemList {
        ItemList { cursor in
            let offset = Int(cursor) ?? 0
            let page = try await api.savedAlbums(offset: offset)
            return (page.items.map(\.album), page.next == nil ? nil : String(offset + page.items.count))
        }
    }
}

extension ItemList where Item == Artist {
    static func followed(api: SpotifyWebAPI) -> ItemList {
        ItemList { cursor in
            let page = try await api.followedArtists(after: cursor.isEmpty ? nil : cursor)
            return (page.items, page.next == nil ? nil : page.cursors?.after)
        }
    }
}
