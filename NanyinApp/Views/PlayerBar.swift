//
//  PlayerBar.swift
//  Nanyin
//

import SwiftUI

struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    @State private var draggingProgress: Double?
    /// Now-playing block hover — brightens the artist link (M4.1).
    @State private var npHover = false
    /// Local playback-position tick — deliberately NOT in AppModel so the
    /// 2Hz update only invalidates this bar, never the track list.
    @State private var displayPosition: UInt32 = 0

    var body: some View {
        content
            .task(id: app.nowPlaying?.uri) {
                displayPosition = app.playbackPositionMs
                while !Task.isCancelled {
                    if draggingProgress == nil {
                        let p = app.playbackPositionMs
                        if p != displayPosition { displayPosition = p }
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
            .onChange(of: app.isPlaybackReady) { _, ready in
                if !ready { draggingProgress = nil }
            }
            .onChange(of: app.nowPlaying?.uri) { _, _ in
                draggingProgress = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        switch theme.id {
        case .nanyinDark:
            darkContent
        case .classic2010:
            classicContent
        }
    }

    private var darkContent: some View {
        HStack(spacing: 0) {
            // Now playing (left)
            HStack(spacing: 12) {
                if let np = app.nowPlaying {
                    artwork
                        .frame(width: 52, height: 52)
                        .cornerRadius(theme.metrics.cornerRadius)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.title)
                            .font(theme.typography.playerTitle)
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)
                        if np.artist.isEmpty {
                            Text("—")
                                .font(theme.typography.secondary)
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(1)
                        } else {
                            Button {
                                app.openNowPlayingArtist()
                            } label: {
                                Text(np.artist)
                                    .font(theme.typography.secondary)
                                    .foregroundStyle(
                                        npHover ? theme.colors.primaryText : theme.colors.secondaryText
                                    )
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .linkCursor()
                        }
                    }

                    // Like the playing track (M4.2).
                    if let id = SpotifyClient.trackId(from: np.uri) {
                        let known = app.isLikeKnown(id)
                        let liked = app.likedIDs.contains(id)
                        Button {
                            app.toggleLikePlaying()
                        } label: {
                            Image(systemName: liked ? "heart.fill" : "heart")
                                .font(.system(size: 12))
                                .foregroundStyle(liked ? theme.colors.accent : theme.colors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .disabled(!known)
                        .opacity(known ? 1 : 0.35)
                        .padding(.leading, theme.metrics.likeButtonLeadingPadding)
                        .help(known ? (liked ? "Remove from Liked Songs" : "Save to Liked Songs") : "Checking Liked Songs…")
                        .task(id: id) {
                            app.requestLikedState(id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, theme.metrics.sidebarInset)
            .onHover { npHover = $0 }

            // Transport (center)
            VStack(spacing: 6) {
                HStack(spacing: 24) {
                    Button {
                        app.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(theme.typography.compact)
                            .foregroundStyle(app.shuffle ? theme.colors.accent : theme.colors.secondaryText)
                    }
                    .buttonStyle(.plain)

                    transportButton("PreviousTrack", action: app.prev)
                    Button {
                        app.togglePlay()
                    } label: {
                        Image(systemName: app.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.colors.primaryText)
                    }
                    .buttonStyle(.plain)
                    transportButton("NextTrack", action: app.next)

                    Button {
                        app.cycleRepeat()
                    } label: {
                        Image(systemName: app.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(theme.typography.secondary)
                            .foregroundStyle(
                                app.repeatMode == .off
                                    ? theme.colors.secondaryText
                                    : theme.colors.accent
                            )
                    }
                    .buttonStyle(.plain)
                }
                .disabled(!app.isPlaybackReady)

                if app.nowPlaying != nil {
                    HStack(spacing: 8) {
                        Text(PlaybackTimeFormatter.string(fromMilliseconds: effectivePosition))
                            .font(theme.typography.mono)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 34, alignment: .trailing)

                        slider
                            .allowsHitTesting(app.isPlaybackReady)

                        Text(PlaybackTimeFormatter.string(fromMilliseconds: max(app.durationMs, 0)))
                            .font(theme.typography.mono)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 34, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Volume (right)
            HStack(spacing: 12) {
                Button {
                    app.open(.queue)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            app.page == .queue ? theme.colors.accent : theme.colors.secondaryText
                        )
                }
                .buttonStyle(.plain)
                .help("Queue")

                Image(systemName: "speaker.fill")
                    .font(theme.typography.compact)
                    .foregroundStyle(theme.colors.secondaryText)
                Slider(value: Binding(
                    get: { app.volume },
                    set: { app.setVolume($0) }
                ), in: 0 ... 1)
                .controlSize(.mini)
                .frame(width: 130)
                .disabled(!app.isPlaybackReady)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, theme.metrics.sidebarInset)
        }
        .background(theme.colors.playerBackground.swiftUIStyle)
    }

    private var classicContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ChromeButton(
                    title: "",
                    accessibilityLabel: "Previous track",
                    assetName: "ClassicPreviousTrack",
                    style: ChromeStyle(role: .transport, size: CGSize(width: 24, height: 24)),
                    action: app.prev
                )
                ChromeButton(
                    title: "",
                    accessibilityLabel: app.isPlaying ? "Pause" : "Play",
                    symbolName: app.isPlaying ? "pause.fill" : "play.fill",
                    style: ChromeStyle(role: .transport, size: CGSize(width: 28, height: 28)),
                    action: app.togglePlay
                )
                ChromeButton(
                    title: "",
                    accessibilityLabel: "Next track",
                    assetName: "ClassicNextTrack",
                    style: ChromeStyle(role: .transport, size: CGSize(width: 24, height: 24)),
                    action: app.next
                )

                Spacer(minLength: 6)

                ChromeSliderTrack(
                    style: ChromeSliderStyle(
                        size: CGSize(width: 68, height: 10),
                        fraction: app.volume,
                        isEnabled: app.isPlaybackReady,
                        activeAlpha: 0.72
                    ),
                    accessibilityLabel: "Volume",
                    onChanged: { app.setVolume($0) },
                    onEnded: { app.setVolume($0) }
                )

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .disabled(!app.isPlaybackReady)
            .padding(.horizontal, 10)
            .frame(width: theme.metrics.sidebarWidth)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(theme.colors.shadow.opacity(0.48))
                    .frame(width: 1)
            }

            ZStack {
                if app.nowPlaying != nil {
                    HStack(spacing: 8) {
                        Text(PlaybackTimeFormatter.string(fromMilliseconds: effectivePosition))
                            .font(theme.typography.mono)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 34, alignment: .trailing)

                        ChromeSliderTrack(
                            style: ChromeSliderStyle(
                                size: CGSize(width: 220, height: 10),
                                fraction: progressFraction,
                                isEnabled: app.isPlaybackReady
                            ),
                            fillsAvailableWidth: true,
                            onChanged: { draggingProgress = $0 },
                            onEnded: {
                                app.seek(to: $0)
                                draggingProgress = nil
                            },
                            onCancelled: { draggingProgress = nil }
                        )

                        Text(PlaybackTimeFormatter.string(fromMilliseconds: max(app.durationMs, 0)))
                            .font(theme.typography.mono)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 34, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(theme.colors.shadow.opacity(0.48))
                    .frame(width: 1)
            }

            HStack(spacing: 0) {
                classicActionButton(
                    "shuffle",
                    help: "Shuffle",
                    isActive: app.shuffle,
                    isEnabled: app.isPlaybackReady,
                    action: app.toggleShuffle
                )
                classicActionButton(
                    app.repeatMode == .one ? "repeat.1" : "repeat",
                    help: "Repeat",
                    isActive: app.repeatMode != .off,
                    isEnabled: app.isPlaybackReady,
                    action: app.cycleRepeat
                )
                classicActionButton(
                    "list.bullet",
                    help: "Queue",
                    isActive: app.page == .queue,
                    action: { app.open(.queue) }
                )
            }
        }
        .background {
            ChromeSectionBar(style: ChromeSectionBarStyle(height: theme.metrics.playerBarHeight))
        }
    }

    private func classicActionButton(
        _ symbol: String,
        help: String,
        isActive: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? theme.colors.accent : theme.colors.secondaryText)
                .frame(width: 40, height: theme.metrics.playerBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(ThemePressFeedbackButtonStyle())
        .disabled(!isEnabled)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.colors.shadow.opacity(0.48))
                .frame(width: 1)
        }
        .help(help)
    }

    private var effectivePosition: UInt32 {
        min(draggingProgress.map { UInt32($0 * Double(max(app.durationMs, 1))) } ?? displayPosition, max(app.durationMs, 0))
    }

    private var progressFraction: Double {
        guard app.durationMs > 0 else { return 0 }
        return min(max(Double(effectivePosition) / Double(app.durationMs), 0), 1)
    }

    private var slider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.colors.sliderTrack)
                    .frame(height: 4)
                Capsule()
                    .fill(theme.colors.accent)
                    .frame(width: progressWidth(geo), height: 4)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                        draggingProgress = fraction
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                        app.seek(to: fraction)
                        draggingProgress = nil
                    }
            )
        }
        .frame(width: 220, height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback progress")
        .accessibilityValue(
            Text(
                "\(PlaybackTimeFormatter.string(fromMilliseconds: effectivePosition)) of "
                    + PlaybackTimeFormatter.string(fromMilliseconds: max(app.durationMs, 0))
            )
        )
        .disabled(!app.isPlaybackReady)
        .accessibilityAdjustableAction { direction in
            guard app.isPlaybackReady, app.durationMs > 0 else { return }
            let step = 0.05
            switch direction {
            case .increment:
                app.seek(to: min(progressFraction + step, 1))
            case .decrement:
                app.seek(to: max(progressFraction - step, 0))
            @unknown default:
                break
            }
        }
    }

    private func progressWidth(_ geo: GeometryProxy) -> CGFloat {
        guard app.durationMs > 0 else { return 0 }
        let fraction = draggingProgress ?? Double(displayPosition) / Double(max(app.durationMs, 1))
        return geo.size.width * min(max(fraction, 0), 1)
    }

    @ViewBuilder
    private var artwork: some View {
        ArtworkView(url: app.nowPlaying?.artworkURL, size: 52) {
            placeholderArtwork
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            Rectangle()
                .fill(theme.colors.placeholderBackground.swiftUIStyle)
                Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(theme.typography.controlLabel)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private func transportButton(_ assetName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .buttonStyle(.plain)
    }
}
