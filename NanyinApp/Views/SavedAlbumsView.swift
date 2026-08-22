//
//  SavedAlbumsView.swift
//  Nanyin
//

import SwiftUI

/// Saved Albums aggregate page (M4.3): cover grid with hover play, client-side
/// filter, sort orders, and whole-album context playback. Saved albums and
/// Liked Songs are separate concepts — no hearts here, only plus/check
/// semantics.
///
/// Single scroll region: fixed header + one vertical ScrollView holding a
/// lazy cover grid (UI perf rules — grids are lazy, like the discography
/// strips, never a nested same-axis scroller).
struct SavedAlbumsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    @State private var filterText = ""
    @State private var sortOrder: SortOrder = .recentlyAdded

    enum SortOrder: String, CaseIterable, Identifiable {
        case recentlyAdded = "Recently Added"
        case album = "Album"
        case artist = "Artist"
        var id: String { rawValue }
    }

    private var trimmedFilter: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Client-side filter + deterministic sort over the cache display list.
    private var visibleAlbums: [SpotifyClient.SavedAlbum] {
        var list = app.savedAlbums
        if !trimmedFilter.isEmpty {
            list = list.filter {
                $0.album.name.localizedCaseInsensitiveContains(trimmedFilter)
                    || $0.album.artistName.localizedCaseInsensitiveContains(trimmedFilter)
            }
        }
        switch sortOrder {
        case .recentlyAdded:
            break // Display list is already newest-first (server + local inserts).
        case .album:
            list.sort { $0.album.name.localizedStandardCompare($1.album.name) == .orderedAscending }
        case .artist:
            list.sort {
                let byArtist = $0.album.artistName.localizedStandardCompare($1.album.artistName)
                return byArtist == .orderedAscending
                    || (byArtist == .orderedSame
                        && $0.album.name.localizedStandardCompare($1.album.name) == .orderedAscending)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.colors.divider)
            if app.savedAlbumsError != nil, app.hasSavedAlbumsData {
                refreshErrorBanner
            }
            content
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved Albums")
                    .font(theme.typography.collectionHeader)
                    .foregroundStyle(theme.colors.primaryText)
                Spacer()
                Text(albumCountLabel)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            HStack(spacing: 12) {
                filterField
                Spacer()
                sortMenu
            }
        }
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.pageTopInset)
        .padding(.bottom, theme.metrics.headerBottomInset)
    }

    private var albumCountLabel: String {
        let count = app.savedAlbumCount
        return count == 1 ? "1 album" : "\(count) albums"
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.secondaryText)
            TextField("Filter albums…", text: $filterText)
                .textFieldStyle(.plain)
                .font(theme.typography.metadata)
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.metrics.compactFieldHorizontalPadding)
        .padding(.vertical, theme.metrics.compactFieldVerticalPadding)
        .background(theme.colors.inputBackground.swiftUIStyle)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.cornerRadius)
                .strokeBorder(theme.colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.cornerRadius))
        .frame(width: 220)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(theme.typography.compact)
                Text(sortOrder.rawValue)
                    .font(theme.typography.metadata)
            }
            .foregroundStyle(theme.colors.secondaryText)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if let error = app.savedAlbumsError, !app.hasSavedAlbumsData {
            errorState(error)
        } else if !app.hasSavedAlbumsData {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(theme.colors.accent)
                Text("Loading saved albums…")
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if app.savedAlbums.isEmpty {
            emptyState
        } else if visibleAlbums.isEmpty {
            VStack(spacing: 10) {
                Text("No albums match “\(trimmedFilter)”")
                    .font(theme.typography.bodyEmphasis)
                    .foregroundStyle(theme.colors.secondaryText)
                Button("Clear filter") { filterText = "" }
                    .buttonStyle(.link)
                    .tint(theme.colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            albumGrid
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(theme.colors.warning)
            Text(message)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, theme.metrics.pageHorizontalInset + 12)
            Button {
                app.refreshSavedAlbums(force: true)
            } label: {
                Text("Retry")
                    .font(theme.typography.button)
                    .foregroundStyle(theme.colors.inverseText)
                    .padding(.horizontal, theme.metrics.controlHorizontalPadding)
                    .padding(.vertical, theme.metrics.controlVerticalPadding - 1)
                    .background(theme.colors.accent)
                    .cornerRadius(theme.metrics.smallPillCornerRadius)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.6))
            Text("No saved albums yet")
                .font(theme.typography.collectionTitle)
                .foregroundStyle(theme.colors.primaryText)
            Text("Save albums from any album page — they stay separate from Liked Songs.")
                .font(theme.typography.metadata)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                app.focusSearch()
            } label: {
                Text("Search for albums")
                    .font(theme.typography.button)
                    .foregroundStyle(theme.colors.inverseText)
                    .padding(.horizontal, theme.metrics.controlHorizontalPadding - 4)
                    .padding(.vertical, theme.metrics.controlVerticalPadding - 2)
                    .background(theme.colors.accent)
                    .cornerRadius(theme.metrics.compactPillCornerRadius)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The page's single vertical scroller. LazyVGrid materializes cards only
    /// near the viewport — same laziness contract as the discography strips.
    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.metrics.collectionGridMinimum), spacing: theme.metrics.smallPadding + 8)],
                spacing: theme.metrics.smallPadding + 8
            ) {
                ForEach(visibleAlbums) { saved in
                    SavedAlbumCard(album: saved)
                }
            }
            .padding(.horizontal, theme.metrics.pageHorizontalInset)
            .padding(.top, theme.metrics.sectionTopPadding + 4)
            .padding(.bottom, theme.metrics.pageBottomInset + 4)
        }
    }

    private var refreshErrorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.warning)
            Text("Couldn’t refresh all saved albums.")
                .font(theme.typography.bannerText)
                .foregroundStyle(theme.colors.secondaryText)
            Spacer()
            Button("Retry") {
                app.refreshSavedAlbums(force: true)
            }
            .buttonStyle(.link)
            .tint(theme.colors.accent)
        }
        .padding(.horizontal, theme.metrics.cardPadding)
        .padding(.vertical, theme.metrics.fieldVerticalPadding)
        .background(theme.colors.warningContainer.swiftUIStyle)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius)
                .strokeBorder(theme.colors.warningBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius))
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.sectionTopPadding)
    }
}

