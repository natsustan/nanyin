import NanyinKit
import SwiftUI

/// Right-docked lyrics pane with live synced line highlighting, auto-scroll,
/// and click-to-seek. Uses `TimelineView` over `Player.Position` so playback
/// ticks stay local to this pane.
struct LyricsPanel: View {
    @Environment(AppModel.self) private var app
    static let width: CGFloat = 300

    var body: some View {
        let track = app.player.track
        let lyricsModel = app.lyrics
        VStack(spacing: 0) {
            header(track: track, state: lyricsModel.state)
            content(track: track, state: lyricsModel.state)
        }
        .frame(width: Self.width)
        .background(Theme.hex(0x282828))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.divider).frame(width: 1) }
        .onAppear { lyricsModel.load(for: track) }
        .onChange(of: track?.uri) { lyricsModel.load(for: app.player.track) }
    }

    private func header(track: CoreTrack?, state: LyricsModel.State) -> some View {
        GraphiteHeader {
            Text("Lyrics")
            if case .loaded(let lyrics) = state {
                Text("· \(lyrics.source)")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if let track {
                Button { app.lyrics.load(for: track, force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.hex(0xC8C8C8))
                }
                .buttonStyle(.plain)
                .help("Reload Lyrics")
            }
            Button { app.showLyrics = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.hex(0xC8C8C8))
            }
            .buttonStyle(.plain)
            .help("Close Lyrics")
        }
    }

    @ViewBuilder
    private func content(track: CoreTrack?, state: LyricsModel.State) -> some View {
        if let track {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(AquaFont.bold(12.5))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(AquaFont.regular(11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.pageHeader)
                .hairline(.bottom, Theme.divider)

                switch state {
                case .idle, .loading:
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading lyrics…")
                            .font(AquaFont.regular(12))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    PlaceholderText(message: "No lyrics available for this song.") {
                        app.lyrics.load(for: track, force: true)
                    }
                case .failed(let message):
                    PlaceholderText(message: message) {
                        app.lyrics.load(for: track, force: true)
                    }
                case .loaded(let lyrics) where lyrics.instrumental:
                    PlaceholderText(message: "Instrumental")
                case .loaded(let lyrics) where lyrics.synced:
                    SyncedLyricsScroll(lyrics: lyrics)
                case .loaded(let lyrics):
                    PlainLyricsScroll(lyrics: lyrics)
                }
            }
        } else {
            PlaceholderText(message: "Play a song to view lyrics.")
        }
    }
}

private struct SyncedLyricsScroll: View {
    @Environment(AppModel.self) private var app
    let lyrics: Lyrics
    @State private var lastScrolledIndex: Int?

    var body: some View {
        let position = app.player.position
        TimelineView(.periodic(from: .now, by: position.advancing ? 0.25 : 60)) { context in
            let currentMs = position.current(at: context.date)
            let active = lyrics.activeLineIndex(at: currentMs)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            let isActive = active == index
                            let isPast = active.map { index < $0 } ?? false
                            Button {
                                if let ms = line.startTimeMs {
                                    app.player.seek(to: ms)
                                }
                            } label: {
                                Text(line.text)
                                    .font(isActive ? AquaFont.bold(13.5) : AquaFont.regular(13))
                                    .foregroundStyle(
                                        isActive ? Theme.green
                                            : isPast ? Theme.secondaryText.opacity(0.65)
                                            : Theme.text.opacity(0.85)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
                .onChange(of: active) { _, newIndex in
                    guard let newIndex, newIndex != lastScrolledIndex else { return }
                    lastScrolledIndex = newIndex
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct PlainLyricsScroll: View {
    let lyrics: Lyrics

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(AquaFont.regular(13))
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
    }
}
