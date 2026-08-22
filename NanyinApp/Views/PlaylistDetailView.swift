//
//  PlaylistDetailView.swift
//  Nanyin
//

import SwiftUI

/// Header (cover + name + count + play button) + track list.
/// Used for playlists, Liked Songs, and album pages (label = "ALBUM",
/// albumId set). The header always stays mounted and interactive — track
/// loading, empty, and error states render below it, never replacing it
/// (M4.3: the album save control must remain reachable at all times).
struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme

    let title: String
    let subtitle: String
    let coverURL: URL?
    let contextKey: String
    var coverAssetName: String? = nil
    /// Header eyebrow: PLAYLIST / ALBUM / …
    var label = "PLAYLIST"
    /// Non-nil on album pages: enables the save control and context playback.
    var albumId: String? = nil

    private var tracks: [SpotifyClient.Track] {
        app.tracksByContext[contextKey] ?? []
    }

    /// Artist line for the album-page save seed. Falls back to the page
    /// subtitle (which may carry "Artist · Year") until tracks arrive; the
    /// next server refresh replaces the seed with canonical data anyway.
    private var albumSeed: SpotifyClient.SavedAlbum {
        let artistName = tracks.first
            .map { $0.artists.map(\.name).joined(separator: ", ") }
            ?? subtitle
        return SpotifyClient.SavedAlbum(
            album: .init(
                id: albumId ?? "",
                name: title,
                artistName: artistName.isEmpty ? title : artistName,
                group: "album",
                year: nil,
                trackCount: tracks.count,
                artworkURL: coverURL
            ),
            addedAt: nil
        )
    }

    private var headerSubtitle: String {
        guard albumId != nil, !tracks.isEmpty else { return subtitle }
        return subtitle.isEmpty
            ? "\(tracks.count) tracks"
            : "\(subtitle) · \(tracks.count) tracks"
    }

    var body: some View {
        // Single scroll region: fixed header + recycling List (the List
        // inside TrackListView is the ONLY scroller on this page — the
        // previous nested-ScrollView layout caused scroll jank).
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.colors.divider)
            trackContent
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
        .task(id: albumId) {
            // Resolve the saved state for album pages on first appearance.
            if albumId != nil {
                app.requestSavedAlbumState(albumSeed)
            }
        }
    }

    @ViewBuilder
    private var trackContent: some View {
        if let error = app.tracksError[contextKey] {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(theme.colors.warning)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, theme.metrics.pageHorizontalInset + 12)
                Button {
                    app.retryCurrentPageLoad()
                } label: {
                    Text("Retry")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.colors.inverseText)
                        .padding(.horizontal, theme.metrics.controlHorizontalPadding)
                        .padding(.vertical, theme.metrics.controlVerticalPadding - 1)
                        .background(theme.colors.accent)
                        .cornerRadius(theme.metrics.smallPillCornerRadius)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tracks.isEmpty {
            VStack(spacing: 12) {
                if app.isLoadingTracks(contextKey: contextKey) {
                    ProgressView()
                    Text("Loading tracks…")
                        .foregroundStyle(theme.colors.secondaryText)
                } else {
                    Text("Nothing here yet")
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TrackListView(tracks: tracks, contextKey: contextKey)
        }
    }

    @ViewBuilder
    private var header: some View {
        if theme.id == .classic2010 {
            classicHeader
        } else {
            darkHeader
        }
    }

    private var darkHeader: some View {
        HStack(spacing: 24) {
            cover(size: theme.metrics.detailArtworkSize)
                .frame(width: theme.metrics.detailArtworkSize, height: theme.metrics.detailArtworkSize)
                .cornerRadius(theme.metrics.imageCornerRadius)
                .shadow(color: theme.colors.shadow.opacity(0.5), radius: theme.metrics.shadowRadius + 4, y: theme.metrics.shadowYOffset + 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(theme.typography.sectionHeader)
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.secondaryText)
                Text(title)
                    .font(theme.typography.detailTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                Text(headerSubtitle)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)

                HStack(spacing: 12) {
                    playButton
                    if albumId != nil {
                        SaveAlbumButton(album: albumSeed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.top, theme.metrics.pageTopInset)
        .padding(.bottom, theme.metrics.pageBottomInset)
        .background(theme.colors.contentBackground.swiftUIStyle)
    }

    private var classicHeader: some View {
        HStack(spacing: 12) {
            cover(size: theme.metrics.detailArtworkSize)
                .frame(width: theme.metrics.detailArtworkSize, height: theme.metrics.detailArtworkSize)
                .cornerRadius(theme.metrics.imageCornerRadius)

            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(theme.typography.sectionHeader)
                    .tracking(0.8)
                    .foregroundStyle(theme.colors.secondaryText)
                Text(title)
                    .font(theme.typography.detailTitle)
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    playButton
                    if albumId != nil {
                        SaveAlbumButton(album: albumSeed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.metrics.pageHorizontalInset)
        .padding(.vertical, theme.metrics.smallPadding + 2)
        .background {
            ChromeSectionBar(
                style: ChromeSectionBarStyle(
                    height: theme.metrics.detailArtworkSize + (theme.metrics.smallPadding + 2) * 2
                )
            )
        }
    }

    /// Album pages play the server-resolved context directly (no dependency
    /// on loaded tracks); playlist/liked pages play the loaded first track.
    private var playButton: some View {
        Button {
            if let albumId {
                app.playAlbum(id: albumId)
            } else if let first = tracks.first {
                app.play(track: first, contextKey: contextKey)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("PLAY")
                    .font(theme.typography.button)
                    .tracking(0.8)
            }
            .foregroundStyle(theme.colors.inverseText)
            .padding(.horizontal, theme.metrics.controlHorizontalPadding)
            .padding(.vertical, theme.metrics.controlVerticalPadding)
            .background(theme.colors.accent)
            .cornerRadius(theme.metrics.pillCornerRadius)
        }
        .buttonStyle(.plain)
        .disabled(!app.isPlaybackReady || (albumId == nil && tracks.isEmpty))
        .opacity(!app.isPlaybackReady || (albumId == nil && tracks.isEmpty) ? 0.5 : 1)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private func cover(size: CGFloat) -> some View {
        if let coverAssetName {
            Image(coverAssetName)
                .resizable()
                .scaledToFill()
        } else {
            ArtworkView(url: coverURL, size: size) {
                placeholderCover(size: size)
            }
        }
    }

    private func placeholderCover(size: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.32, height: size * 0.32)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}

/// Album-header save control. Plus/check semantics — deliberately NOT a
/// heart, so album saves can never be confused with Liked Songs (M4.3).
/// Disabled until the saved state is known (one contains probe on page
/// appearance, same discipline as the track like button).
private struct SaveAlbumButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let album: SpotifyClient.SavedAlbum

    @State private var hovering = false

    private var isKnown: Bool { app.isAlbumSaveKnown(album.id) }
    private var isSaved: Bool { app.isAlbumSaved(album.id) }
    private var probeFailed: Bool { app.didAlbumSaveProbeFail(album.id) }

    var body: some View {
        Button {
            app.toggleSavedAlbum(album)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: probeFailed ? "arrow.clockwise" : (isSaved ? "checkmark" : "plus"))
                    .font(.system(size: 11, weight: .bold))
                Text(probeFailed ? "RETRY" : (isSaved ? "SAVED" : "SAVE ALBUM"))
                    .font(theme.typography.button)
                    .tracking(0.8)
            }
            .foregroundStyle(isSaved ? theme.colors.accent : theme.colors.primaryText)
            .padding(.horizontal, theme.metrics.controlHorizontalPadding - 2)
            .padding(.vertical, theme.metrics.controlVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: theme.metrics.pillCornerRadius)
                    .strokeBorder(
                        hovering
                            ? theme.colors.primaryText.opacity(isSaved ? 0.7 : 0.9)
                            : theme.colors.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isKnown && !probeFailed)
        .opacity(isKnown || probeFailed ? 1 : 0.5)
        .onHover { hovering in
            self.hovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(
            probeFailed
                ? "Retry checking Saved Albums"
                : (isKnown ? (isSaved ? "Remove from Saved Albums" : "Save to Saved Albums") : "Checking Saved Albums…")
        )
    }
}
