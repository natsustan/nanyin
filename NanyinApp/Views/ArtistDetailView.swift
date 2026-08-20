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
                Divider().overlay(Color(white: 0.18))
                trackContent
                discography
            }
        }
        .background(Theme.background)
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
                    .foregroundStyle(.orange)
                Text(error)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if tracks.isEmpty {
            VStack(spacing: 12) {
                if app.isLoadingTracks(contextKey: contextKey) {
                    ProgressView()
                    Text("Loading top tracks…")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("No top tracks")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            // Top tracks are only ~10 rows, so plain rows (no NSTableView
            // recycling) are fine. Horizontal card rows below use the
            // perpendicular axis and keep this as a single vertical scroller.
            topTracksHeader
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, index: index, contextKey: contextKey)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            portrait
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("ARTIST")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(headerStats)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    if let first = tracks.first {
                        app.play(track: first, contextKey: contextKey)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("PLAY")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Theme.accent)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
                .opacity(tracks.isEmpty ? 0.5 : 1)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(Theme.background)
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
    private var portrait: some View {
        Group {
            if let url = resolvedArtworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderPortrait
                }
            } else {
                placeholderPortrait
            }
        }
        .clipShape(Circle())
    }

    private var placeholderPortrait: some View {
        ZStack {
            Color(white: 0.14)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textSecondary)
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
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 28)
            // Horizontal strip above the vertical List — perpendicular axes,
            // so the single-scroll-region rule (no same-axis nesting) holds.
            // LazyHStack keeps AsyncImages lazy for long discographies.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { album in
                        AlbumCard(album: album)
                    }
                }
                .padding(.horizontal, 28)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var topTracksHeader: some View {
        HStack(spacing: 10) {
            Text("Top tracks")
                .font(.system(size: 14, weight: .bold))
            Text("\(tracks.count)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

/// Square-cover album card. Hover state is card-local (same rule as rows).
private struct AlbumCard: View {
    @Environment(AppModel.self) private var app
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
            VStack(alignment: .leading, spacing: 8) {
                cover
                Text(album.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(album.year ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 128, alignment: .leading)
            .padding(8)
            .background(hovering ? Color(white: 0.13) : .clear)
            .cornerRadius(6)
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
        Group {
            if let url = album.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderCover
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private var placeholderCover: some View {
        ZStack {
            Color(white: 0.14)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
