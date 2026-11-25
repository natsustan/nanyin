import NanyinKit
import SwiftUI

/// What's New in the 2010 Spotify-for-Mac style: a brushed-metal tab strip
/// flush with the sidebar header above airy cover grids with green headings
/// and metallic "More" pills, alongside Recently Played and Top Tracks.
struct WhatsNewPage: View {
    @Environment(\.appearsActive) private var appearsActive
    let model: WhatsNewModel

    @State private var grid = CoverGridMetrics.compute(width: 720)
    @State private var expanded: Set<SectionID> = []

    private enum SectionID: Hashable {
        case newReleases, madeForYou, topMixes, topArtists
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            switch model.tab {
            case .overview:
                overview
            case .recentlyPlayed:
                trackTable(model.recentlyPlayed, empty: "Songs you play on Spotify appear here.")
            case .topTracks:
                trackTable(model.topTracks, empty: "No top tracks for this period yet.")
            }
        }
        .background(Theme.content)
        .onGeometryChange(for: CoverGridMetrics.self) { proxy in
            CoverGridMetrics.compute(width: proxy.size.width)
        } action: { metrics in
            grid = metrics
        }
    }

    private var tabBar: some View {
        let tabs = WhatsNewModel.Tab.allCases
        return MetalSubBar {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let nextSelected = index + 1 < tabs.count && model.tab == tabs[index + 1]
                MetalTabButton(
                    title: tab.rawValue,
                    isSelected: model.tab == tab,
                    isFirst: index == 0,
                    hideTrailingDivider: nextSelected,
                    activeWindow: appearsActive
                ) {
                    model.selectTab(tab)
                }
            }
            if model.tab == .topTracks {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 2) {
                        ForEach(TopTimeRange.allCases, id: \.self) { range in
                            MetalRangePill(title: range.label, isSelected: model.topRange == range) {
                                model.setTopRange(range)
                            }
                        }
                    }
                    .fixedSize()
                    rangeMenu(compact: false)
                    rangeMenu(compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 6)
                .padding(.trailing, 8)
            } else {
                Spacer(minLength: 0)
            }
            MetalSubBarDivider()
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .bold))
                    .opacity(isRefreshing ? 0.5 : 1)
            }
            .buttonStyle(MetalSubBarButtonStyle(width: 26))
            .help("Refresh")
        }
    }

    private func rangeMenu(compact: Bool) -> some View {
        Menu {
            ForEach(TopTimeRange.allCases, id: \.self) { range in
                Button {
                    model.setTopRange(range)
                } label: {
                    Text(model.topRange == range ? "✓ \(range.label)" : range.label)
                }
            }
        } label: {
            HStack(spacing: 3) {
                if compact {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Text(model.topRange.label)
                        .font(AquaFont.bold(10.5))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 7)
            .frame(height: 16)
            .background(
                Capsule()
                    .fill(Theme.selection)
                    .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 0.75))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .environment(\.colorScheme, .light)
        .help("Time Range: \(model.topRange.label)")
    }

    private var isRefreshing: Bool {
        switch model.tab {
        case .overview: model.isLoadingOverview
        case .recentlyPlayed: model.recentlyPlayed?.pages.isLoading == true
        case .topTracks: model.topTracks?.pages.isLoading == true
        }
    }

    @ViewBuilder private var overview: some View {
        if !model.hasOverviewContent {
            if model.isLoadingOverview {
                PlaceholderText(message: "Loading…")
            } else if let error = model.topArtistsError {
                PlaceholderText(message: error) { model.refresh() }
            } else {
                PlaceholderText(message: "Nothing new to show yet.") { model.refresh() }
            }
        } else {
            let sections = visibleSections
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                        if index > 0 {
                            EtchedDivider()
                        }
                        sectionView(for: section, layout: grid)
                    }
                }
                .padding(.horizontal, grid.padding)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(Theme.content)
        }
    }

    private var visibleSections: [SectionID] {
        var result: [SectionID] = []
        if !model.newReleases.isEmpty { result.append(.newReleases) }
        if !model.madeForYou.isEmpty { result.append(.madeForYou) }
        if !model.topMixes.isEmpty { result.append(.topMixes) }
        if !model.topArtists.isEmpty { result.append(.topArtists) }
        return result
    }

    @ViewBuilder private func sectionView(for section: SectionID, layout: CoverGridMetrics) -> some View {
        switch section {
        case .newReleases:
            coverSection(id: .newReleases, title: "New Releases", items: model.newReleases, collapsedRows: 2, layout: layout) {
                Tile(album: $0, subtitle: releaseSubtitle($0))
            }
        case .madeForYou:
            coverSection(id: .madeForYou, title: "Made for You", items: model.madeForYou, collapsedRows: 1, layout: layout) {
                Tile(playlist: $0)
            }
        case .topMixes:
            coverSection(id: .topMixes, title: "Your Top Mixes", items: model.topMixes, collapsedRows: 1, layout: layout) {
                Tile(playlist: $0)
            }
        case .topArtists:
            coverSection(id: .topArtists, title: "Top Artists", items: model.topArtists, collapsedRows: 1, layout: layout) {
                Tile(artist: $0, subtitle: "Artist")
            }
        }
    }

    private func coverSection<Item: Identifiable, Cell: View>(
        id: SectionID,
        title: String,
        items: [Item],
        collapsedRows: Int,
        layout: CoverGridMetrics,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) -> some View {
        let collapsedLimit = layout.columns * collapsedRows
        let hasMore = items.count > collapsedLimit
        let isExpanded = expanded.contains(id)
        let displayed = (hasMore && !isExpanded) ? Array(items.prefix(collapsedLimit)) : items

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(AquaFont.bold(14))
                    .foregroundStyle(Theme.green)
                Spacer(minLength: 8)
                if hasMore {
                    Button(isExpanded ? "Show Less" : "More") {
                        if isExpanded {
                            expanded.remove(id)
                        } else {
                            expanded.insert(id)
                        }
                    }
                    .buttonStyle(MetalPillButtonStyle())
                    .help(isExpanded ? "Show fewer items" : "Show all \(items.count) items")
                }
            }
            LazyVGrid(columns: layout.gridColumns, alignment: .leading, spacing: 18) {
                ForEach(displayed) { item in
                    cell(item)
                }
            }
        }
    }

    @ViewBuilder private func trackTable(_ list: TrackList?, empty: String) -> some View {
        if let list {
            let pages = list.pages
            if pages.items.isEmpty {
                PlaceholderText(
                    message: pages.error ?? (pages.isLoading ? "Loading…" : empty),
                    retry: pages.error == nil ? nil : { pages.retry() })
            } else {
                TrackListTable(list: list, columns: [.star, .track, .artist, .time, .album])
            }
        } else {
            PlaceholderText(message: "Loading…")
        }
    }

    private func releaseSubtitle(_ album: AlbumSummary) -> String {
        [album.artists.names, album.releaseYear ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A 2010 Spotify-style brushed-metal tab: when active, drops seamlessly into
/// the dark charcoal content below; when inactive, sits in the light metal bar.
private struct MetalTabButton: View {
    let title: String
    let isSelected: Bool
    let isFirst: Bool
    let hideTrailingDivider: Bool
    let activeWindow: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if isSelected && !isFirst {
                    Rectangle().fill(Theme.divider).frame(width: 1)
                }
                Text(title)
                    .font(isSelected ? AquaFont.bold(11.5) : AquaFont.regular(11.5))
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : Theme.metalText.opacity(activeWindow ? 1 : 0.65)
                    )
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: Theme.subBarHeight)
                if isSelected {
                    Rectangle().fill(Theme.divider).frame(width: 1)
                } else if !hideTrailingDivider {
                    MetalSubBarDivider()
                        .padding(.bottom, 1)
                }
            }
            .background {
                if isSelected {
                    Theme.subBarActiveTab
                        .hairline(.top, Theme.subBarActiveTabHighlight)
                } else if hovering {
                    Theme.subBarHover
                        .padding(.bottom, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Compact time-range selector pill inside the brushed-metal tab bar.
private struct MetalRangePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? AquaFont.bold(10.5) : AquaFont.regular(10.5))
                .foregroundStyle(isSelected ? .white : Theme.metalText)
                .padding(.horizontal, 7)
                .frame(height: 16)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.selection)
                            .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 0.75))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
