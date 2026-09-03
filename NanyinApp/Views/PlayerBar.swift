//
//  PlayerBar.swift
//  Nanyin
//

import SwiftUI

struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appTheme) private var theme
    /// Kept local so the 2.5Hz tick never invalidates the track list.
    @State private var progressDisplay = PlaybackProgressDisplay()
    /// Now-playing block hover — brightens the artist link (M4.1).
    @State private var npHover = false

    var body: some View {
        content
            .task(id: app.nowPlaying?.uri) {
                updateProgressDisplay()
                while !Task.isCancelled {
                    updateProgressDisplay()
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
            .onChange(of: app.isPlaybackReady) { _, ready in
                if !ready { progressDisplay.resetInteraction() }
            }
            .onChange(of: app.nowPlaying?.uri) { _, _ in
                progressDisplay.resetInteraction()
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
                ), in: 0 ... 1, onEditingChanged: { isEditing in
                    if isEditing {
                        app.beginVolumeEditing()
                    } else {
                        app.commitVolume()
                    }
                })
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
                    onEnded: {
                        app.setVolume($0)
                        app.commitVolume()
                    },
                    onCancelled: app.cancelVolumeEditing
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
                            onChanged: { progressDisplay.drag(to: $0) },
                            onEnded: {
                                seek(to: $0)
                            },
                            onCancelled: { progressDisplay.cancelDrag() }
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
        min(
            progressDisplay.effectivePositionMs(durationMs: max(app.durationMs, 0)),
            max(app.durationMs, 0)
        )
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
                        progressDisplay.drag(to: fraction)
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                        seek(to: fraction)
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
                seek(to: min(progressFraction + step, 1))
            case .decrement:
                seek(to: max(progressFraction - step, 0))
            @unknown default:
                break
            }
        }
    }

    private func progressWidth(_ geo: GeometryProxy) -> CGFloat {
        geo.size.width * progressFraction
    }

    private func updateProgressDisplay() {
        progressDisplay.update(
            positionMs: app.playbackPositionMs,
            confirmedPositionMs: app.playbackConfirmedPositionMs,
            playRequestID: app.playbackRequestID
        )
    }

    private func seek(to fraction: Double) {
        progressDisplay.commitSeek(to: fraction, durationMs: max(app.durationMs, 0))
        app.seek(to: fraction)
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
