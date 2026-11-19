import NanyinKit
import SwiftUI

struct AlbumPage: View {
    @Environment(AppModel.self) private var app
    let detail: AlbumDetail

    var body: some View {
        VStack(spacing: 0) {
            if let album = detail.album {
                PageHeader(title: album.name, subtitle: subtitle(album)) {
                    CoverImage(url: album.images?.best(minimum: 200), size: 96)
                } accessory: {
                    Button("Play") { app.player.play(contextURI: album.uri) }
                        .buttonStyle(TexturedButtonStyle())
                }
            } else {
                PageHeader(title: "Album", subtitle: detail.error ?? "Loading…")
            }
            if let tracks = detail.tracks {
                TrackListTable(list: tracks, columns: [.indicator, .track, .artist, .time])
            } else {
                Theme.content
            }
        }
    }

    private func subtitle(_ album: Album) -> String {
        [album.artists.names, album.releaseYear, album.total_tracks.map { "\($0) tracks" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct ArtistPage: View {
    @Environment(AppModel.self) private var app
    let detail: ArtistDetail

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: detail.artist?.name ?? "Artist",
                subtitle: detail.error ?? detail.artist?.genres?.prefix(3).joined(separator: ", ") ?? ""
            ) {
                CoverImage(url: detail.artist?.images?.best(minimum: 200), size: 72)
            } accessory: {
                if let artist = detail.artist {
                    Button("Play") { app.player.play(contextURI: artist.uri) }
                        .buttonStyle(TexturedButtonStyle())
                }
            }
            if !detail.albums.isEmpty {
                GraphiteHeader { Text("Albums and Singles") }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(detail.albums) { AlbumTile(album: $0) }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .frame(height: 156)
                .background(Theme.content)
            }
            GraphiteHeader { Text("Popular") }
            if let tracks = detail.topTracks {
                TrackListTable(list: tracks, columns: [.indicator, .track, .time, .popularity, .album])
            } else {
                Theme.content
            }
        }
    }
}

struct AlbumTile: View {
    @Environment(AppModel.self) private var app
    let album: AlbumSummary

    var body: some View {
        Button {
            app.navigator.go(to: .album(id: album.id))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                CoverImage(url: album.images?.best(minimum: 200), size: 110)
                Text(album.name)
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.text)
                Text(album.releaseYear ?? "")
                    .font(AquaFont.regular(10))
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .frame(width: 110, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// Album art with a thin dark frame, the way the 2010 client framed covers.
struct CoverImage: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Theme.hex(0x404040)
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}
