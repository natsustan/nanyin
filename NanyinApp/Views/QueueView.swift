//
//  QueueView.swift
//  Nanyin
//

import SwiftUI

/// The active device's queue: Now Playing, next up, and recently played.
/// Backed by GET /v1/me/player/queue (refreshed on track changes, adds, and
/// page visits) plus a local recently-played history (M2.3).
///
/// Single scroll region: fixed header + one recycling List (UI perf rules).
struct QueueView: View {
    @Environment(AppModel.self) private var app

    private var hasContent: Bool {
        app.queueCurrent != nil || app.nowPlaying != nil
            || !app.queueUpcoming.isEmpty || !app.queueRecent.isEmpty
    }

    var body: some View {
        Group {
            if hasContent {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Color(white: 0.18))
                    list
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    Text("Nothing in queue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Play something — the queue follows along.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "list.bullet")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Queue")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private var subtitle: String {
        let next = app.queueUpcoming.count
        return next == 1 ? "1 song next up" : "\(next) songs next up"
    }

    private var list: some View {
        List {
            nowPlayingSection

            if app.isLoadingQueue && app.queueUpcoming.isEmpty && app.queueRecent.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            if !app.queueUpcoming.isEmpty {
                queueSection("NEXT UP", items: app.queueUpcoming)
            }
            if !app.queueRecent.isEmpty {
                queueSection("RECENTLY PLAYED", items: app.queueRecent)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 36)
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        Section {
            if let track = app.queueCurrent {
                NowPlayingRow(
                    title: track.name,
                    artist: track.artists.map(\.name).joined(separator: ", "),
                    artworkURL: track.artworkURL,
                    isPlaying: app.nowPlaying?.uri == track.uri && app.isPlaying
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if let np = app.nowPlaying {
                NowPlayingRow(
                    title: np.title,
                    artist: np.artist,
                    artworkURL: np.artworkURL,
                    isPlaying: app.isPlaying
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("NOW PLAYING")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 6)
        }
    }

    private func queueSection(_ title: String, items: [AppModel.QueueItem]) -> some View {
        Section {
            ForEach(items) { item in
                QueueRow(track: item.track)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 6)
        }
    }
}

/// Current-track card: artwork + title/artist + equalizer while playing.
private struct NowPlayingRow: View {
    let title: String
    let artist: String
    let artworkURL: URL?
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 44, height: 44)
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isPlaying {
                EqBars()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(white: 0.14)
            }
        } else {
            ZStack {
                Color(white: 0.14)
                Image("MusicIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Compact queue row: artwork + title/artist + duration.
private struct QueueRow: View {
    @Environment(AppModel.self) private var app
    let track: SpotifyClient.Track

    /// Row-local hover — never in the list parent (UI perf rules).
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 32, height: 32)
                .cornerRadius(3)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovering ? .white : .white.opacity(0.92))
                    .lineLimit(1)
                Text(track.artists.map(\.name).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Theme.fmtTime(UInt32(track.durationMs)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 5)
        .background(hovering ? Theme.hover : .clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                app.addToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "https://open.spotify.com/track/\(track.id)", forType: .string
                )
            } label: {
                Label("Copy Song Link", systemImage: "link")
            }
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = track.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(white: 0.14)
            }
        } else {
            ZStack {
                Color(white: 0.14)
                Image("MusicIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Three-bar equalizer (fixed phases — no randomElement per render).
private struct EqBars: View {
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
