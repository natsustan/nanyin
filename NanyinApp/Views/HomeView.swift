//
//  HomeView.swift
//  Nanyin
//

import SwiftUI

/// Personalized home: Recently Played, Top Tracks, Top Artists, and library
/// shortcuts — built from public Web API endpoints (recently-played, top/
/// tracks, top/artists), NOT Spotify recommendation feeds. Sections load
/// independently (one failing never clears the others) and cache in memory
/// for the login session; the header button forces a full refresh. The M0
/// "paste a track URI" box lives on in SearchView (paste a track link there).
///
/// Layout: one vertical ScrollView for the page; the two card strips are
/// bounded horizontal (cross-axis) scrollers; top tracks render as plain
/// rows (≤10 — same pattern as ArtistDetailView). No nested same-axis
/// scrolling, hover state stays card-local (UI perf rules).
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.metrics.sectionTopPadding + 8) {
                header
                partialErrorNotice
                content
            }
            .padding(.horizontal, theme.metrics.pageHorizontalInset)
            .padding(.top, theme.metrics.pageTopInset)
            .padding(.bottom, theme.metrics.homeBottomInset)
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
        .onAppear {
            // Cache-guarded: first entry after login loads once; revisits
            // are no-ops until a manual refresh or an account change.
            app.loadHome()
        }
    }

    // MARK: - Header

    /// Greeting text for a moment in time (local timezone, like the wall
    /// clock the user actually lives by).
    private static func greetingText(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// Minute-tick timeline scoped to the greeting text ONLY — the rest of
    /// HomeView never re-renders on ticks, and the schedule pauses while the
    /// page is offscreen. No app-wide observable state involved.
    private var greeting: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(Self.greetingText(for: context.date))
                .font(theme.typography.pageTitle)
                .foregroundStyle(theme.colors.primaryText)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            greeting
            Spacer()
            if app.isLoadingHome {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.colors.accent)
            }
            RefreshButton(action: { app.loadHome(force: true) })
                .disabled(app.isLoadingHome)
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !app.hasHomeData, app.isLoadingHome {
            loadingState
        } else {
            if !app.hasHomeData, app.homeErrors.isEmpty {
                freshAccountHint
            }
            recentlyPlayedSection
            topTracksSection
            topArtistsSection
            librarySection
        }
    }

    /// Slim banner when a refresh dropped some sections but others still
    /// render — a failed block never blanks the page.
    @ViewBuilder
    private var partialErrorNotice: some View {
        if !app.homeErrors.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.warning)
                Text("Couldn’t load some sections.")
                    .font(theme.typography.bannerText)
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer()
                // Non-force load retries exactly the failed sections —
                // rendered sections keep their content.
                Button("Retry") {
                    app.loadHome()
                }
                .buttonStyle(.link)
                .tint(theme.colors.accent)
            }
            .padding(.horizontal, theme.metrics.bannerHorizontalPadding)
            .padding(.vertical, theme.metrics.bannerVerticalPadding)
            .background(theme.colors.warningContainer.swiftUIStyle)
            .overlay(
                RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius)
                    .strokeBorder(theme.colors.warningBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.bannerCornerRadius))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(theme.colors.accent)
            Text("Loading your home…")
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    /// All sections loaded successfully but the account has no history yet.
    private var freshAccountHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.house")
                .foregroundStyle(theme.colors.secondaryText)
            Text("Nothing here yet — play something and it will show up.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
            Spacer()
        }
        .padding(theme.metrics.cardPadding)
        .background(theme.colors.surface.swiftUIStyle)
        .cornerRadius(theme.metrics.cardCornerRadius)
    }

    // MARK: - Sections

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        if !app.homeRecentlyPlayed.isEmpty {
            section(title: "Recently Played") {
                // Bounded horizontal strip (≤10 cards) — perpendicular to
                // the page's single vertical scroll region.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.metrics.smallPadding + 4) {
                        ForEach(app.homeRecentlyPlayed) { card in
                            RecentCard(card: card)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var topTracksSection: some View {
        if !app.homeTopTracks.isEmpty {
            section(title: "Top Tracks", caption: "your most played · last 4 weeks") {
                // ≤10 rows — plain rows on the page's background, same
                // pattern as ArtistDetailView's top-tracks list.
                VStack(spacing: 0) {
                    ForEach(Array(app.homeTopTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            index: index,
                            contextKey: AppModel.homeTopTracksContextKey,
                            presentation: rowPresentation
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topArtistsSection: some View {
        if !app.homeTopArtists.isEmpty {
            section(title: "Top Artists", caption: "most played · last 6 months") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.metrics.smallPadding + 4) {
                        ForEach(app.homeTopArtists) { artist in
                            ArtistTile(artist: artist)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var librarySection: some View {
        section(title: "Your Library", caption: "liked and saved") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: theme.metrics.collectionGridMinimum), spacing: theme.metrics.smallPadding + 8)],
                spacing: theme.metrics.smallPadding + 8
            ) {
                likedSongsTile
                ForEach(Array(app.savedAlbums.prefix(5))) { saved in
                    LibraryTile(
                        title: saved.album.name,
                        subtitle: [saved.album.artistName, saved.album.year ?? ""]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "),
                        artworkURL: saved.album.artworkURL,
                        onOpen: {
                            app.open(.album(
                                id: saved.album.id,
                                name: saved.album.name,
                                subtitle: saved.album.artistName,
                                artworkURL: saved.album.artworkURL
                            ))
                        },
                        onPlay: { app.playAlbum(id: saved.album.id) },
                        linkURL: "https://open.spotify.com/album/\(saved.album.id)"
                    )
                }
                ForEach(Array(app.playlists.prefix(5))) { playlist in
                    LibraryTile(
                        title: playlist.name,
                        subtitle: "\(playlist.trackCount) songs · Playlist",
                        artworkURL: playlist.artworkURL,
                        onOpen: {
                            app.open(.playlist(id: playlist.id, name: playlist.name))
                        },
                        onPlay: { app.playPlaylist(id: playlist.id) },
                        linkURL: "https://open.spotify.com/playlist/\(playlist.id)"
                    )
                }
            }
        }
    }

    private var likedSongsTile: some View {
        LibraryTile(
            title: "Liked Songs",
            subtitle: app.likedCount == 1 ? "1 song" : "\(app.likedCount) songs",
            artworkURL: nil,
            assetCover: "LikedSongsCover",
            onOpen: { app.open(.liked) },
            onPlay: app.userId.isEmpty ? nil : { app.playLikedSongs() },
            linkURL: nil
        )
    }

    private var rowPresentation: TrackRowPresentation {
        theme.id == .classic2010 ? .classic : .comfortable
    }

    private func section<Content: View>(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, caption: caption)
            content()
        }
    }

    private func sectionHeader(title: String, caption: String?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(theme.typography.sectionTitle)
                .foregroundStyle(theme.colors.primaryText)
            if let caption {
                Text(caption)
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            Spacer()
        }
    }
}

// MARK: - Cards and tiles (hover state is card-local — never in the parent)

private struct RefreshButton: View {
    @Environment(\.appTheme) private var theme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? theme.colors.primaryText : theme.colors.secondaryText)
                .frame(width: 30, height: 30)
                .background(
                    hovering ? theme.colors.raisedSurface.swiftUIStyle : theme.colors.inputBackground.swiftUIStyle
                )
                .clipShape(Circle())
        }
        .buttonStyle(ThemePressFeedbackButtonStyle())
        .help("Refresh Home")
        .onHover { hovering = $0 }
    }
}

/// One Recently Played card: square cover, title, subtitle. Click opens the
/// context's page; hover play starts its server-resolved context.
private struct RecentCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let card: HomeFeed.Card

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            Text(card.title)
                .font(theme.typography.cardTitle)
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
            Text(card.subtitle)
                .font(theme.typography.secondary)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
        .frame(width: theme.metrics.homeFeatureArtworkSize + theme.metrics.smallPadding * 2, alignment: .leading)
        .padding(theme.metrics.smallPadding)
        .background(
            hovering ? theme.colors.cardHover.swiftUIStyle : AnyShapeStyle(Color.clear)
        )
        .cornerRadius(theme.metrics.cardCornerRadius)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .contextMenu { contextMenu }
        .onHover { hovering = $0 }
        .linkCursor()
    }

    private func open() {
        switch card.kind {
        case .album:
            app.open(.album(
                id: card.refID,
                name: card.title,
                subtitle: card.subtitle,
                artworkURL: card.artworkURL
            ))
        case .playlist:
            app.open(.playlist(id: card.refID, name: card.title))
        case .artist:
            app.open(.artist(id: card.refID, name: card.title, artworkURL: card.artworkURL))
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if canPlay {
            Button(action: play) {
                Label("Play", systemImage: "play")
            }
        }
        if let link = linkURL {
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
    }

    private var canPlay: Bool {
        app.isPlaybackReady
    }

    private func play() {
        guard canPlay else { return }
        switch card.kind {
        case .album: app.playAlbum(id: card.refID)
        case .playlist: app.playPlaylist(id: card.refID)
        case .artist: app.playArtist(id: card.refID)
        }
    }

    private var linkURL: String? {
        switch card.kind {
        case .album: "https://open.spotify.com/album/\(card.refID)"
        case .playlist: "https://open.spotify.com/playlist/\(card.refID)"
        case .artist: "https://open.spotify.com/artist/\(card.refID)"
        }
    }

    private var cover: some View {
        ArtworkView(url: card.artworkURL, size: theme.metrics.homeFeatureArtworkSize) {
            placeholderCover
        }
        .frame(width: theme.metrics.homeFeatureArtworkSize, height: theme.metrics.homeFeatureArtworkSize)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.imageCornerRadius))
        .shadow(color: theme.colors.shadow.opacity(0.35), radius: theme.metrics.shadowRadius, y: theme.metrics.shadowYOffset)
        .overlay(alignment: .bottomLeading) {
            if hovering, canPlay {
                playButton.padding(theme.metrics.smallPadding)
            }
        }
    }

    private var playButton: some View {
        Button(action: play) {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.inverseText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme.colors.accent))
                .shadow(color: theme.colors.shadow.opacity(0.4), radius: theme.metrics.smallCornerRadius * 2, y: 2)
        }
        .buttonStyle(.plain)
        .help("Play")
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

