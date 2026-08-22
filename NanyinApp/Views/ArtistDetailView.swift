//
//  ArtistDetailView.swift
//  Nanyin
//

import SwiftUI

/// Artist page: circular portrait header + discography rows (albums, singles)
/// + top tracks (PlaylistDetailView's structure). Top tracks are small — they
/// play as a bounded ad-hoc context, same path as search results (no server
/// context URI).
struct ArtistDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    let artistID: String
    let title: String
    let artworkURL: URL?
    let contextKey: String

    private var resolvedArtworkURL: URL? {
        artworkURL ?? app.artistsByID[artistID]?.artworkURL
    }

    private var tracks: [SpotifyClient.Track] {
        app.tracksByContext[contextKey] ?? []
    }

    private var releases: [SpotifyClient.AlbumInfo] {
        app.albumsByArtist[contextKey] ?? []
    }

    private var albums: [SpotifyClient.AlbumInfo] {
        releases.filter { $0.group != "single" }
    }

    private var singles: [SpotifyClient.AlbumInfo] {
        releases.filter { $0.group == "single" }
    }

    var body: some View {
        // Keep the artist header visible even when the artist has no top
        // tracks yet (or the top-tracks request fails). The artist page is
        // still useful for its identity and any available releases.
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                header
                Divider().overlay(theme.colors.divider)
                trackContent
                discography
            }
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
        .task(id: artistID) {
            if artworkURL == nil {
                app.loadArtistProfileIfNeeded(id: artistID)
            }
        }
    }

    @ViewBuilder
    private var trackContent: some View {
        if let error = app.tracksError[contextKey] {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(theme.colors.warning)
                Text(error)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.pageTopInset + 4)
        } else if tracks.isEmpty {
            VStack(spacing: 12) {
                if app.isLoadingTracks(contextKey: contextKey) {
                    ProgressView()
                    Text("Loading top tracks…")
                        .foregroundStyle(theme.colors.secondaryText)
                } else {
                    Text("No top tracks")
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.metrics.pageTopInset + 4)
        } else {
            // Top tracks are only ~10 rows, so plain rows (no NSTableView
            // recycling) are fine. Horizontal card rows below use the
            // perpendicular axis and keep this as a single vertical scroller.
            topTracksHeader
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track: track,
                    index: index,
                    contextKey: contextKey,
                    presentation: rowPresentation
                )
            }
        }
    }

    private var rowPresentation: TrackRowPresentation {
        theme.id == .classic2010 ? .classic : .comfortable
    }

    @ViewBuilder
    private var header: some View {
        if theme.id == .classic2010 {
            classicHeader
        } else {
            darkHeader
        }
    }

    private var darkHeader: some View {
        HStack(spacing: 24) {
            portrait(size: theme.metrics.detailArtworkSize)
                .frame(width: theme.metrics.detailArtworkSize, height: theme.metrics.detailArtworkSize)
                .shadow(color: theme.colors.shadow.opacity(0.5), radius: theme.metrics.shadowRadius + 4, y: theme.metrics.shadowYOffset + 2)

            VStack(alignment: .leading, spacing: 10) {
                Text("ARTIST")
                    .font(theme.typography.sectionHeader)
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.secondaryText)
                Text(title)
                    .font(theme.typography.detailTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                Text(headerStats)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)

                playButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.pageTopInset)
        .padding(.bottom, theme.metrics.pageBottomInset)
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    private var classicHeader: some View {
        HStack(spacing: 12) {
            portrait(size: theme.metrics.detailArtworkSize)
                .frame(width: theme.metrics.detailArtworkSize, height: theme.metrics.detailArtworkSize)

            VStack(alignment: .leading, spacing: 5) {
                Text("ARTIST")
                    .font(theme.typography.sectionHeader)
                    .tracking(0.8)
                    .foregroundStyle(theme.colors.secondaryText)
                Text(title)
                    .font(theme.typography.detailTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                Text(headerStats)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                playButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.vertical, theme.metrics.smallPadding + 2)
        .background {
            ChromeSectionBar(
                style: ChromeSectionBarStyle(
                    height: theme.metrics.detailArtworkSize + (theme.metrics.smallPadding + 2) * 2
                )
            )
        }
    }

    private var playButton: some View {
        Button {
            if let first = tracks.first {
                app.play(track: first, contextKey: contextKey)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("PLAY")
                    .font(theme.typography.button)
                    .tracking(0.8)
            }
            .foregroundStyle(theme.colors.inverseText)
            .padding(.horizontal, theme.metrics.controlHorizontalPadding)
            .padding(.vertical, theme.metrics.controlVerticalPadding)
            .background(theme.colors.accent)
            .cornerRadius(theme.metrics.pillCornerRadius)
        }
        .buttonStyle(.plain)
        .disabled(!app.isPlaybackReady || tracks.isEmpty)
        .opacity(!app.isPlaybackReady || tracks.isEmpty ? 0.5 : 1)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var headerStats: String {
        var stats = ["\(tracks.count) top tracks"]
        if !albums.isEmpty {
            stats.append("\(albums.count) albums")
        }
        if !singles.isEmpty {
            stats.append("\(singles.count) singles")
        }
        return stats.joined(separator: " · ")
    }

    @ViewBuilder
    private func portrait(size: CGFloat) -> some View {
        ArtworkView(url: resolvedArtworkURL, size: size) {
            placeholderPortrait(size: size)
        }
        .clipShape(Circle())
    }

    private func placeholderPortrait(size: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.31))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
    // MARK: - Discography

    @ViewBuilder
    private var discography: some View {
        if !albums.isEmpty {
            albumRow(title: "Albums", items: albums)
        }
        if !singles.isEmpty {
            albumRow(title: "Singles", items: singles)
        }
    }

    private func albumRow(title: String, items: [SpotifyClient.AlbumInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(theme.typography.sectionLabel)
                .padding(.horizontal, theme.metrics.pageHorizontalInset)
            // Horizontal strip above the vertical List — perpendicular axes,
            // so the single-scroll-region rule (no same-axis nesting) holds.
            // LazyHStack keeps cards lazy for long discographies.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { album in
                        AlbumCard(album: album)
                    }
                }
                .padding(.horizontal, theme.metrics.pageHorizontalInset)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, theme.metrics.sectionTopPadding)
        .padding(.bottom, theme.metrics.sectionBottomPadding - 2)
    }

    private var topTracksHeader: some View {
        HStack(spacing: 10) {
            Text("Top tracks")
                .font(theme.typography.sectionLabel)
            Text("\(tracks.count)")
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.sectionTopPadding - 2)
        .padding(.bottom, theme.metrics.sectionBottomPadding)
    }
}

