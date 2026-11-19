import SwiftUI

/// The unified metal title bar and toolbar: traffic lights and the window
/// title on top, history and search below, the account on the right.
struct MainToolbar: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var debounce: Task<Void, Never>?
    @State private var isFrontmost = true

    static let height: CGFloat = 54

    var body: some View {
        let navigator = app.navigator
        ZStack(alignment: .top) {
            TitleBarDragArea()
            Text("Nanyin")
                .font(AquaFont.regular(13))
                .foregroundStyle(Theme.metalText.opacity(isFrontmost ? 1 : 0.5))
                .shadow(color: .white.opacity(0.6), radius: 0, y: 1)
                .padding(.top, 3)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                TrafficLights()
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.top, 2)
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    Button { navigator.goBack() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(TexturedButtonStyle(width: 28))
                        .disabled(!navigator.canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                    Button { navigator.goForward() } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(TexturedButtonStyle(width: 28))
                        .disabled(!navigator.canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                        .padding(.leading, -1)
                }
                AquaSearchField(text: $query, onSubmit: search)
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
        .background {
            LinearGradient(
                colors: isFrontmost ? [Theme.metalTop, Theme.metalBottom] : [Theme.metalInactiveTop, Theme.metalInactiveBottom],
                startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.7)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.metalEdge).frame(height: 1) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in isFrontmost = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in isFrontmost = false }
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
                .font(AquaFont.regular(11))
        }
        .menuStyle(.button)
        .buttonStyle(TexturedButtonStyle())
        .fixedSize()
    }

    private func scheduleSearch() {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            app.navigator.go(to: .search(text))
        }
    }

    private func search() {
        debounce?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        app.navigator.go(to: .search(text))
    }
}
