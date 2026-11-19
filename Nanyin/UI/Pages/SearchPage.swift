import NanyinKit
import SwiftUI

/// Search as the 2010 client showed it: matching artists and albums as
/// lines of links above the matching tracks.
struct SearchPage: View {
    let query: String
    let results: SearchResultsModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Search",
                subtitle: results.error ?? (results.tracks == nil ? "Searching for “\(query)”…" : "Results for “\(query)”"))
            if !results.artists.isEmpty || !results.albums.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !results.artists.isEmpty {
                        LinkLine(label: "Artists", items: results.artists.map { ($0.name, Route.artist(id: $0.id)) })
                    }
                    if !results.albums.isEmpty {
                        LinkLine(label: "Albums", items: results.albums.map {
                            ("\($0.name) by \($0.artists.first?.name ?? "")", Route.album(id: $0.id))
                        })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.hex(0x262626))
                .hairline(.bottom, Theme.divider)
            }
            if let tracks = results.tracks {
                TrackListTable(list: tracks)
            } else {
                Theme.content
            }
        }
    }
}

/// "Artists: A, B, C", each name a link, wrapping like text.
private struct LinkLine: View {
    @Environment(AppModel.self) private var app
    let label: String
    let items: [(String, Route)]

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
                    app.navigator.go(to: items[index].1)
                }
                return .handled
            })
    }
}
