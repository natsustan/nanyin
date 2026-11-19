import SwiftUI

/// The graphite transport bar along the bottom of the window.
struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    static let height: CGFloat = 46

    var body: some View {
        let player = app.player
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Button(action: player.previous) { Image(systemName: "backward.fill") }
                    .buttonStyle(GlossyRoundButtonStyle(diameter: 24))
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(GlossyRoundButtonStyle(diameter: 30))
                Button(action: player.next) { Image(systemName: "forward.fill") }
                    .buttonStyle(GlossyRoundButtonStyle(diameter: 24))
            }
            VolumeSlider()
                .frame(width: 80)
            ProgressScrubber()
            HStack(spacing: 2) {
                Button(action: player.toggleShuffle) { Image(systemName: "shuffle") }
                    .buttonStyle(GraphiteToggleStyle(isOn: player.shuffle))
                    .help("Shuffle")
                Button(action: player.cycleRepeat) {
                    Image(systemName: player.repeatMode == .track ? "repeat.1" : "repeat")
                }
                .buttonStyle(GraphiteToggleStyle(isOn: player.repeatMode != .off))
                .help("Repeat")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(Theme.graphite)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.graphiteEdge).frame(height: 1)
                Rectangle().fill(Theme.graphiteHighlight).frame(height: 1)
            }
        }
    }
}

/// Elapsed time, the scrub bar and the track length. The position is
/// derived from the player's anchor each frame, so nothing app-wide changes
/// while a song plays.
private struct ProgressScrubber: View {
    @Environment(AppModel.self) private var app
    @State private var dragFraction: Double?

    var body: some View {
        let player = app.player
        let duration = player.track?.durationMs ?? 0
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let current = min(player.position.current(at: context.date), duration)
            let fraction = dragFraction ?? (duration > 0 ? Double(current) / Double(duration) : 0)
            HStack(spacing: 8) {
                TimeLabel(ms: dragFraction.map { Int($0 * Double(duration)) } ?? current)
                AquaTrack(fraction: fraction, knob: duration > 0) { value, ended in
                    dragFraction = ended ? nil : value
                    if ended { player.seek(to: Int(value * Double(duration))) }
                }
                .frame(height: 14)
                TimeLabel(ms: duration)
            }
        }
    }
}

private struct TimeLabel: View {
    let ms: Int

    var body: some View {
        let seconds = max(ms, 0) / 1000
        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
            .font(AquaFont.regular(10))
            .monospacedDigit()
            .foregroundStyle(Theme.hex(0xD6D6D6))
            .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
            .frame(width: 34)
    }
}

private struct VolumeSlider: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.hex(0xC8C8C8))
            AquaTrack(fraction: Double(app.player.volume) / Double(UInt16.max), knob: true) { value, _ in
                app.player.setVolume(UInt16(value * Double(UInt16.max)))
            }
            .frame(height: 14)
        }
    }
}

/// A recessed dark groove filled in green up to `fraction`, with a glossy
/// knob. Reports drags as fractions; `ended` is true on release.
struct AquaTrack: View {
    let fraction: Double
    var knob = true
    let onChange: (Double, _ ended: Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = min(max(fraction, 0), 1)
            let groove = Capsule()
            ZStack(alignment: .leading) {
                groove.fill(LinearGradient(colors: [Theme.hex(0x161616), Theme.hex(0x3A3A3A)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 6)
                    .overlay(groove.strokeBorder(.black.opacity(0.6), lineWidth: 0.5))
                groove.fill(LinearGradient(colors: [Theme.hex(0xA6D82E), Theme.hex(0x6E9E00)], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(6, width * clamped), height: 6)
                    .opacity(clamped > 0 ? 1 : 0)
                if knob {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.hex(0xFAFAFA), Theme.hex(0xB5B5B5)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(.black.opacity(0.65), lineWidth: 0.75))
                        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                        .frame(width: 11, height: 11)
                        .offset(x: (width - 11) * clamped)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChange(min(max($0.location.x / width, 0), 1), false) }
                    .onEnded { onChange(min(max($0.location.x / width, 0), 1), true) }
            )
        }
    }
}
