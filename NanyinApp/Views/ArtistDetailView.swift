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

    let title: String
    let artworkURL: URL?
    let contextKey: String

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
        Group {
            if let error = app.tracksError[contextKey] {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                VStack(spacing: 12) {
                    if app.loadingTracks {
                        ProgressView()
                        Text("Loading top tracks…")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("No top tracks")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Single vertical scroller for the whole page: top tracks are
                // only ~10 rows, so plain rows (no NSTableView recycling) are
                // fine — this lets Albums/Singles sit BELOW the track list.
                // Horizontal card rows inside are perpendicular-axis scrollers.
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        header
                        Divider().overlay(Color(white: 0.18))
                        topTracksHeader
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, index: index, contextKey: contextKey)
                        }
                        discography
                    }
                }
            }
        }
        .background(Theme.background)
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
                Text("\(tracks.count) top tracks · \(albums.count) albums · \(singles.count) singles")
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

    @ViewBuilder
    private var portrait: some View {
        Group {
            if let url = artworkURL {
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
