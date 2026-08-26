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
    @State private var signOutHovering = false
    @AppStorage("sidebar.classicNowPlayingCollapsed")
    private var isClassicNowPlayingCollapsed = false

    init(presentation: SidebarPresentation = .nanyinDark) {
        self.presentation = presentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if presentation == .nanyinDark {
                // Keep navigation content below the title bar controls.
                Color.clear.frame(height: theme.metrics.toolbarSpacerHeight)
            } else {
                classicAccountBar
            }

            entry(.home, icon: Image(systemName: "house"), title: "Home")
                .padding(.top, homeTopInset)
            entry(.search, icon: Image(systemName: "magnifyingglass"), title: "Search")
            if presentation == .nanyinDark {
                entry(.queue, icon: Image(systemName: "list.bullet"), title: "Queue")
            }

            Divider()
                .overlay(theme.colors.playerBackground.swiftUIStyle)
                .padding(.vertical, sidebarGroupGap)
                .padding(.horizontal, theme.metrics.fieldHorizontalPadding)

            Text(presentation == .classic2010 ? "Library" : "Your Library")
                .font(theme.typography.sectionHeader)
                .tracking(1.2)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sidebarInset)
                .padding(.bottom, sidebarHeaderToItemsGap)

            entry(.liked, icon: Image(systemName: "music.note"), title: "Songs", count: app.likedCount)
            entry(.savedAlbums, icon: Image("DiscIcon"), title: "Albums", count: app.savedAlbumCount)
            entry(
                .followedArtists,
                icon: Image(systemName: "microphone"),
                title: "Artists",
                count: app.followedArtistCount
            )

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
            .padding(.top, sidebarSubgroupGap)
            .padding(.bottom, sidebarHeaderToItemsGap)

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

            if presentation == .classic2010, app.nowPlaying != nil {
                classicNowPlayingPanel
            }

            if presentation == .nanyinDark {
                Divider()
                    .overlay(theme.colors.playerBackground.swiftUIStyle)

                HStack(spacing: 8) {
                    Text(accountName)
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Button("Sign Out") {
                        signOut()
                    }
                    .buttonStyle(.plain)
                    .font(theme.typography.fieldLabel)
                    .foregroundStyle(theme.colors.secondaryText)
                }
                .padding(.horizontal, theme.metrics.sidebarInset)
                .padding(.vertical, theme.metrics.fieldVerticalPadding + 1)
            }
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

    private var classicAccountBar: some View {
        HStack(spacing: 0) {
            Text(accountName)
                .font(theme.typography.fieldLabel)
                .foregroundStyle(theme.colors.inverseText.opacity(0.92))
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer(minLength: 6)

            Button {
                signOut()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.colors.inverseText.opacity(signOutHovering ? 0.95 : 0.72))
                    .frame(width: 26, height: 24)
                    .background(Color.black.opacity(signOutHovering ? 0.16 : 0.08))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 1)
            }
            .accessibilityLabel("Sign Out")
            .help("Sign Out")
            .onHover { signOutHovering = $0 }
        }
        .frame(height: 24)
        .background(classicMetalSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.42))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.58))
                .frame(height: 1)
        }
    }

    private var accountName: String {
        app.userDisplayName.isEmpty ? "Spotify account" : app.userDisplayName
    }

    /// Sidebar sections use a compact rhythm: navigation and Library remain
    /// distinct, while Library items and Playlists read as a closer subgroup.
    private var sidebarGroupGap: CGFloat {
        presentation == .classic2010 ? 3 : 8
    }

    private var homeTopInset: CGFloat {
        presentation == .classic2010 ? 2 : 0
    }

    private var sidebarSubgroupGap: CGFloat {
        presentation == .classic2010 ? 6 : 10
    }

    private var sidebarHeaderToItemsGap: CGFloat {
        presentation == .classic2010 ? 2 : 6
    }

    private var sidebarItemVerticalPadding: CGFloat {
        presentation == .classic2010 ? 3 : 5
    }

    private func signOut() {
        Task { await app.signOut() }
    }

    private var classicNowPlayingPanel: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(theme.colors.divider)

            if isClassicNowPlayingCollapsed {
                classicCompactNowPlaying
            } else {
                classicExpandedNowPlaying
            }
        }
    }

    private var classicExpandedNowPlaying: some View {
        VStack(spacing: 0) {
            classicNowPlayingMetadata
                .frame(height: 44)
                .background(classicMetalSurface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.black.opacity(0.52))
                        .frame(height: 1)
                }

            classicArtwork(size: theme.metrics.sidebarWidth)
                .frame(width: theme.metrics.sidebarWidth, height: theme.metrics.sidebarWidth)
                .clipped()
        }
    }

    private var classicCompactNowPlaying: some View {
        HStack(spacing: 8) {
            classicArtwork(size: 54)
                .frame(width: 54, height: 54)
                .clipped()

            if let nowPlaying = app.nowPlaying {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(nowPlaying.title)
                            .font(theme.typography.playerTitle)
                            .foregroundStyle(theme.colors.inverseText.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        classicNowPlayingLikeButton
                    }
                    // Reserve the top-right corner for the collapse control so
                    // the title and its liked-state marker never sit beneath it.
                    .padding(.trailing, 24)

                    classicNowPlayingArtistAndAlbum
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.trailing, 2)
        .frame(height: 54)
        .background(classicMetalSurface)
        .overlay(alignment: .topTrailing) {
            classicNowPlayingCollapseButton
        }
    }

    private var classicNowPlayingMetadata: some View {
        ZStack(alignment: .trailing) {
            if let nowPlaying = app.nowPlaying {
                VStack(spacing: 2) {
                    Text(nowPlaying.title)
                        .font(theme.typography.playerTitle)
                        .foregroundStyle(theme.colors.inverseText.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    classicNowPlayingArtistAndAlbum
                }
                // Keep the metadata out of the right-side action area: the like
                // button occupies 26 pt plus its trailing inset, while the
                // collapse button remains in the top-right corner.
                .padding(.leading, 24)
                .padding(.trailing, 58)
                .frame(maxWidth: .infinity)
            }

            classicNowPlayingLikeButton
                .frame(width: 26, height: 36)
                .padding(.trailing, 24)

            classicNowPlayingCollapseButton
        }
    }

    @ViewBuilder
    private var classicNowPlayingLikeButton: some View {
        if let nowPlaying = app.nowPlaying,
           let id = SpotifyClient.trackId(from: nowPlaying.uri) {
            let known = app.isLikeKnown(id)
            let liked = app.likedIDs.contains(id)
            Button {
                app.toggleLikePlaying()
            } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(theme.typography.compact)
                    .foregroundStyle(liked ? theme.colors.accent : theme.colors.inverseText.opacity(0.58))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!known)
            .opacity(known ? 1 : 0.35)
            .accessibilityLabel(known ? (liked ? "Remove from Liked Songs" : "Save to Liked Songs") : "Checking Liked Songs")
            .help(known ? (liked ? "Remove from Liked Songs" : "Save to Liked Songs") : "Checking Liked Songs…")
            .task(id: id) {
                app.requestLikedState(id)
            }
        }
    }

    @ViewBuilder
    private var classicNowPlayingArtistAndAlbum: some View {
        if let nowPlaying = app.nowPlaying {
            HStack(spacing: 3) {
                Button(nowPlaying.artist.isEmpty ? "—" : nowPlaying.artist) {
                    guard !nowPlaying.artists.isEmpty else { return }
                    app.openNowPlayingArtist()
                }
                .allowsHitTesting(!nowPlaying.artists.isEmpty)
                .help(nowPlaying.artists.isEmpty ? "Artist unavailable" : "Open artist")

                Text("(")

                Button(nowPlaying.album.isEmpty ? "—" : nowPlaying.album) {
                    guard nowPlaying.albumId != nil else { return }
                    app.openNowPlayingAlbum()
                }
                .allowsHitTesting(nowPlaying.albumId != nil)
                .help(nowPlaying.albumId == nil ? "Album unavailable" : "Open album")

                Text(")")
            }
            .buttonStyle(.plain)
            .font(theme.typography.compact)
            .foregroundStyle(theme.colors.inverseText.opacity(0.58))
            .lineLimit(1)
        } else {
            Text("—")
                .font(theme.typography.compact)
                .foregroundStyle(theme.colors.inverseText.opacity(0.58))
        }
    }

    private var classicNowPlayingCollapseButton: some View {
        Button {
            isClassicNowPlayingCollapsed.toggle()
        } label: {
            Image(systemName: isClassicNowPlayingCollapsed
                ? "arrow.up.left.and.arrow.down.right"
                : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.colors.inverseText.opacity(0.64))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isClassicNowPlayingCollapsed ? "Expand album artwork" : "Collapse album artwork")
        .help(isClassicNowPlayingCollapsed ? "Expand album artwork" : "Collapse album artwork")
    }

    private func classicArtwork(size: CGFloat) -> some View {
        ArtworkView(url: app.nowPlaying?.artworkURL, size: size) {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
                .overlay {
                    Image("MusicIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(size * 0.33, 42), height: min(size * 0.33, 42))
                        .foregroundStyle(theme.colors.secondaryText)
                }
        }
    }

    private var classicMetalSurface: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(white: 0.78), location: 0),
                .init(color: Color(white: 0.68), location: 0.48),
                .init(color: Color(white: 0.57), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
            .padding(.vertical, sidebarItemVerticalPadding)
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
