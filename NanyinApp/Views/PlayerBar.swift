//
//  PlayerBar.swift
//  Nanyin
//

import SwiftUI

struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    @State private var draggingProgress: Double?
    /// Now-playing block hover — brightens the artist link (M4.1).
    @State private var npHover = false
    /// Local playback-position tick — deliberately NOT in AppModel so the
    /// 2Hz update only invalidates this bar, never the track list.
    @State private var displayPosition: UInt32 = 0

    var body: some View {
        HStack(spacing: 0) {
            // Now playing (left)
            HStack(spacing: 12) {
                artwork
                    .frame(width: 52, height: 52)
                    .cornerRadius(4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.nowPlaying?.title ?? "Not playing")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let np = app.nowPlaying {
                        if np.artist.isEmpty {
                            Text("—")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        } else {
                            Button {
                                app.openNowPlayingArtist()
                            } label: {
                                Text(np.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(npHover ? .white : Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .linkCursor()
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }

                // Like the playing track (M4.2).
                if let np = app.nowPlaying, let id = SpotifyClient.trackId(from: np.uri) {
                    let known = app.isLikeKnown(id)
                    let liked = app.likedIDs.contains(id)
                    Button {
                        app.toggleLikePlaying()
                    } label: {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundStyle(liked ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!known)
                    .opacity(known ? 1 : 0.35)
                    .padding(.leading, 4)
                    .help(known ? (liked ? "Remove from Liked Songs" : "Save to Liked Songs") : "Checking Liked Songs…")
                    .task(id: id) {
                        app.requestLikedState(id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .onHover { npHover = $0 }

            // Transport (center)
            VStack(spacing: 6) {
                HStack(spacing: 24) {
                    Button {
                        app.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 11))
                            .foregroundStyle(app.shuffle ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    button("backward.fill") { app.prev() }
                    Button {
                        app.togglePlay()
                    } label: {
                        Image(systemName: app.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    button("forward.fill") { app.next() }

                    Button {
                        app.cycleRepeat()
                    } label: {
                        Image(systemName: app.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(app.repeatMode == .off ? Theme.textSecondary : Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .disabled(!app.isPlaybackReady)

                HStack(spacing: 8) {
                    Text(Theme.fmtTime(effectivePosition))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, alignment: .trailing)

                    slider
                        .allowsHitTesting(app.isPlaybackReady)

                    Text(Theme.fmtTime(max(app.durationMs, 0)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, alignment: .leading)
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
                            app.page == .queue ? Theme.accent : Theme.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .help("Queue")

                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: Binding(
                    get: { app.volume },
                    set: { app.setVolume($0) }
                ), in: 0 ... 1)
                .controlSize(.mini)
                .frame(width: 130)
                .disabled(!app.isPlaybackReady)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
        }
        .background(Theme.playerBar)
        .task(id: app.nowPlaying?.uri) {
            displayPosition = 0
            while !Task.isCancelled {
                if draggingProgress == nil {
                    let p = Core.positionMs
                    if p != displayPosition { displayPosition = p }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private var effectivePosition: UInt32 {
        min(draggingProgress.map { UInt32($0 * Double(max(app.durationMs, 1))) } ?? displayPosition, max(app.durationMs, 0))
    }

    private var slider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 0.28))
                    .frame(height: 4)
                Capsule()
                    .fill(Theme.accent)
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
    }

    private func progressWidth(_ geo: GeometryProxy) -> CGFloat {
        guard app.durationMs > 0 else { return 0 }
        let fraction = draggingProgress ?? Double(displayPosition) / Double(max(app.durationMs, 1))
        return geo.size.width * min(max(fraction, 0), 1)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = app.nowPlaying?.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholderArtwork
            }
        } else {
            placeholderArtwork
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            Color(white: 0.14)
            Image("MusicIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
