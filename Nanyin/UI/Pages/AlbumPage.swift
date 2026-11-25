import AppKit
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
                    HStack(spacing: 6) {
                        LibraryToggleButton(
                            status: detail.libraryStatus,
                            addedTitle: "Saved",
                            addTitle: "Save",
                            disabled: detail.isSaving,
                            toggle: detail.toggleSave,
                            retry: detail.retryLibraryStatus
                        )
                        Button("Play") { app.player.play(contextURI: album.uri) }
                            .buttonStyle(TexturedButtonStyle())
                    }
                }
            } else {
                PageHeader(title: "Album", subtitle: detail.error ?? "Loading…")
            }
            if let tracks = detail.tracks {
                TrackListTable(list: tracks, columns: [.star, .track, .artist, .time])
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
                    HStack(spacing: 6) {
                        LibraryToggleButton(
                            status: detail.libraryStatus,
                            addedTitle: "Following",
                            addTitle: "Follow",
                            disabled: detail.isUpdatingFollow,
                            toggle: detail.toggleFollow,
                            retry: detail.retryLibraryStatus
                        )
                        Button("Play") { app.player.play(contextURI: artist.uri) }
                            .buttonStyle(TexturedButtonStyle())
                    }
                }
            }
            if let message = detail.albumsError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Albums and Singles")
                        .font(AquaFont.bold(13.5))
                        .foregroundStyle(Theme.green)
                        .engraved()
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                    PlaceholderText(message: message)
                        .frame(height: 54)
                }
                .background(Theme.content)
                EtchedDivider()
            } else if !detail.albums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Albums and Singles")
                        .font(AquaFont.bold(13.5))
                        .foregroundStyle(Theme.green)
                        .engraved()
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(detail.albums) { Tile(album: $0, subtitle: $0.releaseYear ?? "", size: 120) }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 174)
                }
                .background(Theme.content)
                EtchedDivider()
            }
            HStack {
                Text("Popular")
                    .font(AquaFont.bold(13.5))
                    .foregroundStyle(Theme.green)
                    .engraved()
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.content)
            popular
        }
    }

    @ViewBuilder private var popular: some View {
        let pages = detail.topTracks.pages
        if pages.items.isEmpty {
            PlaceholderText(
                message: pages.error ?? (pages.isLoading ? "Loading…" : "No popular songs."),
                retry: pages.error == nil ? nil : { pages.retry() })
        } else {
            TrackListTable(list: detail.topTracks, columns: [.star, .track, .time, .popularity, .album])
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
    var playURI: String? = nil
    var size: CGFloat = 136
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Button { app.navigator.go(to: route) } label: {
                    CoverImage(url: images?.best(minimum: 260), size: size)
                }
                .buttonStyle(.plain)
                if hovering, let playURI {
                    Button { app.player.play(contextURI: playURI) } label: {
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

            Button { app.navigator.go(to: route) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AquaFont.bold(12))
                        .foregroundStyle(Theme.text)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AquaFont.regular(11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .lineLimit(1)
                .frame(width: size, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: size, alignment: .leading)
        .onHover { hovering = $0 }
        .contextMenu {
            if let playURI {
                Button("Play") { app.player.play(contextURI: playURI) }
            }
            Button("Open") { app.navigator.go(to: route) }
            if let playURI {
                Divider()
                Button("Copy Spotify Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Route.webLink(for: playURI), forType: .string)
                }
            }
        }
    }
}

extension Tile {
    init(album: AlbumSummary, subtitle: String, size: CGFloat = 136) {
        self.init(
            title: album.name, subtitle: subtitle, images: album.images,
            route: .album(id: album.id), playURI: album.uri, size: size)
    }

    init(album: Album) {
        self.init(
            title: album.name, subtitle: album.artists.names, images: album.images,
            route: .album(id: album.id), playURI: album.uri)
    }

    init(artist: Artist) {
        self.init(
            title: artist.name, images: artist.images,
            route: .artist(id: artist.id), playURI: artist.uri)
    }
}

/// Album art with a thin dark frame and subtle inner highlight, the way the
/// 2010 client framed covers.
struct CoverImage: View {
    let url: URL?
    let size: CGFloat
    var fallbackSymbol: String?

    var body: some View {
        ZStack {
            Artwork(url: url, placeholder: Theme.vinylBackground) {
                if let fallbackSymbol {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.32, weight: .light))
                        .foregroundStyle(Theme.secondaryText.opacity(0.45))
                } else {
                    VinylPlaceholder(insetRatio: 0.14)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(Rectangle().strokeBorder(.white.opacity(0.08), lineWidth: 1).padding(1))
        .overlay(Rectangle().strokeBorder(.black.opacity(0.65), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

/// The quiet dark vinyl record silhouette shown when album art is missing or
/// loading, inspired by rsms's 2010 Spotify-for-Mac Now Playing cover slot.
struct VinylPlaceholder: View {
    var insetRatio: CGFloat = 0.08

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let disc = side * (1 - insetRatio * 2)
            ZStack {
                Theme.vinylBackground
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.vinylDiscInner, Theme.vinylDiscOuter, Theme.vinylDiscInner],
                            center: .center,
                            startRadius: disc * 0.12,
                            endRadius: disc * 0.5
                        )
                    )
                    .frame(width: disc, height: disc)
                    .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                ForEach([0.84, 0.72, 0.60], id: \.self) { ratio in
                    Circle()
                        .strokeBorder(Theme.vinylGroove, lineWidth: 0.75)
                        .frame(width: disc * ratio, height: disc * ratio)
                }
                Circle()
                    .fill(Theme.vinylLabel)
                    .frame(width: disc * 0.34, height: disc * 0.34)
                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
                Circle()
                    .fill(Theme.vinylSpindle)
                    .frame(width: max(4, disc * 0.08), height: max(4, disc * 0.08))
                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// An image from `ImageLoader`, filling its frame; shown at once when cached.
struct Artwork<Fallback: View>: View {
    let url: URL?
    let placeholder: Color
    @ViewBuilder var fallback: () -> Fallback
    @State private var loaded: (url: URL, image: NSImage)?

    var body: some View {
        let image = url.flatMap { url in loaded?.url == url ? loaded?.image : ImageLoader.shared.cached(url) }
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    placeholder
                    fallback()
                }
            }
        }
        .task(id: url) {
            guard let url, ImageLoader.shared.cached(url) == nil, let image = await ImageLoader.shared.image(url) else { return }
            loaded = (url, image)
        }
    }
}

extension Artwork where Fallback == EmptyView {
    init(url: URL?, placeholder: Color) {
        self.init(url: url, placeholder: placeholder, fallback: { EmptyView() })
    }
}

private struct LibraryToggleButton: View {
    let status: LibraryStatus
    let addedTitle: String
    let addTitle: String
    let disabled: Bool
    let toggle: () -> Void
    let retry: () -> Void

    var body: some View {
        switch status {
        case .loading:
            EmptyView()
        case .known(let isAdded):
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text(isAdded ? addedTitle : addTitle)
                }
            }
            .buttonStyle(TexturedButtonStyle())
            .disabled(disabled)
        case .failed(let reason):
            Button(action: retry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                    Text("Retry \(addTitle)")
                }
            }
            .buttonStyle(TexturedButtonStyle())
            .help("Couldn't check library status: \(reason). Click to try again.")
        }
    }
}