/// Circular-portrait artist card (same shape as the search page's).
private struct ArtistTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let artist: SpotifyClient.Artist

    @State private var hovering = false

    var body: some View {
        Button {
            app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
        } label: {
            VStack(spacing: theme.metrics.smallPadding) {
                ArtworkView(url: artist.artworkURL, size: theme.metrics.artistArtworkSize) {
                    placeholderPortrait
                }
                .frame(width: theme.metrics.artistArtworkSize, height: theme.metrics.artistArtworkSize)
                .clipShape(Circle())
                .shadow(color: theme.colors.shadow.opacity(0.4), radius: theme.metrics.shadowRadius, y: theme.metrics.shadowYOffset)
                Text(artist.name)
                    .font(theme.typography.tileTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Artist")
                    .font(theme.typography.tileSubtitle)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(width: theme.metrics.artistArtworkSize + theme.metrics.smallPadding * 2)
            .padding(theme.metrics.smallPadding)
            .background(
                hovering ? theme.colors.cardHover.swiftUIStyle : AnyShapeStyle(Color.clear)
            )
            .cornerRadius(theme.metrics.cardCornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
    }

    private var placeholderPortrait: some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: theme.metrics.artistArtworkSize * 0.45))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}

/// One Your Library tile: square cover (URL or fixed asset), title, subtitle.
/// Click opens the destination; hover play starts the whole context.
private struct LibraryTile: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let title: String
    let subtitle: String
    let artworkURL: URL?
    var assetCover: String? = nil
    let onOpen: () -> Void
    var onPlay: (() -> Void)? = nil
    var linkURL: String? = nil

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            Text(title)
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
        .onTapGesture(perform: onOpen)
        .contextMenu {
            if let onPlay, app.isPlaybackReady {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play")
                }
            }
            if let linkURL {
                Divider()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(linkURL, forType: .string)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
        }
        .onHover { hovering = $0 }
        .linkCursor()
    }

    private var cover: some View {
        Group {
            if let assetCover {
                Image(assetCover)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkView(url: artworkURL, size: theme.metrics.collectionArtworkSize) {
                    placeholderCover
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.imageCornerRadius))
        .shadow(color: theme.colors.shadow.opacity(0.35), radius: theme.metrics.shadowRadius, y: theme.metrics.shadowYOffset)
        .overlay(alignment: .bottomLeading) {
            if hovering, let onPlay, app.isPlaybackReady {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.colors.inverseText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.colors.accent))
                        .shadow(color: theme.colors.shadow.opacity(0.4), radius: theme.metrics.smallCornerRadius * 2, y: 2)
                }
                .buttonStyle(.plain)
                .help("Play")
                        .padding(theme.metrics.smallPadding)
            }
        }
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