/// One saved-album card: square cover with a hover play circle and a remove
/// badge, title + artist/year beneath. Click opens the album page. Hover
/// state is card-local (never in the grid parent — UI perf rules).
private struct SavedAlbumCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let album: SpotifyClient.SavedAlbum

    @State private var hovering = false

    private var subtitle: String {
        [album.album.artistName, album.album.year ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            Text(album.album.name)
                .font(theme.typography.cardTitle)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
            Text(subtitle)
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
        .padding(theme.metrics.smallPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            hovering ? theme.colors.cardHover.swiftUIStyle : AnyShapeStyle(Color.clear)
        )
        .cornerRadius(theme.metrics.cardCornerRadius)
        .contentShape(Rectangle())
        .onTapGesture {
            app.open(.album(
                id: album.id,
                name: album.album.name,
                subtitle: subtitle,
                artworkURL: album.album.artworkURL
            ))
        }
        .contextMenu {
            Button {
                app.playAlbum(id: album.id)
            } label: {
                Label("Play Album", systemImage: "play")
            }
            Divider()
            Button {
                app.removeSavedAlbum(album)
            } label: {
                Label("Remove from Saved Albums", systemImage: "minus.circle")
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "https://open.spotify.com/album/\(album.id)", forType: .string
                )
            } label: {
                Label("Copy Album Link", systemImage: "link")
            }
        }
        .onHover { hovering = $0 }
    }

    private var cover: some View {
        ArtworkView(url: album.album.artworkURL, size: theme.metrics.collectionArtworkSize) {
            placeholderCover
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.cornerRadius))
        .shadow(color: theme.colors.shadow.opacity(0.35), radius: theme.metrics.shadowRadius, y: theme.metrics.shadowYOffset)
        .overlay(alignment: .topTrailing) {
            if hovering { removeBadge.padding(theme.metrics.smallPadding - 2) }
        }
        .overlay(alignment: .bottomLeading) {
            if hovering { playButton.padding(theme.metrics.smallPadding) }
        }
    }

    /// Green play circle (Spotify-grid style) — starts the whole album via
    /// its server-resolved context at index 0 (no track-URI upload).
    private var playButton: some View {
        Button {
            app.playAlbum(id: album.id)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.colors.inverseText)
                .frame(width: theme.metrics.collectionArtworkSize * 0.20, height: theme.metrics.collectionArtworkSize * 0.20)
                .background(Circle().fill(theme.colors.accent))
                .shadow(color: theme.colors.shadow.opacity(0.4), radius: theme.metrics.smallCornerRadius * 2, y: 2)
        }
        .buttonStyle(.plain)
        .help("Play Album")
    }

    /// Everything in this grid is saved by definition, so the badge appears
    /// only on hover, as the removal affordance (minus, not a heart).
    private var removeBadge: some View {
        Button {
            app.removeSavedAlbum(album)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(theme.colors.primaryText)
                .shadow(color: theme.colors.shadow.opacity(0.5), radius: theme.metrics.smallCornerRadius + 1)
        }
        .buttonStyle(.plain)
        .help("Remove from Saved Albums")
    }

    private var placeholderCover: some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}
