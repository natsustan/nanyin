//
//  SidebarView.swift
//  Nanyin
//

import SwiftUI

enum SidebarPresentation {
    case nanyinDark
    case classic2010
}

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    let presentation: SidebarPresentation

    /// Hover state for the New Playlist (+) button — local to the sidebar.
    @State private var plusHovering = false

    init(presentation: SidebarPresentation = .nanyinDark) {
        self.presentation = presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation == .nanyinDark {
                // Keep navigation content below the title bar controls.
                Color.clear.frame(height: theme.metrics.toolbarSpacerHeight)
            }

            entry(.home, icon: Image(systemName: "house"), title: "Home")
            entry(.search, icon: Image(systemName: "magnifyingglass"), title: "Search")
            entry(.queue, icon: Image(systemName: "list.bullet"), title: "Queue")

            Divider()
                .overlay(theme.colors.playerBackground.swiftUIStyle)
                .padding(.vertical, theme.metrics.dividerVerticalPadding)
                .padding(.horizontal, theme.metrics.fieldHorizontalPadding)

            Text(presentation == .classic2010 ? "Library" : "Your Library")
                .font(theme.typography.sectionHeader)
                .tracking(1.2)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sidebarInset)
                .padding(.bottom, theme.metrics.smallPadding)

            entry(.liked, icon: Image(systemName: "heart.fill"), title: "Liked Songs", count: app.likedCount)
            entry(.savedAlbums, icon: Image(systemName: "opticaldisc"), title: "Saved Albums", count: app.savedAlbumCount)

            // One stable title row: Playlists + always-visible New
            // Playlist (+) button — present while loading and empty too.
            HStack(spacing: 6) {
                Text("Playlists")
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

            if presentation == .classic2010 {
                classicNowPlayingPanel
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

    private var classicNowPlayingPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .overlay(theme.colors.divider)

            Text("Now Playing")
                .font(theme.typography.sectionHeader)
                .tracking(1.1)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sidebarInset)

            HStack(spacing: 8) {
                ArtworkView(url: app.nowPlaying?.artworkURL, size: 64) {
                    Rectangle()
                        .fill(theme.colors.placeholderBackground.swiftUIStyle)
                        .overlay {
                            Image("MusicIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                }
                .frame(width: 64, height: 64)
                .cornerRadius(theme.metrics.imageCornerRadius)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(app.nowPlaying?.title ?? "Not playing")
                            .font(theme.typography.playerTitle)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(2)

                        if let nowPlaying = app.nowPlaying,
                           let id = SpotifyClient.trackId(from: nowPlaying.uri) {
                            let known = app.isLikeKnown(id)
                            let liked = app.likedIDs.contains(id)
                            Button {
                                app.toggleLikePlaying()
                            } label: {
                                Image(systemName: liked ? "heart.fill" : "heart")
                                    .font(theme.typography.compact)
                                    .foregroundStyle(
                                        liked ? theme.colors.accent : theme.colors.secondaryText
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!known)
                            .opacity(known ? 1 : 0.35)
                            .help(known ? (liked ? "Remove from Liked Songs" : "Save to Liked Songs") : "Checking Liked Songs…")
                            .task(id: id) {
                                app.requestLikedState(id)
                            }
                        }
                    }

                    if let nowPlaying = app.nowPlaying {
                        Button(nowPlaying.artist.isEmpty ? "—" : nowPlaying.artist) {
                            app.openNowPlayingArtist()
                        }
                        .buttonStyle(.plain)
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                        .disabled(nowPlaying.artists.isEmpty)
                        .help("Open artist")

                        Button(nowPlaying.album.isEmpty ? "—" : nowPlaying.album) {
                            app.openNowPlayingAlbum()
                        }
                        .buttonStyle(.plain)
                        .font(theme.typography.compact)
                        .foregroundStyle(theme.colors.tertiaryText)
                        .lineLimit(1)
                        .disabled(nowPlaying.albumId == nil)
                        .help("Open album")
                    } else {
                        Text("—")
                            .font(theme.typography.secondary)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, theme.metrics.sidebarInset)
            .padding(.bottom, theme.metrics.smallPadding)
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

        return Button {
            if let page {
                app.open(page)
            }
        } label: {
            HStack(spacing: 12) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.metrics.sidebarInset)
            .padding(.vertical, theme.metrics.compactFieldVerticalPadding)
            .background(
                isSelected
                    ? theme.colors.rowSelected.swiftUIStyle
                    : AnyShapeStyle(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            disabled
                ? theme.colors.disabledText
                : (isSelected ? theme.colors.primaryText : theme.colors.secondaryText)
        )
        .disabled(disabled || page == nil)
        .onHover { hovering in
            if hovering, !disabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
