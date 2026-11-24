import AppKit
import NanyinKit
import SwiftUI

/// What's New in the 2010 client's style: cover shelves for new releases,
/// personalized mixes and top artists, alongside Recently Played and Top Tracks.
struct WhatsNewPage: View {
    @Environment(AppModel.self) private var app
    let model: WhatsNewModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "What's New", subtitle: subtitle) {
                Button("Refresh") { model.refresh() }
                    .buttonStyle(TexturedButtonStyle())
            }
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

    private var subtitle: String {
        switch model.tab {
        case .overview: "New releases, mixes and artists"
        case .recentlyPlayed: "Recently played"
        case .topTracks: "Your top tracks · \(model.topRange.label)"
        }
    }

    private var tabBar: some View {
        GraphiteHeader {
            HStack(spacing: 2) {
                ForEach(WhatsNewModel.Tab.allCases, id: \.self) { tab in
                    ShelfTabButton(title: tab.rawValue, isSelected: model.tab == tab) {
                        model.selectTab(tab)
                    }
                }
            }
            Spacer()
            if model.tab == .topTracks {
                HStack(spacing: 2) {
                    ForEach(TopTimeRange.allCases, id: \.self) { range in
                        ShelfTabButton(title: range.label, isSelected: model.topRange == range) {
                            model.setTopRange(range)
                        }
                    }
                }
            }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !model.newReleases.isEmpty {
                        shelf(title: "New Releases", count: model.newReleases.count) {
                            ForEach(model.newReleases) { album in
                                Tile(album: album, subtitle: releaseSubtitle(album), size: 120)
                                    .contextMenu { tileMenu(uri: album.uri, openTitle: "Open Album", route: .album(id: album.id)) }
                            }
                        }
                    }
                    if !model.madeForYou.isEmpty {
                        shelf(title: "Made for You", count: model.madeForYou.count) {
                            ForEach(model.madeForYou) { playlistTile($0) }
                        }
                    }
                    if !model.topMixes.isEmpty {
                        shelf(title: "Your Top Mixes", count: model.topMixes.count) {
                            ForEach(model.topMixes) { playlistTile($0) }
                        }
                    }
                    if !model.topArtists.isEmpty {
                        shelf(title: "Top Artists", count: model.topArtists.count) {
                            ForEach(model.topArtists) { artist in
                                Tile(title: artist.name, subtitle: "Artist", images: artist.images,
                                     route: .artist(id: artist.id), size: 120)
                                    .contextMenu { tileMenu(uri: artist.uri, openTitle: "Open Artist", route: .artist(id: artist.id)) }
                            }
                        }
                    }
                }
            }
            .background(Theme.content)
        }
    }

    private func shelf<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GraphiteHeader {
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .frame(height: 174)
            .background(Theme.content)
        }
    }

    private func playlistTile(_ playlist: Playlist) -> some View {
        Tile(
            title: playlist.name,
            subtitle: playlist.owner.display_name ?? "Spotify",
            images: playlist.images,
            route: .playlist(id: playlist.id),
            size: 120
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

/// A compact recessed tab button inside a `GraphiteHeader`.
private struct ShelfTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? AquaFont.bold(11) : AquaFont.regular(11))
                .foregroundStyle(isSelected ? .white : Theme.hex(0xCCCCCC))
                .padding(.horizontal, 8)
                .frame(height: 16)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.selection)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.45), lineWidth: 0.5))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
