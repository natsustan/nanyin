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
            if !results.artists.isEmpty || !results.albums.isEmpty || !results.playlists.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !results.artists.isEmpty {
                        LinkText(label: "Artists", parts: results.artists.map { ($0.name, .artist(id: $0.id)) },
                                 color: Theme.text)
                    }
                    if !results.albums.isEmpty {
                        LinkText(label: "Albums", parts: results.albums.map {
                            ("\($0.name) by \($0.artists.first?.name ?? "")", .album(id: $0.id))
                        }, color: Theme.text)
                    }
                    if !results.playlists.isEmpty {
                        LinkText(label: "Playlists", parts: results.playlists.map {
                            ($0.name, .playlist(id: $0.id))
                        }, color: Theme.text)
                    }
                }
                .font(AquaFont.regular(12))
                .lineLimit(2)
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
