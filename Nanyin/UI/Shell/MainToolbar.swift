import SwiftUI

/// The unified metal title bar and toolbar: traffic lights and the window
/// title on top, history and search below, the account on the right.
struct MainToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var appearsActive
    @State private var query = ""
    @State private var debounce: Task<Void, Never>?

    static let height: CGFloat = 54

    var body: some View {
        let navigator = app.navigator
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
                .padding(.top, 2)
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
                    .onChange(of: query) { scheduleSearch() }
                Spacer()
                if app.account.profile != nil {
                    accountMenu
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 1)
        }
        .frame(height: Self.height)
        .background(Theme.metal(active: appearsActive))
        .hairline(.top, .white.opacity(0.7))
        .hairline(.bottom, Theme.metalEdge)
    }

    private var accountMenu: some View {
        Menu {
            if let profile = app.account.profile {
                Text(profile.isPremium ? "\(profile.name) · Premium" : profile.name)
            }
            Divider()
            Button("Sign Out") { Task { await app.signOut() } }
        } label: {
            Text(app.account.profile?.name ?? "")
                .font(AquaFont.regular(12))
        }
        .menuStyle(.button)
        .buttonStyle(TexturedButtonStyle())
        .fixedSize()
    }

    /// Typing searches after a pause, refining the current search page
    /// instead of adding a history entry per pause.
    private func scheduleSearch() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            search(replacing: true)
        }
    }

    private func search(replacing: Bool) {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if case .search = app.navigator.current {
            app.navigator.go(to: .search(text), replacing: replacing)
        } else {
            app.navigator.go(to: .search(text))
        }
    }
}
