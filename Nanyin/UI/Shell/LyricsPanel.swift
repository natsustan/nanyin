import NanyinKit
import SwiftUI

/// Right-docked lyrics pane with live synced line highlighting, auto-scroll,
/// and click-to-seek. Uses `TimelineView` over `Player.Position` so playback
/// ticks stay local to this pane and stop completely while paused.
struct LyricsPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appearsActive) private var appearsActive
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
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("Lyrics")
                    .font(AquaFont.bold(12))
                    .foregroundStyle(Theme.metalText.opacity(appearsActive ? 1 : 0.65))
                    .embossed()
                if case .loaded(let lyrics) = state {
                    Text("· \(lyrics.source)")
                        .font(AquaFont.regular(10.5))
                        .foregroundStyle(Theme.metalSecondaryText.opacity(appearsActive ? 1 : 0.65))
                        .embossed()
                        .lineLimit(1)
                }
            }
            .padding(.leading, 9)
            Spacer(minLength: 4)
            if let track {
                MetalSubBarDivider()
                Button { app.lyrics.load(for: track, force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(MetalSubBarButtonStyle(width: 24))
                .help("Reload Lyrics")
            }
            MetalSubBarDivider()
            Button { app.showLyrics = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .buttonStyle(MetalSubBarButtonStyle(width: 24))
            .help("Close Lyrics")
        }
        .frame(height: Theme.subBarHeight)
        .background(Theme.subBar(active: appearsActive))
        .hairline(.top, Theme.subBarHighlight)
        .hairline(.bottom, Theme.divider)
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
                        .id(track.uri)
                case .loaded(let lyrics):
                    PlainLyricsScroll(lyrics: lyrics)
                        .id(track.uri)
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

    var body: some View {
        let position = app.player.position
        TimelineView(LyricsSchedule(position: position)) { context in
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
                .onChange(of: active, initial: true) { _, newIndex in
                    guard let newIndex else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }
}

/// Ticks at 4 Hz while advancing, and stops completely while playback is paused.
private struct LyricsSchedule: TimelineSchedule {
    let position: Player.Position

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard position.advancing else {
            var once = true
            return AnyIterator { defer { once = false }; return once ? start : nil }
        }
        var current = start
        return AnyIterator {
            defer { current = current.addingTimeInterval(0.25) }
            return current
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
