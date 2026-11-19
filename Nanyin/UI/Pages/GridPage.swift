import SwiftUI

/// A title over a grid of tiles that loads more as it scrolls.
struct GridPage<Item: Identifiable & Sendable, Cell: View>: View {
    let title: String
    let list: ItemList<Item>
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, subtitle: list.error ?? (list.isLoading && list.items.isEmpty ? "Loading…" : "")) {
                if list.error != nil {
                    Button("Try Again", action: list.retry).buttonStyle(TexturedButtonStyle())
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 18, alignment: .top)], spacing: 18) {
                    ForEach(list.items) { item in
                        cell(item).onAppear { list.itemAppeared(item) }
                    }
                }
                .padding(16)
            }
            .background(Theme.content)
        }
    }
}
