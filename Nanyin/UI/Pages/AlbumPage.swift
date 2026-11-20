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
                TrackListTable(list: tracks, columns: [.indicator, .star, .track, .artist, .time])
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
                        ForEach(detail.albums) { Tile(album: $0, subtitle: $0.releaseYear ?? "", size: 110) }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .frame(height: 156)
                .background(Theme.content)
            }
            GraphiteHeader { Text("Popular") }
            if let tracks = detail.topTracks {
                TrackListTable(list: tracks, columns: [.indicator, .star, .track, .time, .album])
            } else {
                Text(detail.topTracksError ?? "Loading…")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.content)
            }
        }
    }
}

/// A cover with a caption that opens a page, for grids and shelves.
struct Tile: View {
    @Environment(AppModel.self) private var app
    let title: String
    var subtitle = ""
    let images: [SpotifyImage]?
    let route: Route
    var size: CGFloat = 130

    var body: some View {
        Button { app.navigator.go(to: route) } label: {
            VStack(alignment: .leading, spacing: 3) {
                CoverImage(url: images?.best(minimum: 200), size: size)
                Text(title)
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(AquaFont.regular(10))
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

extension Tile {
    init(album: AlbumSummary, subtitle: String, size: CGFloat = 130) {
        self.init(title: album.name, subtitle: subtitle, images: album.images, route: .album(id: album.id), size: size)
    }

    init(album: Album) {
        self.init(title: album.name, subtitle: album.artists.names, images: album.images, route: .album(id: album.id))
    }

    init(artist: Artist) {
        self.init(title: artist.name, images: artist.images, route: .artist(id: artist.id))
    }
}

/// Album art with a thin dark frame, the way the 2010 client framed covers.
struct CoverImage: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Artwork(url: url, placeholder: Theme.hex(0x404040))
            .frame(width: size, height: size)
            .clipped()
            .overlay(Rectangle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

/// An image from `ImageLoader`, filling its frame; shown at once when cached.
struct Artwork: View {
    let url: URL?
    let placeholder: Color
    @State private var loaded: (url: URL, image: NSImage)?

    var body: some View {
        let image = url.flatMap { url in loaded?.url == url ? loaded?.image : ImageLoader.shared.cached(url) }
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url, ImageLoader.shared.cached(url) == nil, let image = await ImageLoader.shared.image(url) else { return }
            loaded = (url, image)
        }
    }
}
