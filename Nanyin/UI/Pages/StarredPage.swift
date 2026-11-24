import SwiftUI

/// Starred (Liked Songs) page with Play, Shuffle, in-page Filter, and Sort.
struct StarredPage: View {
    let list: TrackList

    var body: some View {
        VStack(spacing: 0) {
            PagerHeader(title: "Starred", pager: list.pages, detail: count)
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
