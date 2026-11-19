import NanyinKit
import SwiftUI

/// The source list: fixed destinations, the library, the playlists, and the
/// cover of what is playing at the bottom, as the 2010 client had it.
struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SidebarRow(title: "What's New", icon: "house", route: .whatsNew)
                    SidebarRow(title: "Play Queue", icon: "list.bullet", route: .queue)
                    SidebarHeading(title: "Library")
                    SidebarRow(title: "Songs", icon: "star", route: .likedSongs)
                    SidebarRow(title: "Albums", icon: "square.stack", route: .albums)
                    SidebarRow(title: "Artists", icon: "music.mic", route: .artists)
                    SidebarHeading(title: "Playlists")
                    ForEach(app.library.playlists) { playlist in
                        SidebarRow(
                            title: playlist.name,
                            icon: "music.note.list",
                            route: .playlist(id: playlist.id, name: playlist.name))
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
            .scrollIndicators(.automatic)
            NowPlayingCover()
        }
        .background(Theme.sidebar)
    }
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
    @Environment(AppModel.self) private var app
    let title: String
    let icon: String
    let route: Route

    var body: some View {
        let selected = app.navigator.current == route
        Button {
            app.navigator.go(to: route)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .frame(width: 14)
                    .foregroundStyle(selected ? .white : Theme.sidebarHeading)
                Text(title)
                    .font(selected ? AquaFont.bold(11) : AquaFont.regular(11))
                    .foregroundStyle(selected ? .white : Theme.sidebarText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .shadow(color: .black.opacity(selected ? 0.5 : 0.3), radius: 0, y: 1)
            .padding(.horizontal, 10)
            .frame(height: 20)
            .background {
                if selected {
                    Theme.selection
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 1) }
                        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.4)).frame(height: 1) }
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
                    Text(track.artistNames)
                        .font(AquaFont.regular(10))
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.graphite)
                .overlay(alignment: .top) { Rectangle().fill(Theme.graphiteEdge).frame(height: 1) }
                AsyncImage(url: track.coverURL) { image in
                    image.resizable().aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    Theme.content
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
            }
        }
    }
}
