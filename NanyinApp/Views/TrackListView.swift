//
//  TrackListView.swift
//  Nanyin
//

import SwiftUI

/// Classic flat track table: # / TITLE+ARTIST / ALBUM / duration.
/// Single click selects, double-click plays from the context.
/// Perf-critical: hover/selection state is row-local so mouse movement
/// never invalidates the whole list.
struct TrackListView: View {
    @Environment(AppModel.self) private var app
    let tracks: [SpotifyClient.Track]
    let contextKey: String

    @State private var selectedURI: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(white: 0.18))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(
                            track: track,
                            index: index,
                            contextKey: contextKey,
                            isSelected: selectedURI == track.uri
                        ) {
                            selectedURI = track.uri
                        }
                    }
                }
            }
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
    }
}

private struct TrackRow: View {
    @Environment(AppModel.self) private var app
    let track: SpotifyClient.Track
    let index: Int
    let contextKey: String
    let isSelected: Bool
    let onSelect: () -> Void

    /// Row-local hover state — the perf-critical part: crossing rows with the
    /// mouse only invalidates the two rows involved, never the whole list.
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
                    Text(track.artists.joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.albumName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 260, alignment: .leading)

            Text(Theme.fmtTime(UInt32(track.durationMs)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(
            hovering && !isCurrent ? Theme.hover : (isSelected ? Color(white: 0.13) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            app.play(track: track, contextKey: contextKey)
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .onHover { h in
            hovering = h
        }
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
