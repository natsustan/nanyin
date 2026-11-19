import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar()
            switch app.account.state {
            case .signedIn:
                HStack(spacing: 0) {
                    Sidebar()
                        .frame(width: 200)
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    RouteView(route: app.navigator.current)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.content)
                }
                PlaybackNotice()
                PlayerBar()
            default:
                OnboardingView()
            }
        }
        .background(Theme.content)
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .frame(minWidth: 780, minHeight: 480)
        .preferredColorScheme(.dark)
    }
}

private struct RouteView: View {
    @Environment(AppModel.self) private var app
    let route: Route

    var body: some View {
        switch route {
        case .whatsNew:
            WhatsNewPage()
        case .queue:
            PagePlaceholder(title: "Play Queue", message: "Songs you add to the queue appear here.")
        case .likedSongs:
            if let list = app.library.trackList(for: route) {
                TrackListPage(title: "Songs", list: list, columns: [.indicator, .track, .artist, .time, .album, .added])
            }
        case .albums:
            PagePlaceholder(title: "Albums")
        case .artists:
            PagePlaceholder(title: "Artists")
        case .playlist(_, let name):
            if let list = app.library.trackList(for: route) {
                TrackListPage(title: name, list: list).id(route)
            }
        case .album(let id):
            AlbumPage(id: id).id(route)
        case .artist(let id):
            ArtistPage(id: id).id(route)
        case .search(let query):
            SearchPage(query: query)
        }
    }
}

/// A strip above the player bar while playback on this Mac is not ready.
private struct PlaybackNotice: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let session = app.session
        let message: String?
        let action: (title: String, run: () -> Void)?
        switch session.state {
        case .ready:
            message = app.player.lastError
            action = message == nil ? nil : ("Dismiss", { app.player.lastError = nil })
        case .notSetUp:
            message = "To play music on this Mac, approve playback with Spotify once."
            action = ("Set Up Playback…", session.authorize)
        case .authorizing:
            message = "Waiting for your approval in the browser…"
            action = nil
        case .connecting:
            message = "Connecting to Spotify…"
            action = nil
        case .waiting(let until, let reason):
            message = "\(reason). Trying again \(until.formatted(.relative(presentation: .named)))."
            action = ("Try Now", session.retry)
        case .needsAuthorization(let reason):
            message = reason
            action = ("Approve Playback…", session.authorize)
        case .failed(let reason):
            message = reason
            action = ("Try Again", session.retry)
        }
        return Group {
            if let message {
                HStack(spacing: 10) {
                    Text(message)
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.metalText)
                        .lineLimit(2)
                    Spacer()
                    if let action {
                        Button(action.title, action: action.run)
                            .buttonStyle(TexturedButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(LinearGradient(colors: [Theme.hex(0xFFF6C6), Theme.hex(0xEADB8E)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(Theme.hex(0x8A7A2A)).frame(height: 1) }
                .environment(\.colorScheme, .light)
            }
        }
    }
}
