import SwiftUI

/// A brushed-metal sub-bar over a grid of tiles that loads more as it scrolls.
struct GridPage<Item: Identifiable & Sendable, Cursor: Sendable, Cell: View>: View {
    let title: String
    let pager: Pager<Item, Cursor>
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let detail = pager.total.map(String.init) ?? ""
        let status = pager.error ?? (pager.isLoading && pager.items.isEmpty ? "Loading…" : detail)
        VStack(spacing: 0) {
            MetalSubBar {
                MetalSubBarTitle(title: title, detail: status)
                Spacer(minLength: 8)
                if pager.error != nil {
                    MetalSubBarDivider()
                    Button { pager.retry() } label: {
                        Text("Try Again")
                            .font(AquaFont.bold(11))
                    }
                    .buttonStyle(MetalSubBarButtonStyle(width: nil))
                }
            }
            ScrollView {
                LazyVGrid(columns: CoverGridMetrics.adaptiveColumns, alignment: .leading, spacing: 20) {
                    ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, item in
                        cell(item).onAppear { pager.appeared(index) }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .background(Theme.content)
        }
    }
}
