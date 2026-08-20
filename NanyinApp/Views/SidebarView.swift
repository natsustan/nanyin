//
//  SidebarView.swift
//  Nanyin
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back/forward navigation (desktop-client style sidebar arrows).
            HStack(spacing: 4) {
                NavButton(systemImage: "chevron.left", shortcut: "[", enabled: app.canGoBack) {
                    app.goBack()
                }
                NavButton(systemImage: "chevron.right", shortcut: "]", enabled: app.canGoForward) {
                    app.goForward()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 10)

            entry(.home, icon: Image(systemName: "house"), title: "Home")
            entry(.search, icon: Image(systemName: "magnifyingglass"), title: "Search")
            entry(.queue, icon: Image(systemName: "list.bullet"), title: "Queue")

            Divider()
                .overlay(Theme.playerBar)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

            Text("YOUR LIBRARY")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            entry(.liked, icon: Image(systemName: "heart.fill"), title: "Liked Songs", count: app.likedCount)

            if !app.playlists.isEmpty {
                Text("PLAYLISTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            } else {
                Text("Loading playlists…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(app.playlists) { playlist in
                        entry(
                            .playlist(id: playlist.id, name: playlist.name),
                            icon: Image("MusicIcon"),
                            title: playlist.name,
                            count: playlist.trackCount
                        )
                    }
                }
            }

            if let note = app.connectionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebar)
    }

    /// Circular back/forward arrow — dims when the stack is empty and carries
    /// the ⌘[ / ⌘] shortcuts (SwiftUI disables the shortcut with the button).
    private struct NavButton: View {
        let systemImage: String
        let shortcut: KeyEquivalent
        let enabled: Bool
        let action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(enabled ? (hovering ? .white : Color(white: 0.85)) : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(hovering && enabled ? Color(white: 0.14) : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .keyboardShortcut(shortcut, modifiers: .command)
            .onHover { hovering = $0 }
            .help(enabled ? "Back / Forward" : "No navigation history")
        }
    }

    private func entry(
        _ page: AppModel.Page?,
        icon: Image,
        title: String,
        count: Int? = nil,
        disabled: Bool = false
    ) -> some View {
        let isSelected = page != nil && app.page == page

        return HStack(spacing: 12) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 13)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        }
        .foregroundStyle(
            disabled
                ? Theme.textSecondary.opacity(0.5)
                : (isSelected ? .white : Theme.textSecondary)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color(white: 0.12) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if let page {
                app.open(page)
            }
        }
        .onHover { hovering in
            if hovering, !disabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
