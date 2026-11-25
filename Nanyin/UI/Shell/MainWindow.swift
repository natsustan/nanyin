import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar()
            if app.showsLibrary {
                ThreePaneLayout(preferredSidebar: sidebarWidth) {
                    Sidebar()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    SidebarDivider(
                        width: $sidebarWidth,
                        showsLyrics: app.showLyrics,
                        shellMetrics: shellMetrics
                    ) { savedSidebarWidth = sidebarWidth }
                        .zIndex(1)
                    RouteView(route: app.navigator.current)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.content)
                        .clipped()
                    if app.showLyrics {
                        LyricsPanel()
                            .clipped()
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    shellMetrics.width = width
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
    @State private var shellMetrics = ShellMetrics()
    @State private var spaceKey = SpaceKeyMonitor()
}

/// Non-observed width holder so `SidebarDivider` can clamp against the current
/// window width during drags without invalidating `MainWindow` on every resize pixel.
@MainActor
private final class ShellMetrics {
    var width: CGFloat = 1100
}

/// Strictly parent-driven three-pane shell (sidebar, 1-pt divider, main page,
/// optional lyrics pane). Never lets wide page content push sibling panes off
/// screen, and dynamically clamps side panes in narrow windows while keeping
/// the listener's saved sidebar width intact.
private struct ThreePaneLayout: Layout {
    static let minSidebar: CGFloat = 150
    static let maxSidebar: CGFloat = 360
    static let dividerWidth: CGFloat = 1
    static let minContent: CGFloat = 360
    static let preferredLyrics: CGFloat = LyricsPanel.width
    static let minLyrics: CGFloat = 240

    let preferredSidebar: CGFloat

    struct Allocation: Equatable {
        let sidebar: CGFloat
        let content: CGFloat
        let lyrics: CGFloat
    }

    static func maxSidebarWidth(total: CGFloat, showsLyrics: Bool) -> CGFloat {
        let available = max(0, total - dividerWidth)
        let reservedLyrics = showsLyrics ? minLyrics : 0
        return min(maxSidebar, max(minSidebar, available - minContent - reservedLyrics))
    }

    static func allocate(total: CGFloat, preferredSidebar: CGFloat, showsLyrics: Bool) -> Allocation {
        let available = max(0, total - dividerWidth)
        let desiredSidebar = min(max(preferredSidebar, minSidebar), maxSidebar)

        guard showsLyrics else {
            let sidebar = min(desiredSidebar, maxSidebarWidth(total: total, showsLyrics: false), available)
            return Allocation(sidebar: sidebar, content: max(0, available - sidebar), lyrics: 0)
        }

        let sideBudget = max(0, available - minContent)
        guard sideBudget >= minSidebar + minLyrics else {
            let sidebar = min(minSidebar, floor(available * 0.25))
            let lyrics = min(minLyrics, floor(available * 0.30))
            return Allocation(sidebar: sidebar, content: max(0, available - sidebar - lyrics), lyrics: lyrics)
        }

        // Preserve the user's chosen sidebar width up to `maxSidebarWidth`:
        // narrow lyrics toward its floor first, then clamp the sidebar.
        let lyrics = min(preferredLyrics, max(minLyrics, sideBudget - desiredSidebar))
        let sidebar = min(desiredSidebar, max(minSidebar, sideBudget - lyrics))
        return Allocation(sidebar: sidebar, content: max(0, available - sidebar - lyrics), lyrics: lyrics)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 1100, height: 700))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 3 else { return }
        let hasLyrics = subviews.count >= 4
        let widths = Self.allocate(total: bounds.width, preferredSidebar: preferredSidebar, showsLyrics: hasLyrics)

        let slotWidths = [widths.sidebar, Self.dividerWidth, widths.content] + (hasLyrics ? [widths.lyrics] : [])
        var x = bounds.minX
        for (subview, width) in zip(subviews, slotWidths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
    }
}

/// The 1-pt line between the sidebar and the page, draggable to resize the
/// sidebar as the 2010 client's was.
private struct SidebarDivider: View {
    @Binding var width: Double
    let showsLyrics: Bool
    let shellMetrics: ShellMetrics
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
                    .pointerStyle(.columnResize)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let origin: Double
                            if let existing = start {
                                origin = existing
                            } else {
                                origin = ThreePaneLayout.allocate(
                                    total: shellMetrics.width,
                                    preferredSidebar: width,
                                    showsLyrics: showsLyrics
                                ).sidebar
                                start = origin
                            }
                            let upper = ThreePaneLayout.maxSidebarWidth(
                                total: shellMetrics.width,
                                showsLyrics: showsLyrics
                            )
                            width = min(max(origin + drag.translation.width, ThreePaneLayout.minSidebar), upper)
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
                .id(detail.artistID)
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
