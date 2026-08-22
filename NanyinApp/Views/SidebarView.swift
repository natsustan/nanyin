//
//  SidebarView.swift
//  Nanyin
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    /// Hover state for the New Playlist (+) button — local to the sidebar.
    @State private var plusHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep navigation content below the title bar controls.
            Color.clear.frame(height: theme.metrics.toolbarSpacerHeight)

            entry(.home, icon: Image(systemName: "house"), title: "Home")
            entry(.search, icon: Image(systemName: "magnifyingglass"), title: "Search")
            entry(.queue, icon: Image(systemName: "list.bullet"), title: "Queue")

            Divider()
                .overlay(theme.colors.playerBackground.swiftUIStyle)
                .padding(.vertical, theme.metrics.dividerVerticalPadding)
                .padding(.horizontal, theme.metrics.fieldHorizontalPadding)

            Text("YOUR LIBRARY")
                .font(theme.typography.sectionHeader)
                .tracking(1.2)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sidebarInset)
                .padding(.bottom, theme.metrics.smallPadding)

            entry(.liked, icon: Image(systemName: "heart.fill"), title: "Liked Songs", count: app.likedCount)
            entry(.savedAlbums, icon: Image(systemName: "opticaldisc"), title: "Saved Albums", count: app.savedAlbumCount)

            // One stable title row: PLAYLISTS + always-visible New
            // Playlist (+) button — present while loading and empty too.
            HStack(spacing: 6) {
                Text("PLAYLISTS")
                    .font(theme.typography.sectionHeader)
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer()
                newPlaylistButton
            }
            .padding(.horizontal, theme.metrics.sidebarInset)
            .padding(.top, theme.metrics.sectionTopPadding - 2)
            .padding(.bottom, theme.metrics.smallPadding)

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
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.horizontal, theme.metrics.sidebarInset)
                    .padding(.bottom, theme.metrics.smallPadding)
            }

            Divider()
                .overlay(theme.colors.playerBackground.swiftUIStyle)

            HStack(spacing: 8) {
                Text(app.userDisplayName.isEmpty ? "Spotify account" : app.userDisplayName)
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                Spacer()
                Button("Sign Out") {
                    Task { await app.signOut() }
                }
                .buttonStyle(.plain)
                .font(theme.typography.fieldLabel)
                .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(.horizontal, theme.metrics.sidebarInset)
            .padding(.vertical, theme.metrics.fieldVerticalPadding + 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.sidebarBackground.swiftUIStyle)
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
                .foregroundStyle(plusHovering ? theme.colors.primaryText : theme.colors.secondaryText)
                .frame(width: 22, height: 22)
                .background(
                    plusHovering
                        ? theme.colors.subtleHover.swiftUIStyle
                        : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: theme.metrics.iconButtonCornerRadius)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(ThemePressFeedbackButtonStyle())
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
            .font(theme.typography.secondary)
            .foregroundStyle(theme.colors.secondaryText.opacity(0.6))
            .padding(.horizontal, theme.metrics.sidebarInset)
            .padding(.vertical, theme.metrics.compactFieldVerticalPadding)
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
                .font(isSelected ? theme.typography.nowPlayingTitle : theme.typography.body)
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(theme.typography.mono)
                    .foregroundStyle(theme.colors.tertiaryText)
            }
        }
        .foregroundStyle(
            disabled
                ? theme.colors.disabledText
                : (isSelected ? theme.colors.primaryText : theme.colors.secondaryText)
        )
        .padding(.horizontal, theme.metrics.sidebarInset)
        .padding(.vertical, theme.metrics.compactFieldVerticalPadding)
        .background(
            isSelected
                ? theme.colors.rowSelected.swiftUIStyle
                : AnyShapeStyle(Color.clear)
        )
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
