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

/// The playing track's title and its cover, filling the sidebar's width.
private struct NowPlayingCover: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let track = app.player.track {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(AquaFont.bold(11))
                        .foregroundStyle(Theme.text)
                    Text(app.player.playingElsewhere ? "Playing on another device" : track.artistNames)
                        .font(AquaFont.regular(10))
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.graphite)
                .hairline(.top, Theme.graphiteEdge)
                Artwork(url: track.coverURL, placeholder: Theme.content)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
            }
        }
    }
}