/// Square-cover album card. Hover state is card-local (same rule as rows).
private struct AlbumCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let album: SpotifyClient.AlbumInfo

    @State private var hovering = false

    private var savedAlbum: SpotifyClient.SavedAlbum {
        SpotifyClient.SavedAlbum(album: album, addedAt: nil)
    }

    private var isSavedKnown: Bool { app.isAlbumSaveKnown(album.id) }
    private var isSaved: Bool { app.isAlbumSaved(album.id) }

    private var subtitle: String {
        [album.artistName, album.year ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button {
            app.open(.album(id: album.id, name: album.name, subtitle: subtitle, artworkURL: album.artworkURL))
        } label: {
            VStack(alignment: .leading, spacing: theme.metrics.smallPadding) {
                cover
                Text(album.name)
                    .font(theme.typography.tileTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                Text(album.year ?? "")
                    .font(theme.typography.tileSubtitle)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(width: theme.metrics.discographyArtworkSize + theme.metrics.smallPadding * 2, alignment: .leading)
            .padding(theme.metrics.smallPadding)
            .background(
                hovering ? theme.colors.cardHover.swiftUIStyle : AnyShapeStyle(Color.clear)
            )
            .cornerRadius(theme.metrics.cardCornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hovering = hovering
        }
        .linkCursor()
        .contextMenu {
            Button {
                app.playAlbum(id: album.id)
            } label: {
                Label("Play Album", systemImage: "play")
            }
            Divider()
            if isSavedKnown, isSaved {
                Button {
                    app.removeSavedAlbum(savedAlbum)
                } label: {
                    Label("Remove from Saved Albums", systemImage: "minus.circle")
                }
            } else {
                // Unknown state defaults to Save — both writes are
                // idempotent server-side, so no probe is needed first.
                Button {
                    app.saveAlbum(savedAlbum)
                } label: {
                    Label("Save Album", systemImage: "plus.circle")
                }
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
    }

    @ViewBuilder
    private var cover: some View {
        ArtworkView(url: album.artworkURL, size: theme.metrics.discographyArtworkSize) {
            placeholderCover(size: theme.metrics.discographyArtworkSize)
        }
        .frame(width: theme.metrics.discographyArtworkSize, height: theme.metrics.discographyArtworkSize)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.imageCornerRadius))
        .shadow(color: theme.colors.shadow.opacity(0.4), radius: theme.metrics.shadowRadius, y: theme.metrics.shadowYOffset)
    }

    private func placeholderCover(size: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.32, height: size * 0.32)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}
