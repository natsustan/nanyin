import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar()
            if app.showsLibrary {
                HStack(spacing: 0) {
                    Sidebar()
                        .frame(width: sidebarWidth)
                    SidebarDivider(width: $sidebarWidth) { savedSidebarWidth = sidebarWidth }
                    RouteView(route: app.navigator.current)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.content)
                }
                PlaybackNotice()
                PlayerBar()
            } else {
                OnboardingView()
            }
        }
        .background(Theme.content)
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .frame(minWidth: 780, minHeight: 480)
        .preferredColorScheme(.dark)
        .onAppear { spaceKey.install { if app.showsLibrary { app.player.togglePlayPause() } } }
        .sheet(item: Bindable(app).credits) { CreditsSheet(credits: $0) }
    }

    /// Live while dragging; saved when the drag ends.
    @State private var sidebarWidth = UserDefaults.standard.object(forKey: "SidebarWidth") as? Double ?? 200
    @AppStorage("SidebarWidth") private var savedSidebarWidth = 200.0
    @State private var spaceKey = SpaceKeyMonitor()
}

/// The 1-pt line between the sidebar and the page, draggable to resize the
/// sidebar as the 2010 client's was.
private struct SidebarDivider: View {
    @Binding var width: Double
    let onEnd: () -> Void
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .columnResizePointer()
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let origin = start ?? width
                            start = origin
                            width = min(max(origin + drag.translation.width, 150), 360)
                        }
                        .onEnded { _ in
                            start = nil
                            onEnd()
                        })
            }
    }
}

/// Space plays and pauses in the main window, unless a text field or a
/// button (with Full Keyboard Access) wants it; held down, it acts once.
@MainActor
private final class SpaceKeyMonitor {
    private var monitor: Any?

    func install(_ action: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49, !event.isARepeat else { return event }
            let responder = event.window?.firstResponder
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
                  let window = event.window, window === NSApp.mainWindow, window.attachedSheet == nil,
                  !(responder is NSText), !(responder is NSControl) || responder is NSTableView
            else { return event }
            MainActor.assumeIsolated(action)
            return nil
        }
    }
}

private struct RouteView: View {
    @Environment(AppModel.self) private var app
    let route: Route

    var body: some View {
        let content = app.library.content(for: route)
        switch (route, content) {
        case (.queue, _):
            PlayQueuePage()
        case (.albums, .albums(let albums)?):
            GridPage(title: "Albums", pager: albums) { Tile(album: $0) }
        case (.artists, .artists(let artists)?):
            GridPage(title: "Artists", pager: artists) { Tile(artist: $0) }
        case (.whatsNew, .whatsNew(let model)?):
            WhatsNewPage(model: model)
        case (.likedSongs, .tracks(let list)?):
            StarredPage(list: list)
        case (.playlist(let id), .tracks(let list)?):
            PlaylistPage(playlist: app.library.playlist(id), list: list)
                .id(id)
        case (_, .album(let detail)?):
            AlbumPage(detail: detail)
        case (_, .artist(let detail)?):
            ArtistPage(detail: detail)
        case (.search(let query), .search(let results)?):
            SearchPage(query: query, results: results)
        default:
            Theme.content
        }
    }
}

/// A strip above the player bar while playback on this Mac is not ready.
private struct PlaybackNotice: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let session = app.session
        var message: String?
        var actions: [(title: String, run: () -> Void)] = []
        switch session.state {
        case .ready:
            break
        case .notSetUp:
            message = "To play music on this Mac, approve playback with Spotify once."
            actions = [("Set Up Playback…", session.authorize)]
        case .authorizing:
            message = "Waiting for your approval in the browser…"
            if session.authorizeURL != nil {
                actions.append(("Open Again", session.reopenAuthorizeURL))
            }
            actions.append(("Cancel", session.cancelAuthorize))
        case .connecting:
            message = "Connecting to Spotify…"
        case .waiting(let until, let reason):
            message = "\(reason). Trying again \(until.formatted(.relative(presentation: .named)))."
            actions = [("Try Now", session.retry)]
        case .needsAuthorization(let reason):
            message = reason
            actions = [("Approve Playback…", session.authorize)]
        case .failed(let reason):
            message = reason
            actions = [("Try Again", session.retry)]
        }
        // A failed action outranks the standing state until dismissed.
        if let report = app.notices.message {
            message = report
            actions = [("Dismiss", app.notices.dismiss)]
        }
        return Group {
            if let message {
                HStack(spacing: 8) {
                    Text(message)
                        .font(AquaFont.regular(12))
                        .foregroundStyle(Theme.metalText)
                        .lineLimit(2)
                    Spacer()
                    ForEach(actions, id: \.title) { action in
                        Button(action.title, action: action.run)
                            .buttonStyle(TexturedButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(LinearGradient(colors: [Theme.hex(0xFFF6C6), Theme.hex(0xEADB8E)], startPoint: .top, endPoint: .bottom))
                .hairline(.top, Theme.hex(0x8A7A2A))
                .environment(\.colorScheme, .light)
            }
        }
    }
}
