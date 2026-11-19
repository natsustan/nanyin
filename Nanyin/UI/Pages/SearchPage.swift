import NanyinKit
import SwiftUI

/// Search as the 2010 client showed it: matching artists and albums as
/// lines of links above the matching tracks.
struct SearchPage: View {
    @Environment(AppModel.self) private var app
    let query: String
    @State private var results: SearchResults?
    @State private var list: TrackList?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Search", subtitle: error ?? (results == nil ? "Searching for “\(query)”…" : "Results for “\(query)”"))
            if let results {
                SearchSummary(results: results)
            }
            if let list {
                TrackListTable(list: list)
            } else {
                Theme.content
            }
        }
        .task(id: query) {
            do {
                let found = try await app.account.api.search(query)
                results = found
                list = .tracks(found.tracks?.items ?? [])
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct SearchSummary: View {
    @Environment(AppModel.self) private var app
    let results: SearchResults

    var body: some View {
        let artists = results.artists?.items ?? []
        let albums = results.albums?.items ?? []
        VStack(alignment: .leading, spacing: 6) {
            if !artists.isEmpty {
                LinkLine(label: "Artists", items: artists.map { ($0.name, Route.artist(id: $0.id)) })
            }
            if !albums.isEmpty {
                LinkLine(label: "Albums", items: albums.map { ("\($0.name) by \($0.artists.first?.name ?? "")", Route.album(id: $0.id)) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.hex(0x262626))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

/// "Artists: A, B, C" with each name a link.
private struct LinkLine: View {
    @Environment(AppModel.self) private var app
    let label: String
    let items: [(String, Route)]

    var body: some View {
        FlowText(label: label, items: items) { app.navigator.go(to: $0) }
    }
}

/// Inline links that wrap like text.
private struct FlowText: View {
    let label: String
    let items: [(String, Route)]
    let open: (Route) -> Void

    var body: some View {
        var text = AttributedString("\(label): ")
        text.font = AquaFont.bold(11)
        text.foregroundColor = Theme.text
        for (index, item) in items.enumerated() {
            var link = AttributedString(item.0)
            link.font = AquaFont.regular(11)
            link.foregroundColor = Theme.hex(0xC8C8C8)
            link.link = URL(string: "nanyin-route://\(index)")
            text += link
            if index < items.count - 1 {
                var comma = AttributedString(", ")
                comma.foregroundColor = Theme.secondaryText
                text += comma
            }
        }
        return Text(text)
            .lineLimit(2)
            .environment(\.openURL, OpenURLAction { url in
                if let index = url.host().flatMap(Int.init), items.indices.contains(index) {
                    open(items[index].1)
                }
                return .handled
            })
    }
}
