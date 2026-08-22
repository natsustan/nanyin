//
//  TrackListView.swift
//  Nanyin
//

import SwiftUI

private enum TrackTableLayout {
    static let indexColumnWidth: CGFloat = 64
    static let albumColumnWidth: CGFloat = 260
    static let durationColumnWidth: CGFloat = 56
}

/// Stable identity for one occurrence of a track. Playlists permit the same
/// Spotify track URI more than once, so catalog identity alone is not a row
/// identity.
private struct TrackOccurrence: Identifiable {
    struct ID: Hashable {
        let uri: String
        let occurrence: Int
    }

    let id: ID
    let index: Int
    let track: SpotifyClient.Track

    static func rows(for tracks: [SpotifyClient.Track]) -> [TrackOccurrence] {
        var occurrences: [String: Int] = [:]
        return tracks.enumerated().map { index, track in
            let occurrence = occurrences[track.uri, default: 0]
            occurrences[track.uri] = occurrence + 1
            return TrackOccurrence(
                id: ID(uri: track.uri, occurrence: occurrence),
                index: index,
                track: track
            )
        }
    }
}

/// Classic flat track table: # / TITLE+ARTIST / ALBUM / duration.
/// Built on List (NSTableView recycling) — the native 60Hz path on macOS.
/// Single click selects, double-click plays from the context.
struct TrackListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let tracks: [SpotifyClient.Track]
    let contextKey: String

    @State private var selectedRowID: TrackOccurrence.ID?

    var body: some View {
        List(selection: $selectedRowID) {
            Section {
                ForEach(TrackOccurrence.rows(for: tracks)) { row in
                    TrackRow(
                        track: row.track,
                        index: row.index,
                        contextKey: contextKey
                    )
                    .tag(row.id)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                header
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, theme.metrics.standardRowHeight)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: TrackTableLayout.indexColumnWidth, alignment: .center)
            Text("Track")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Album")
                .frame(width: TrackTableLayout.albumColumnWidth, alignment: .leading)
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: TrackTableLayout.durationColumnWidth, alignment: .trailing)
        }
        .font(theme.typography.sectionHeader)
        .tracking(0.8)
        .foregroundStyle(theme.colors.secondaryText)
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.vertical, theme.metrics.smallPadding)
        .background(theme.colors.contentBackground.swiftUIStyle)
        .overlay(alignment: .bottom) {
            Divider().overlay(theme.colors.divider)
        }
    }
}

