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

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                header
                partialErrorNotice
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
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
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            greeting
            Spacer()
            if app.isLoadingHome {
                ProgressView()
                    .controlSize(.small)
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
        } else if !app.hasHomeData, !app.isLoadingHome, !app.homeErrors.isEmpty {
            fullErrorState
        } else {
            if !app.hasHomeData {
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
        if app.hasHomeData, !app.homeErrors.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Couldn’t load some sections.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                // Non-force load retries exactly the failed sections —
                // rendered sections keep their content.
                Button("Retry") {
                    app.loadHome()
                }
                .buttonStyle(.link)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your home…")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var fullErrorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Couldn’t load your home")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(app.homeErrors.values.first ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                // Nothing is loaded in this state — a non-force load
                // requests every missing section anyway.
                app.loadHome()
            } label: {
                Text("Retry")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    /// All sections loaded successfully but the account has no history yet.
    private var freshAccountHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.house")
                .foregroundStyle(Theme.textSecondary)
            Text("Nothing here yet — play something and it will show up.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(14)
        .background(Color(white: 0.09))
        .cornerRadius(8)
    }

    // MARK: - Sections

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        if !app.homeRecentlyPlayed.isEmpty {
            section(title: "Recently Played") {
                // Bounded horizontal strip (≤10 cards) — perpendicular to
                // the page's single vertical scroll region.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
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
                            contextKey: AppModel.homeTopTracksContextKey
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
                    HStack(spacing: 12) {
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
                columns: [GridItem(.adaptive(minimum: 170), spacing: 16)],
                spacing: 16
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
            onPlay: { app.playLikedSongs() },
            linkURL: nil
        )
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}

// MARK: - Cards and tiles (hover state is card-local — never in the parent)

private struct RefreshButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? .white : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(hovering ? Color(white: 0.16) : Color(white: 0.13))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Refresh Home")
        .onHover { hovering = $0 }
    }
}

/// One Recently Played card: square cover, title, subtitle. Click opens the
/// context's page; hover play starts its server-resolved context.
private struct RecentCard: View {
    @Environment(AppModel.self) private var app
    let card: HomeFeed.Card

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            Text(card.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(card.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .padding(8)
        .background(hovering ? Color(white: 0.13) : .clear)
        .cornerRadius(8)
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
        Group {
            if let url = card.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderCover
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 134, height: 134)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .overlay(alignment: .bottomLeading) {
            if hovering, canPlay {
                playButton.padding(8)
            }
        }
    }

    private var playButton: some View {
        Button(action: play) {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.accent))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("Play")
    }

    private var placeholderCover: some View {
        ZStack {
            Color(white: 0.14)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Circular-portrait artist card (same shape as the search page's).
private struct ArtistTile: View {
    @Environment(AppModel.self) private var app
    let artist: SpotifyClient.Artist

    @State private var hovering = false

    var body: some View {
        Button {
            app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let url = artist.artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            placeholderPortrait
                        }
                    } else {
                        placeholderPortrait
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Text(artist.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Artist")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 104)
            .padding(8)
            .background(hovering ? Color(white: 0.13) : .clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .linkCursor()
    }

    private var placeholderPortrait: some View {
        ZStack {
            Color(white: 0.14)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// One Your Library tile: square cover (URL or fixed asset), title, subtitle.
/// Click opens the destination; hover play starts the whole context.
private struct LibraryTile: View {
    @Environment(AppModel.self) private var app
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color(white: 0.13) : .clear)
        .cornerRadius(8)
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
            } else if let url = artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderCover
                }
            } else {
                placeholderCover
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .overlay(alignment: .bottomLeading) {
            if hovering, let onPlay, app.isPlaybackReady {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.accent))
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .help("Play")
                .padding(8)
            }
        }
    }

    private var placeholderCover: some View {
        ZStack {
            Color(white: 0.14)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
