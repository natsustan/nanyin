//
//  SidebarView.swift
//  Nanyin
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    /// Hover state for the New Playlist (+) button — local to the sidebar.
    @State private var plusHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep navigation content below the title bar controls.
            Color.clear.frame(height: 54)

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
            entry(.savedAlbums, icon: Image(systemName: "opticaldisc"), title: "Saved Albums", count: app.savedAlbumCount)

            // One stable title row: PLAYLISTS + always-visible New
            // Playlist (+) button — present while loading and empty too.
            HStack(spacing: 6) {
                Text("PLAYLISTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                newPlaylistButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if app.playlists.isEmpty {
                        playlistListState
                    }
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

            Divider()
                .overlay(Theme.playerBar)

            HStack(spacing: 8) {
                Text(app.userDisplayName.isEmpty ? "Spotify account" : app.userDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button("Sign Out") {
                    Task { await app.signOut() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebar)
        .sheet(isPresented: Binding(
            get: { app.isShowingNewPlaylistSheet },
            set: { shown in if !shown { app.cancelNewPlaylistSheet() } }
        )) {
            NewPlaylistSheet()
        }
    }

    /// Plain + at the title row's right edge (M4.5). Keyboard- and
    /// VoiceOver-accessible; tooltip matches the action.
    private var newPlaylistButton: some View {
        Button {
            app.showNewPlaylistSheet()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(plusHovering ? .white : Theme.textSecondary)
                .frame(width: 22, height: 22)
                .background(
                    plusHovering ? Color.white.opacity(0.1) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Playlist")
        .help("New Playlist")
        .onHover { plusHovering = $0 }
    }

    /// Explicit loading / empty / failed states for the playlist list —
    /// an empty or failed response is never treated as perpetual loading.
    @ViewBuilder
    private var playlistListState: some View {
        if app.playlistsLoadFailed {
            listStateText("Couldn't load playlists")
        } else if !app.hasLoadedPlaylists {
            listStateText("Loading playlists…")
        } else {
            listStateText("No playlists yet")
        }
    }

    private func listStateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
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
