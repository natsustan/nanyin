import SwiftUI

/// A title over a grid of tiles that loads more as it scrolls.
struct GridPage<Item: Identifiable & Sendable, Cursor: Sendable, Cell: View>: View {
    let title: String
    let pager: Pager<Item, Cursor>
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        VStack(spacing: 0) {
            PagerHeader(title: title, pager: pager)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 18, alignment: .top)], spacing: 18) {
                    ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, item in
                        cell(item).onAppear { pager.appeared(index) }
                    }
                }
                .padding(16)
            }
            .background(Theme.content)
        }
    }
}
