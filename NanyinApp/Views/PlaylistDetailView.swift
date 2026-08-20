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
            Divider().overlay(Color(white: 0.18))
            trackContent
        }
        .background(Theme.background)
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
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    app.retryCurrentPageLoad()
                } label: {
                    Text("Retry")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(Theme.accent)
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tracks.isEmpty {
            VStack(spacing: 12) {
                if app.isLoadingTracks(contextKey: contextKey) {
                    ProgressView()
                    Text("Loading tracks…")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Nothing here yet")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TrackListView(tracks: tracks, contextKey: contextKey)
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            cover
                .frame(width: 140, height: 140)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 12) {
                    playButton
                    if albumId != nil {
                        SaveAlbumButton(album: albumSeed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(Theme.background)
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
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Theme.accent)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .disabled(albumId == nil && tracks.isEmpty)
        .opacity(albumId == nil && tracks.isEmpty ? 0.5 : 1)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverAssetName {
            Image(coverAssetName)
                .resizable()
                .scaledToFill()
        } else if let url = coverURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholderCover
            }
        } else {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        ZStack {
            Color(white: 0.14)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Album-header save control. Plus/check semantics — deliberately NOT a
/// heart, so album saves can never be confused with Liked Songs (M4.3).
/// Disabled until the saved state is known (one contains probe on page
/// appearance, same discipline as the track like button).
private struct SaveAlbumButton: View {
    @Environment(AppModel.self) private var app
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
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(isSaved ? Theme.accent : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        hovering ? .white.opacity(isSaved ? 0.7 : 0.9) : Color(white: 0.4),
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
