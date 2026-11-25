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

/// A cover with a caption that opens a page, for grids and shelves.
/// Expands to fill its grid column width with a square cover.
struct Tile: View {
    @Environment(AppModel.self) private var app
    let title: String
    var subtitle = ""
    let images: [SpotifyImage]?
    let route: Route
    var playURI: String? = nil
    var openTitle = "Open"
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Button { app.navigator.go(to: route) } label: {
                    CoverImage(url: images?.best(minimum: 260))
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering = $0 }
        .contextMenu {
            if let playURI {
                Button("Play") { app.player.play(contextURI: playURI) }
            }
            Button(openTitle) { app.navigator.go(to: route) }
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
    init(album: AlbumSummary, subtitle: String) {
        self.init(
            title: album.name, subtitle: subtitle, images: album.images,
            route: .album(id: album.id), playURI: album.uri, openTitle: "Open Album")
    }

    init(album: Album) {
        self.init(
            title: album.name, subtitle: album.artists.names, images: album.images,
            route: .album(id: album.id), playURI: album.uri, openTitle: "Open Album")
    }

    init(artist: Artist, subtitle: String = "") {
        self.init(
            title: artist.name, subtitle: subtitle, images: artist.images,
            route: .artist(id: artist.id), playURI: artist.uri, openTitle: "Open Artist")
    }

    init(playlist: Playlist) {
        self.init(
            title: playlist.name, subtitle: playlist.owner.display_name ?? "Spotify", images: playlist.images,
            route: .playlist(id: playlist.id), playURI: playlist.uri, openTitle: "Open Playlist")
    }
}

/// Computes discrete column counts and horizontal padding for responsive cover
/// grids. Uses `.flexible(minimum: 0)` columns so `LazyVGrid` scales smoothly
/// during window resize and never locks a pane's minimum width.
struct CoverGridMetrics: Equatable {
    static let gap: CGFloat = 18
    static let minTile: CGFloat = 136
    static let maxTile: CGFloat = 172

    let columns: Int
    let padding: CGFloat

    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0, maximum: Self.maxTile), spacing: Self.gap, alignment: .top), count: columns)
    }

    static var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: minTile, maximum: maxTile), spacing: gap, alignment: .top)]
    }

    static func compute(width: CGFloat) -> CoverGridMetrics {
        let padding: CGFloat = width < 320 ? 14 : 22
        let inner = max(80, width - padding * 2)
        let columns = max(1, Int((inner + gap) / (minTile + gap)))
        return CoverGridMetrics(columns: columns, padding: padding)
    }
}

/// Album art with a thin dark frame and subtle inner highlight, the way the
/// 2010 client framed covers. Pass `size` for fixed headers/thumbnails, or omit
/// it to fill the surrounding grid column as a 1:1 square.
struct CoverImage: View {
    let url: URL?
    var size: CGFloat? = nil
    var fallbackSymbol: String?

    var body: some View {
        let art = Artwork(url: url, placeholder: Theme.vinylBackground) {
            if let fallbackSymbol {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: (size ?? 140) * 0.32, weight: .light))
                    .foregroundStyle(Theme.secondaryText.opacity(0.45))
            } else {
                VinylPlaceholder(insetRatio: 0.14)
            }
        }
        Group {
            if let size {
                ZStack { art }
                    .frame(width: size, height: size)
            } else {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { art }
            }
        }
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

struct LibraryToggleButton: View {
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
