//
//  TrackListView.swift
//  Nanyin
//

import SwiftUI

/// Classic flat track table: # / TITLE+ARTIST / ALBUM / duration.
/// Single click selects, double-click plays from the context.
struct TrackListView: View {
    @Environment(AppModel.self) private var app
    let tracks: [SpotifyClient.Track]
    let contextKey: String

    @State private var selectedURI: String?
    @State private var hoverURI: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(white: 0.18))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        row(track, index: index)
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

    private func row(_ track: SpotifyClient.Track, index: Int) -> some View {
        let isCurrent = app.nowPlaying?.uri == track.uri
        let isHovering = hoverURI == track.uri

        return HStack(spacing: 0) {
            // Index / eq indicator
            Group {
                if isCurrent, app.isPlaying {
                    EqIndicator()
                        .frame(width: 14, height: 14)
                } else if isHovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 44, alignment: .trailing)

            // Title + artist
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

            // Album
            Text(track.albumName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 260, alignment: .leading)

            // Duration
            Text(Theme.fmtTime(UInt32(track.durationMs)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(
            isHovering && !isCurrent ? Theme.hover : (selectedURI == track.uri ? Color(white: 0.13) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            app.play(track: track, contextKey: contextKey)
        }
        .onTapGesture(count: 1) {
            selectedURI = track.uri
        }
        .onHover { hovering in
            hoverURI = hovering ? track.uri : nil
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .id(track.uri)
    }
}

/// The classic three-bar equalizer animation for the playing row.
private struct EqIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2) {
            bar(height: 7, delay: 0)
            bar(height: 12, delay: 0.15)
            bar(height: 5, delay: 0.3)
        }
        .frame(width: 14, height: 14)
        .onAppear { animate = true }
    }

    private func bar(height: CGFloat, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.accent)
            .frame(width: 3, height: height)
            .scaleEffect(y: animate ? [0.5, 1.0].randomElement()! : 0.8, anchor: .bottom)
            .animation(
                animate
                    ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true).delay(delay)
                    : .default,
                value: animate
            )
    }
}
