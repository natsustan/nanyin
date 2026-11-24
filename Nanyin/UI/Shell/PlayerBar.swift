import NanyinKit
import SwiftUI

/// The graphite transport bar along the bottom of the window.
struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    @State private var showDevices = false
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
                .frame(width: 86)
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
                Button { showDevices.toggle() } label: {
                    Image(systemName: "hifispeaker.2")
                }
                .buttonStyle(GraphiteToggleStyle(isOn: player.playingElsewhere || showDevices))
                .help("Connect to a Device")
                .popover(isPresented: $showDevices, arrowEdge: .top) {
                    ConnectDevicesPopover(isPresented: $showDevices)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(Theme.graphite)
        .hairline(.top, Theme.graphiteHighlight)
        .padding(.top, 1)
        .hairline(.top, Theme.graphiteEdge)
    }
}

/// Elapsed time, the scrub bar and the track length. The position is
/// derived from the player's anchor, so nothing app-wide changes while a
/// song plays; the view ticks only while the position advances.
private struct ProgressScrubber: View {
    @Environment(AppModel.self) private var app
    @State private var dragFraction: Double?

    var body: some View {
        let player = app.player
        let duration = player.track?.durationMs ?? 0
        let position = player.position
        let schedule = PositionSchedule(position: position)
        TimelineView(schedule) { context in
            let current = min(position.current(at: context.date), duration)
            let fraction = dragFraction ?? (duration > 0 ? Double(current) / Double(duration) : 0)
            HStack(spacing: 8) {
                if player.isLoading {
                    ProgressView().controlSize(.mini)
                }
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

/// Ticks on whole seconds of the playing position, and not at all while it
/// stands still.
private struct PositionSchedule: TimelineSchedule {
    let position: Player.Position

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard position.advancing else {
            var once = true
            return AnyIterator { defer { once = false }; return once ? start : nil }
        }
        // The next moment the elapsed time crosses a whole second.
        let offset = Double(1000 - position.current(at: start) % 1000) / 1000
        var next: Date? = start
        var boundary = start.addingTimeInterval(offset)
        return AnyIterator {
            if let first = next {
                next = nil
                return first
            }
            defer { boundary = boundary.addingTimeInterval(1) }
            return boundary
        }
    }
}

private struct TimeLabel: View {
    let ms: Int

    var body: some View {
        Text(TrackRow.format(ms: ms))
            .font(AquaFont.regular(11))
            .monospacedDigit()
            .foregroundStyle(Theme.hex(0xD6D6D6))
            .engraved()
            .frame(width: 38)
    }
}

private struct VolumeSlider: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let player = app.player
        let fraction = Double(player.volume) / Double(UInt16.max)
        HStack(spacing: 4) {
            Button(action: player.toggleMute) {
                Image(systemName: speakerSymbol(muted: player.isMuted, fraction: fraction))
                    .font(.system(size: 10))
                    .foregroundStyle(player.isMuted ? Theme.secondaryText : Theme.hex(0xC8C8C8))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "Unmute" : "Mute")
            AquaTrack(fraction: fraction, knob: true) { value, ended in
                player.setVolume(UInt16(value * Double(UInt16.max)), final: ended)
            }
            .frame(height: 14)
        }
    }

    private func speakerSymbol(muted: Bool, fraction: Double) -> String {
        if muted || fraction <= 0.001 { return "speaker.slash.fill" }
        if fraction < 0.34 { return "speaker.wave.1.fill" }
        if fraction < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

private struct ConnectDevicesPopover: View {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool

    var body: some View {
        let connect = app.connect
        let session = app.session
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connect to a Device")
                    .font(AquaFont.bold(12.5))
                    .foregroundStyle(Theme.text)
                Spacer()
                if connect.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { connect.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Devices")
                }
            }

            Divider().overlay(Theme.divider)

            if session.isReady {
                deviceRow(
                    title: session.localDeviceName,
                    subtitle: connect.localIsActive ? "Playing on this Mac" : "This Mac · Click to play here",
                    icon: "laptopcomputer",
                    isActive: connect.localIsActive,
                    disabled: connect.isTransferring
                ) {
                    connect.transferToThisMac()
                    isPresented = false
                }
            }

            ForEach(connect.remoteDevices, id: \.stableID) { device in
                deviceRow(
                    title: device.name,
                    subtitle: device.is_restricted
                        ? "\(device.type) · Restricted"
                        : device.is_active ? "Active" : device.type,
                    icon: symbol(for: device.type),
                    isActive: device.is_active,
                    disabled: device.is_restricted || connect.isTransferring
                ) {
                    connect.transfer(to: device)
                    isPresented = false
                }
            }

            if connect.needsResignInForDevices {
                Text("Sign out and sign in again to list and control other Spotify Connect devices.")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = connect.error {
                Text(error)
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.hex(0xF08B7D))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !connect.isLoading && connect.remoteDevices.isEmpty && !session.isReady {
                Text("No active Spotify Connect devices found.")
                    .font(AquaFont.regular(11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(Theme.hex(0x2B2B2B))
        .preferredColorScheme(.dark)
        .onAppear { connect.refresh() }
    }

    private func deviceRow(
        title: String,
        subtitle: String,
        icon: String,
        isActive: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isActive ? Theme.green : Theme.sidebarText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(isActive ? AquaFont.bold(12) : AquaFont.regular(12))
                        .foregroundStyle(isActive ? Theme.green : Theme.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AquaFont.regular(10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Theme.green.opacity(0.12) : Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func symbol(for deviceType: String) -> String {
        switch deviceType.lowercased() {
        case "computer": "laptopcomputer"
        case "smartphone": "iphone"
        case "tablet": "ipad"
        case "speaker", "avr", "stb": "hifispeaker"
        case "tv": "tv"
        case "automobile": "car"
        default: "hifispeaker.2"
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
