import NanyinKit
import SwiftUI

/// The source list: fixed destinations, the library, the playlists, and the
/// cover of what is playing at the bottom, as the 2010 client had it.
struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Read once here so a navigation redraws only the two rows whose
        // selection changed.
        let current = app.navigator.current
        let go = app.navigator.go
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.fixed, id: \.route) { item in
                        if let heading = item.heading { SidebarHeading(title: heading) }
                        SidebarRow(title: item.title, icon: item.icon, isSelected: current == item.route) {
                            go(item.route, false)
                        }
                    }
                    SidebarHeading(title: "Playlists")
                    ForEach(app.library.playlists) { playlist in
                        let route = Route.playlist(id: playlist.id, name: playlist.name)
                        SidebarRow(title: playlist.name, icon: "music.note.list", isSelected: current == route) {
                            go(route, false)
                        }
                    }
                    if let error = app.library.playlistsError {
                        Text(error)
                            .font(AquaFont.regular(10))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 6)
            }
            NowPlayingCover()
        }
        .background(Theme.sidebar)
    }

    private struct Item {
        var heading: String?
        let title: String
        let icon: String
        let route: Route
    }

    private static let fixed = [
        Item(title: "What's New", icon: "house", route: .whatsNew),
        Item(title: "Play Queue", icon: "list.bullet", route: .queue),
        Item(heading: "Library", title: "Starred", icon: "star", route: .likedSongs),
        Item(title: "Albums", icon: "square.stack", route: .albums),
        Item(title: "Artists", icon: "music.mic", route: .artists),
    ]
}

private struct SidebarHeading: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(AquaFont.bold(10))
            .foregroundStyle(Theme.sidebarHeading)
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .frame(width: 14)
                    .foregroundStyle(isSelected ? .white : Theme.sidebarHeading)
                Text(title)
                    .font(isSelected ? AquaFont.bold(11) : AquaFont.regular(11))
                    .foregroundStyle(isSelected ? .white : Theme.sidebarText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .shadow(color: .black.opacity(isSelected ? 0.5 : 0.3), radius: 0, y: 1)
            .padding(.horizontal, 10)
            .frame(height: 20)
            .background {
                if isSelected {
                    Theme.selection
                        .hairline(.top, .white.opacity(0.18))
                        .hairline(.bottom, .black.opacity(0.4))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The playing track's title and its cover, filling the sidebar's width,
/// or folded down to a thumbnail beside the title. The title opens the
/// album, each artist their page.
private struct NowPlayingCover: View {
    @Environment(AppModel.self) private var app
    @AppStorage("NowPlayingArtworkLarge") private var large = true
    @State private var hovering = false

    var body: some View {
        if let track = app.player.track {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    if !large {
                        Button { large = true } label: {
                            CoverImage(url: track.coverURL, size: 32)
                                .overlay { if hovering { ArtworkToggle(symbol: "arrow.up.left.and.arrow.down.right") } }
                        }
                        .buttonStyle(.plain)
                        .help("Show Large Artwork")
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        LinkText(parts: [(track.name, track.albumURI.flatMap(Route.init(uri:)))], color: Theme.text)
                            .font(AquaFont.bold(11))
                        if app.player.playingElsewhere {
                            Text("Playing on another device")
                                .font(AquaFont.regular(10))
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            LinkText(parts: track.artists.map { ($0.name, Route(uri: $0.uri)) }, color: Theme.secondaryText)
                                .font(AquaFont.regular(10))
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.graphite)
                .hairline(.top, Theme.graphiteEdge)
                if large {
                    Artwork(url: track.coverURL, placeholder: Theme.content)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            if hovering {
                                Button { large = false } label: {
                                    ArtworkToggle(symbol: "arrow.down.right.and.arrow.up.left")
                                }
                                .buttonStyle(.plain)
                                .help("Hide Large Artwork")
                                .padding(6)
                            }
                        }
                }
            }
            .onHover { hovering = $0 }
            .contextMenu { menu(track) }
        }
    }

    @ViewBuilder private func menu(_ track: CoreTrack) -> some View {
        TrackMenuContent(items: app.songMenu(
            uri: track.uri, name: track.name, album: track.albumURI.flatMap(Route.init(uri:)),
            artists: track.artists.map(TrackRow.Artist.init)))
        Divider()
        Button(large ? "Hide Large Artwork" : "Show Large Artwork") { large.toggle() }
    }
}

/// The small dark button over the artwork that folds it up or out.
private struct ArtworkToggle: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.artworkButtonGlyph)
            .frame(width: 16, height: 16)
            .background(Theme.artworkButton, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.artworkButtonEdge, lineWidth: 0.5))
    }
}
