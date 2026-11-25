import NanyinKit
import SwiftUI

/// The unified metal title bar and toolbar: traffic lights and the window
/// title on top, history and search below.
struct MainToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var appearsActive
    @State private var query = ""
    @State private var debounce: Task<Void, Never>?

    static let height: CGFloat = 54
    static let compactHeight: CGFloat = 26

    var body: some View {
        let navigator = app.navigator
        let showFull = app.showsLibrary
        ZStack(alignment: .top) {
            TitleBarDragArea()
            Text("Nanyin")
                .font(AquaFont.regular(14))
                .foregroundStyle(Theme.metalText.opacity(appearsActive ? 1 : 0.5))
                .embossed()
                .padding(.top, 3)
                .allowsHitTesting(false)
            TrafficLights()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.top, showFull ? 2 : 5)
            if showFull {
                HStack(spacing: 10) {
                    HStack(spacing: -1) {
                        Button(action: navigator.goBack) { Image(systemName: "chevron.left") }
                            .buttonStyle(TexturedButtonStyle(width: 28))
                            .disabled(!navigator.canGoBack)
                            .keyboardShortcut("[", modifiers: .command)
                        Button(action: navigator.goForward) { Image(systemName: "chevron.right") }
                            .buttonStyle(TexturedButtonStyle(width: 28))
                            .disabled(!navigator.canGoForward)
                            .keyboardShortcut("]", modifiers: .command)
                    }
                    AquaSearchField(text: $query, onSubmit: { search(replacing: false) }, focusRequest: navigator.searchFocusRequests)
                        .frame(width: 220)
                        .help("Search songs, artists, albums, playlists, or paste a Spotify link")
                        .onChange(of: query) { scheduleSearch() }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 1)
            }
        }
        .frame(height: showFull ? Self.height : Self.compactHeight)
        .background(Theme.metal(active: appearsActive))
        .hairline(.top, .white.opacity(0.7))
        .hairline(.bottom, Theme.metalEdge)
        .onChange(of: showFull) { _, visible in
            if !visible {
                debounce?.cancel()
                debounce = nil
                query = ""
            }
        }
    }

    /// Typing searches after a pause, refining the current search page
    /// instead of adding a history entry per pause. Pasting a Spotify link
    /// opens it directly instead of searching the URL text.
    private func scheduleSearch() {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let target = SpotifyLink.parse(text) {
            if target.id.count >= 22 {
                query = ""
                app.openSpotifyLink(target)
            }
            return
        }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            search(replacing: true)
        }
    }

    private func search(replacing: Bool) {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let target = SpotifyLink.parse(text) {
            query = ""
            app.openSpotifyLink(target)
            return
        }
        if case .search = app.navigator.current {
            app.navigator.go(to: .search(text), replacing: replacing)
        } else {
            app.navigator.go(to: .search(text))
        }
    }
}
