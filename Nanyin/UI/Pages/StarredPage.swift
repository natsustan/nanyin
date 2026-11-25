import SwiftUI

/// Starred (Liked Songs) page with Play, Shuffle, in-page Filter, and Sort.
struct StarredPage: View {
    let list: TrackList

    var body: some View {
        let pages = list.pages
        let status = pages.error ?? (pages.isLoading && pages.items.isEmpty ? "Loading…" : count)
        VStack(spacing: 0) {
            MetalSubBar {
                MetalSubBarTitle(title: "Starred", detail: status, icon: "star.fill", iconTint: Theme.star)
                Spacer(minLength: 8)
                if pages.error != nil {
                    MetalSubBarDivider()
                    Button { pages.retry() } label: {
                        Text("Try Again")
                            .font(AquaFont.bold(11))
                    }
                    .buttonStyle(MetalSubBarButtonStyle(width: nil))
                }
            }
            FilterableTrackList(
                list: list,
                contextURI: list.contextURI,
                columns: [.star, .track, .artist, .time, .album, .added]
            )
        }
    }

    private var count: String {
        guard let total = list.pages.total else { return "" }
        return total == 1 ? "1 track" : "\(total) tracks"
    }
}
