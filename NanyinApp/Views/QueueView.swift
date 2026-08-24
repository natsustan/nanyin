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
    @Environment(\.appTheme) private var theme

    private var hasContent: Bool {
        app.queueCurrent != nil || app.nowPlaying != nil
            || !app.queueUpcoming.isEmpty || !app.queueRecent.isEmpty
    }

    var body: some View {
        Group {
            if hasContent {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(theme.colors.divider)
                    list
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.6))
                    Text("Nothing in queue")
                        .font(theme.typography.bodyEmphasis)
                        .foregroundStyle(theme.colors.primaryText)
                    Text("Play something — the queue follows along.")
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.colors.contentBackground.swiftUIStyle)
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
        HStack(spacing: 14) {
            Image(systemName: "list.bullet")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Queue")
                    .font(theme.typography.queueTitle)
                    .foregroundStyle(theme.colors.primaryText)
                Text(subtitle)
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.top, theme.metrics.pageTopInset + 4)
        .padding(.bottom, theme.metrics.pageBottomInset)
    }

    private var classicHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("Queue")
                .font(theme.typography.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(theme.colors.primaryText)
            Text(subtitle)
                .font(theme.typography.metadata)
                .foregroundStyle(theme.colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.vertical, theme.metrics.smallPadding + 2)
        .background {
            ChromeSectionBar(style: ChromeSectionBarStyle(height: 40))
        }
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
                            .tint(theme.colors.accent)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            if !app.queueUpcoming.isEmpty {
                queueSection("Next Up", items: app.queueUpcoming)
            }
            if !app.queueRecent.isEmpty {
                queueSection("Recently Played", items: app.queueRecent)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, theme.metrics.queueRowHeight)
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
            Text("Now Playing")
                .font(theme.typography.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sectionHorizontalInset)
                .padding(.top, theme.metrics.sectionTopPadding)
                .padding(.bottom, theme.metrics.sectionBottomPadding)
        }
    }

    private func queueSection(_ title: String, items: [AppModel.QueueItem]) -> some View {
        Section {
            ForEach(items) { item in
                QueueRow(track: item.track, artist: item.artist)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text(title)
                .font(theme.typography.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, theme.metrics.sectionHorizontalInset)
                .padding(.top, theme.metrics.sectionTopPadding)
                .padding(.bottom, theme.metrics.sectionBottomPadding)
        }
    }
}

/// Current-track card: artwork + title/artist + equalizer while playing.
private struct NowPlayingRow: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let artist: String
    let artworkURL: URL?
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 44, height: 44)
                .cornerRadius(theme.metrics.cornerRadius)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.typography.nowPlayingTitle)
                    .foregroundStyle(theme.colors.accent)
                    .lineLimit(1)
                if !artist.isEmpty {
                    Text(artist)
                        .font(theme.typography.secondary)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isPlaying {
                EqBars()
            }
        }
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.vertical, theme.metrics.smallPadding)
    }

    @ViewBuilder
    private var artwork: some View {
        ArtworkView(url: artworkURL, size: 44) {
            ZStack {
                Rectangle()
                    .fill(theme.colors.placeholderBackground.swiftUIStyle)
                Image("MusicIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
    }
}

/// Compact queue row: artwork + title/artist + duration.
private struct QueueRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    let track: SpotifyClient.Track
    let artist: String

    /// Row-local hover — never in the list parent (UI perf rules).
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 32, height: 32)
                .cornerRadius(theme.metrics.smallCornerRadius)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(theme.typography.queueRowTitle)
                    .foregroundStyle(
                        hovering ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.92)
                    )
                    .lineLimit(1)
                Text(artist)
                    .font(theme.typography.secondary)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(PlaybackTimeFormatter.string(fromMilliseconds: UInt32(track.durationMs)))
                .font(theme.typography.duration)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .padding(.horizontal, theme.metrics.sectionHorizontalInset)
        .padding(.vertical, theme.metrics.queueRowVerticalPadding)
        .background(
            hovering ? theme.colors.rowHover.swiftUIStyle : AnyShapeStyle(Color.clear)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                app.addToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            .disabled(!app.isPlaybackReady)
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
        ArtworkView(url: track.artworkURL, size: 32) {
            ZStack {
                Rectangle()
                    .fill(theme.colors.placeholderBackground.swiftUIStyle)
                Image("MusicIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
    }
}

/// Three-bar equalizer (fixed phases — no randomElement per render).
private struct EqBars: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .scaleEffect(y: reduceMotion ? 1 : (animate ? phase : 0.8), anchor: .bottom)
            .animation(
                reduceMotion
                    ? nil
                    : (animate
                        ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true).delay(delay)
                        : .default),
                value: animate
            )
    }
}
