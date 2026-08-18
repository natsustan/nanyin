//
//  TrackListView.swift
//  Nanyin
//

import SwiftUI

/// Classic flat track table: # / TITLE+ARTIST / ALBUM / duration.
/// Built on List (NSTableView recycling) — the native 60Hz path on macOS.
/// Single click selects, double-click plays from the context.
struct TrackListView: View {
    @Environment(AppModel.self) private var app
    let tracks: [SpotifyClient.Track]
    let contextKey: String

    @State private var selectedURI: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(white: 0.18))
            List(selection: $selectedURI) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        index: index,
                        contextKey: contextKey
                    )
                    .tag(track.uri)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 40)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 44, alignment: .trailing)
            Text("TITLE")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ALBUM")
                .frame(width: 260, alignment: .leading)
            Text("⏱")
                .frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold))
        .tracking(0.8)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}

/// Shared row (also used by ArtistDetailView's 10-row top-tracks list, which
/// renders in a plain VStack inside a ScrollView — no NSTableView there).
struct TrackRow: View {
    @Environment(AppModel.self) private var app
    let track: SpotifyClient.Track
    let index: Int
    let contextKey: String

    /// Row-local hover state: crossing rows only invalidates the rows involved.
    @State private var hovering = false

    private var isCurrent: Bool { app.nowPlaying?.uri == track.uri }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isCurrent, app.isPlaying {
                    EqIndicator()
                        .frame(width: 14, height: 14)
                } else if hovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 44, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accent : .white)
                    .lineLimit(1)
                if !track.artists.isEmpty {
                    artistLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            albumCell
                .frame(width: 260, alignment: .leading)

            Text(Theme.fmtTime(UInt32(track.durationMs)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                app.play(track: track, contextKey: contextKey)
            } label: {
                Label("Play", systemImage: "play")
            }
            Button {
                app.addToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
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
                app.play(track: track, contextKey: contextKey)
            }
        }
        .onHover { h in
            hovering = h
        }
    }

    /// Artist names as individual click targets (M4.1). Every parsed artist
    /// carries an id, so links are never dead.
    private var artistLine: some View {
        HStack(spacing: 0) {
            ForEach(Array(track.artists.enumerated()), id: \.element.id) { index, artist in
                if index > 0 {
                    Text(", ")
                        .foregroundStyle(Theme.textSecondary)
                }
                Button {
                    app.open(.artist(id: artist.id, name: artist.name, artworkURL: artist.artworkURL))
                } label: {
                    Text(artist.name)
                        .foregroundStyle(hovering ? .white : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .linkCursor()
            }
        }
        .font(.system(size: 11))
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
                        .font(.system(size: 12))
                        .foregroundStyle(hovering ? .white : Theme.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .linkCursor()
            } else {
                Text(track.albumName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var rowBackground: Color {
        if hovering && !isCurrent { return Theme.hover }
        return .clear
    }
}

/// The classic three-bar equalizer animation for the playing row.
private struct EqIndicator: View {
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
            .fill(Theme.accent)
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