/// Shared row (also used by ArtistDetailView's 10-row top-tracks list, which
/// renders in a plain VStack inside a ScrollView — no NSTableView there).
struct TrackRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let track: SpotifyClient.Track
    let index: Int
    let contextKey: String

    /// Row-local hover state: crossing rows only invalidates the rows involved.
    @State private var hovering = false

    private var isCurrent: Bool { app.nowPlaying?.uri == track.uri }
    private var isLikeKnown: Bool { app.isLikeKnown(track.id) }
    private var isLiked: Bool { app.likedIDs.contains(track.id) }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isCurrent, app.isPlaying {
                    EqIndicator()
                        .frame(width: 14, height: 14)
                } else if hovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.colors.primaryText)
                } else {
                    Text("\(index + 1)")
                        .font(theme.typography.trackIndex)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .frame(width: TrackTableLayout.indexColumnWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(isCurrent ? theme.typography.nowPlayingTitle : theme.typography.body)
                    .foregroundStyle(isCurrent ? theme.colors.accent : theme.colors.primaryText)
                    .lineLimit(1)
                if !track.artists.isEmpty {
                    artistLine
                } else if let artist = track.artistDisplayText, !artist.isEmpty {
                    Text(artist)
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            albumCell
                .frame(width: TrackTableLayout.albumColumnWidth, alignment: .leading)

            Text(PlaybackTimeFormatter.string(fromMilliseconds: UInt32(track.durationMs)))
                .font(theme.typography.duration)
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: TrackTableLayout.durationColumnWidth, alignment: .trailing)

            // Like toggle (M4.2): always visible when liked, ghost on hover.
            Button {
                app.toggleLike(track)
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 11))
                    .foregroundStyle(isLiked ? theme.colors.accent : theme.colors.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(!isLikeKnown)
            .opacity(isLikeKnown ? (isLiked ? 1 : (hovering ? 1 : 0)) : 0)
            .frame(width: 32, alignment: .center)
            .help(isLikeKnown ? (isLiked ? "Remove from Liked Songs" : "Save to Liked Songs") : "Checking Liked Songs…")
        }
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.vertical, theme.metrics.trackRowVerticalPadding)
        .background(rowBackground)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                app.play(track: track, contextKey: contextKey, index: index)
            } label: {
                Label("Play", systemImage: "play")
            }
            .disabled(!app.isPlaybackReady)
            Button {
                app.addToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            .disabled(!app.isPlaybackReady)
            if !app.ownedPlaylists.isEmpty {
                Menu {
                    ForEach(app.ownedPlaylists) { playlist in
                        Button {
                            app.addToPlaylist(track, playlist: playlist)
                        } label: {
                            Text(playlist.name)
                        }
                        .disabled(app.isPlaylistAddInFlight(playlist.id))
                    }
                } label: {
                    Label("Add to Playlist", systemImage: "music.note.list")
                }
            }
            if isLikeKnown {
                Button {
                    app.toggleLike(track)
                } label: {
                    Label(
                        isLiked ? "Remove from Liked Songs" : "Save to Liked Songs",
                        systemImage: isLiked ? "heart.slash" : "heart"
                    )
                }
            }
            Divider()
            Button {
                let url = "https://open.spotify.com/track/\(track.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: {
                Label("Copy Song Link", systemImage: "link")
            }
        }
        .onTapGesture(count: 2) {
            // Mutating @Observable state synchronously here runs List's
            // NSTableView sync inside the mouseDown/delegate window — the
            // "reentrant operation in its NSTableView delegate" warning
            // (future assert). Hop out of the event first.
            Task { @MainActor in
                app.play(track: track, contextKey: contextKey, index: index)
            }
        }
        .onHover { h in
            hovering = h
        }
        .onAppear {
            app.requestLikedState(track.id)
        }
    }

    /// Artist names as individual click targets (M4.1). Every parsed artist
    /// carries an id, so links are never dead.
    private var artistLine: some View {
        HStack(spacing: 0) {
            ForEach(Array(track.artists.enumerated()), id: \.element.id) { index, artist in
                if index > 0 {
                    Text(", ")
                        .foregroundStyle(theme.colors.secondaryText)
                }
                Button {
                    app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
                } label: {
                    Text(artist.name)
                        .foregroundStyle(
                            hovering ? theme.colors.primaryText : theme.colors.secondaryText
                        )
                }
                .buttonStyle(.plain)
                .linkCursor()
            }
        }
        .font(theme.typography.secondary)
        .lineLimit(1)
    }

    private var albumCell: some View {
        Group {
            if let albumId = track.albumId, !albumId.isEmpty {
                Button {
                    app.open(.album(
                        id: albumId,
                        name: track.albumName,
                        subtitle: track.artists.map(\.name).joined(separator: ", "),
                        artworkURL: track.artworkURL
                    ))
                } label: {
                    Text(track.albumName)
                        .font(theme.typography.metadata)
                        .foregroundStyle(
                            hovering ? theme.colors.primaryText : theme.colors.secondaryText
                        )
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .linkCursor()
            } else {
                Text(track.albumName)
                    .font(theme.typography.metadata)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var rowBackground: AnyShapeStyle {
        if isCurrent { return theme.colors.rowCurrent.swiftUIStyle }
        if hovering { return theme.colors.rowHover.swiftUIStyle }
        return AnyShapeStyle(Color.clear)
    }
}

/// The classic three-bar equalizer animation for the playing row.
private struct EqIndicator: View {
    @Environment(\.appTheme) private var theme
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2) {
            bar(phase: 0.55, delay: 0)
            bar(phase: 1.0, delay: 0.15)
            bar(phase: 0.7, delay: 0.3)
        }
        .frame(width: 14, height: 14)
        .onAppear { animate = true }
    }

    private func bar(phase: CGFloat, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(theme.colors.accent)
            .frame(width: 3, height: 12)
            .scaleEffect(y: animate ? phase : 0.8, anchor: .bottom)
            .animation(
                animate
                    ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true).delay(delay)
                    : .default,
                value: animate
            )
    }
}
