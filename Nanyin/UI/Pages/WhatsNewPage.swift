import AppKit
import NanyinKit
import SwiftUI

/// What's New in the 2010 Spotify-for-Mac style: a brushed-metal tab strip
/// flush with the sidebar header above airy cover grids with green headings
/// and metallic "More" pills, alongside Recently Played and Top Tracks.
struct WhatsNewPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var appearsActive
    let model: WhatsNewModel

    @State private var contentWidth: CGFloat = 720
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
    }

    private var tabBar: some View {
        MetalSubBar {
            ForEach(WhatsNewModel.Tab.allCases, id: \.self) { tab in
                MetalTabButton(
                    title: tab.rawValue,
                    isSelected: model.tab == tab,
                    isFirst: tab == WhatsNewModel.Tab.allCases.first,
                    activeWindow: appearsActive
                ) {
                    model.selectTab(tab)
                }
            }
            Spacer(minLength: 8)
            if model.tab == .topTracks {
                HStack(spacing: 2) {
                    ForEach(TopTimeRange.allCases, id: \.self) { range in
                        MetalRangePill(title: range.label, isSelected: model.topRange == range) {
                            model.setTopRange(range)
                        }
                    }
                }
                .padding(.trailing, 8)
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
            let layout = GridMetrics.compute(width: contentWidth)
            let sections = visibleSections
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                        if index > 0 {
                            EtchedDivider()
                        }
                        sectionView(for: section, layout: layout)
                    }
                }
                .padding(.horizontal, layout.padding)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(Theme.content)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in contentWidth = width }
                }
            )
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

    @ViewBuilder private func sectionView(for section: SectionID, layout: GridMetrics) -> some View {
        switch section {
        case .newReleases:
            coverSection(
                id: .newReleases,
                title: "New Releases",
                items: model.newReleases,
                collapsedRows: 2,
                layout: layout
            ) { album in
                WhatsNewTile(
                    title: album.name,
                    subtitle: releaseSubtitle(album),
                    images: album.images,
                    size: layout.tileSize,
                    onOpen: { app.navigator.go(to: .album(id: album.id)) },
                    onPlay: { app.player.play(contextURI: album.uri) }
                )
                .contextMenu { tileMenu(uri: album.uri, openTitle: "Open Album", route: .album(id: album.id)) }
            }
        case .madeForYou:
            coverSection(
                id: .madeForYou,
                title: "Made for You",
                items: model.madeForYou,
                collapsedRows: 1,
                layout: layout
            ) { playlist in
                playlistTile(playlist, size: layout.tileSize)
            }
        case .topMixes:
            coverSection(
                id: .topMixes,
                title: "Your Top Mixes",
                items: model.topMixes,
                collapsedRows: 1,
                layout: layout
            ) { playlist in
                playlistTile(playlist, size: layout.tileSize)
            }
        case .topArtists:
            coverSection(
                id: .topArtists,
                title: "Top Artists",
                items: model.topArtists,
                collapsedRows: 1,
                layout: layout
            ) { artist in
                WhatsNewTile(
                    title: artist.name,
                    subtitle: "Artist",
                    images: artist.images,
                    size: layout.tileSize,
                    onOpen: { app.navigator.go(to: .artist(id: artist.id)) },
                    onPlay: { app.player.play(contextURI: artist.uri) }
                )
                .contextMenu { tileMenu(uri: artist.uri, openTitle: "Open Artist", route: .artist(id: artist.id)) }
            }
        }
    }

    private func coverSection<Item: Identifiable, Cell: View>(
        id: SectionID,
        title: String,
        items: [Item],
        collapsedRows: Int,
        layout: GridMetrics,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) -> some View {
        let collapsedLimit = layout.columns * collapsedRows
        let hasMore = items.count > collapsedLimit
        let isExpanded = expanded.contains(id)
        let displayed = (hasMore && !isExpanded) ? Array(items.prefix(collapsedLimit)) : items
        let columns = Array(
            repeating: GridItem(.fixed(layout.tileSize), spacing: layout.gap, alignment: .top),
            count: layout.columns
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(AquaFont.bold(14))
                    .foregroundStyle(Theme.green)
                    .engraved()
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
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(displayed) { item in
                    cell(item)
                }
            }
        }
    }

    private func playlistTile(_ playlist: Playlist, size: CGFloat) -> some View {
        WhatsNewTile(
            title: playlist.name,
            subtitle: playlist.owner.display_name ?? "Spotify",
            images: playlist.images,
            size: size,
            onOpen: { app.navigator.go(to: .playlist(id: playlist.id)) },
            onPlay: { app.player.play(contextURI: playlist.uri) }
        )
        .contextMenu { tileMenu(uri: playlist.uri, openTitle: "Open Playlist", route: .playlist(id: playlist.id)) }
    }

    @ViewBuilder private func tileMenu(uri: String, openTitle: String, route: Route) -> some View {
        Button("Play") { app.player.play(contextURI: uri) }
        Button(openTitle) { app.navigator.go(to: route) }
        Divider()
        Button("Copy Spotify Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Route.webLink(for: uri), forType: .string)
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

/// Computes an even column count and cover size so collapsed rows fill the
/// pane cleanly without orphan gaps or oversized covers.
private struct GridMetrics {
    let columns: Int
    let tileSize: CGFloat
    let gap: CGFloat = 18
    let padding: CGFloat = 22

    static func compute(width: CGFloat) -> GridMetrics {
        let gap: CGFloat = 18
        let padding: CGFloat = 22
        let minTile: CGFloat = 136
        let maxTile: CGFloat = 172
        let inner = max(320, width - padding * 2)
        let columns = max(3, Int((inner + gap) / (minTile + gap)))
        let rawTile = floor((inner - gap * CGFloat(columns - 1)) / CGFloat(columns))
        return GridMetrics(columns: columns, tileSize: min(maxTile, max(108, rawTile)))
    }
}

/// A framed cover tile for What's New: opens on click, with a subtle retro
/// play badge on hover so a release or mix can start in one click.
private struct WhatsNewTile: View {
    let title: String
    let subtitle: String
    let images: [SpotifyImage]?
    let size: CGFloat
    let onOpen: () -> Void
    let onPlay: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: onOpen) {
                    CoverImage(url: images?.best(minimum: 260), size: size)
                }
                .buttonStyle(.plain)

                if hovering {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.artworkButtonGlyph)
                            .offset(x: 1)
                            .frame(width: 24, height: 24)
                            .background(Theme.artworkButton, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.artworkButtonEdge, lineWidth: 0.75))
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Play")
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AquaFont.bold(12))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(width: size, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: size, alignment: .leading)
        .onHover { hovering = $0 }
    }
}

/// A 2010 Spotify-style brushed-metal tab: when active, drops seamlessly into
/// the dark charcoal content below; when inactive, sits in the light metal bar.
private struct MetalTabButton: View {
    let title: String
    let isSelected: Bool
    let isFirst: Bool
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
                    .shadow(
                        color: isSelected ? .black.opacity(0.65) : .white.opacity(0.6),
                        radius: 0,
                        y: isSelected ? -1 : 1
                    )
                    .padding(.horizontal, 14)
                    .frame(height: Theme.subBarHeight)
                if isSelected {
                    Rectangle().fill(Theme.divider).frame(width: 1)
                } else {
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
                .shadow(
                    color: isSelected ? .black.opacity(0.55) : .white.opacity(0.55),
                    radius: 0,
                    y: isSelected ? -1 : 1
                )
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
