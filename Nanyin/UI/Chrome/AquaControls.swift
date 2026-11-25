import SwiftUI

/// The "textured rounded" button of Snow Leopard toolbars: a light metal
/// gradient with a dark rim, pressed darker. Always drawn light, wherever
/// it sits. Pass `segment` to join adjacent controls into one segmented pill.
struct TexturedButtonStyle: ButtonStyle {
    enum Segment {
        case standalone, leading, middle, trailing

        var radii: RectangleCornerRadii {
            switch self {
            case .standalone: .init(topLeading: 4, bottomLeading: 4, bottomTrailing: 4, topTrailing: 4)
            case .leading: .init(topLeading: 4, bottomLeading: 4, bottomTrailing: 0, topTrailing: 0)
            case .middle: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
            case .trailing: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 4, topTrailing: 4)
            }
        }
    }

    var width: CGFloat? = nil
    var segment: Segment = .standalone

    func makeBody(configuration: Configuration) -> some View {
        TexturedButtonBody(configuration: configuration, width: width, segment: segment)
    }

    private struct TexturedButtonBody: View {
        let configuration: Configuration
        let width: CGFloat?
        let segment: Segment
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = UnevenRoundedRectangle(cornerRadii: segment.radii, style: .continuous)
            configuration.label
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.hex(0x3A3A3A).opacity(isEnabled ? 1 : 0.35))
                .frame(width: width, height: 22)
                .padding(.horizontal, width == nil ? 8 : 0)
                .background {
                    shape.fill(LinearGradient(
                        colors: configuration.isPressed
                            ? [Theme.hex(0xA8A8A8), Theme.hex(0xC4C4C4)]
                            : [Theme.hex(0xFBFBFB), Theme.hex(0xCFCFCF)],
                        startPoint: .top, endPoint: .bottom))
                }
                .overlay(shape.strokeBorder(Theme.hex(0x5E5E5E, 0.85), lineWidth: 1))
                .background(shape.fill(.white.opacity(0.35)).offset(y: 1))
                .contentShape(shape)
                .environment(\.colorScheme, .light)
        }
    }
}

/// The Aqua search field: a white capsule with a soft inner shadow.
struct AquaSearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var icon: String? = "magnifyingglass"
    var onSubmit: () -> Void = {}
    /// Changing it puts the cursor in the field.
    var focusRequest = 0
    @FocusState private var focused: Bool

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.hex(0x6A6A6A))
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(AquaFont.regular(12))
                .foregroundStyle(.black)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.hex(0x8A8A8A))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(shape.fill(.white))
        .overlay {
            shape.stroke(.black.opacity(0.35), lineWidth: 2)
                .blur(radius: 1)
                .offset(y: 1)
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(focused ? Theme.hex(0x5E8FD6) : Theme.hex(0x6E6E6E), lineWidth: 1))
        .onChange(of: focusRequest) { focused = true }
        .background {
            if focused {
                shape.stroke(Theme.hex(0x7EAAE8, 0.7), lineWidth: 5).blur(radius: 1.5)
            }
        }
        .environment(\.colorScheme, .light)
    }
}

/// A round glossy button for the player bar, its size set by `diameter`.
struct GlossyRoundButtonStyle: ButtonStyle {
    var diameter: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.38, weight: .black))
            .foregroundStyle(Theme.hex(0x2C2C2C))
            .frame(width: diameter, height: diameter)
            .background {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: configuration.isPressed
                            ? [Theme.hex(0x9A9A9A), Theme.hex(0xC8C8C8)]
                            : [Theme.hex(0xFAFAFA), Theme.hex(0xBDBDBD)],
                        startPoint: .top, endPoint: .bottom))
                    Ellipse()
                        .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(width: diameter * 0.7, height: diameter * 0.45)
                        .offset(y: -diameter * 0.2)
                }
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            }
            .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// A small flat glyph button on graphite (shuffle, repeat), lit green when on.
struct GraphiteToggleStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? Theme.green : Theme.hex(0xC8C8C8))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }
}

/// A recessed dark filter capsule for charcoal/graphite bars (so in-page
/// filtering blends naturally without a glaring white box over dark chrome).
struct DarkFilterField: View {
    @Binding var text: String
    var prompt = "Filter"
    @FocusState private var focused: Bool

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(AquaFont.regular(11.5))
                .foregroundStyle(Theme.text)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(shape.fill(Theme.hex(0x222222)))
        .overlay(shape.strokeBorder(focused ? Theme.green.opacity(0.85) : Theme.hex(0x141414), lineWidth: 1))
        .background(shape.fill(.white.opacity(0.1)).offset(y: 1))
    }
}

/// Compact graphite action button for dark in-page toolbars (Play, Sort).
struct GraphiteActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration)
    }

    private struct BodyView: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 4)
            configuration.label
                .font(AquaFont.bold(11))
                .foregroundStyle(Theme.text.opacity(isEnabled ? 1 : 0.4))
                .frame(height: 20)
                .padding(.horizontal, 9)
                .background {
                    shape.fill(LinearGradient(
                        colors: configuration.isPressed
                            ? [Theme.hex(0x2E2E2E), Theme.hex(0x3D3D3D)]
                            : [Theme.hex(0x555555), Theme.hex(0x393939)],
                        startPoint: .top, endPoint: .bottom))
                }
                .overlay(shape.strokeBorder(Theme.hex(0x1C1C1C), lineWidth: 1))
                .overlay(alignment: .top) {
                    if !configuration.isPressed {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.14))
                            .frame(height: 1)
                            .padding(.horizontal, 2)
                            .padding(.top, 1)
                    }
                }
                .contentShape(shape)
        }
    }
}

/// A pane header in the graphite gradient, like the column bar of a list.
struct GraphiteHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(AquaFont.bold(12))
            .foregroundStyle(Theme.hex(0xE6E6E6))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.graphite)
            .hairline(.top, Theme.graphiteHighlight)
            .hairline(.bottom, Theme.graphiteEdge)
    }
}

/// The shared 24-pt brushed-metal sub-bar spanning the top of the sidebar,
/// top-level library pages, What's New tabs, and lyrics pane.
struct MetalSubBar<Content: View>: View {
    @Environment(\.appearsActive) private var appearsActive
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.subBarHeight)
            .background {
                Theme.subBar(active: appearsActive)
                    .hairline(.top, Theme.subBarHighlight)
                    .hairline(.bottom, Theme.divider)
            }
    }
}

/// Vertical etched separator inside a 24-pt brushed-metal sub-bar.
struct MetalSubBarDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.subBarDividerDark).frame(width: 1)
            Rectangle().fill(Theme.subBarDividerLight).frame(width: 1)
        }
    }
}

/// A title + optional muted detail inside a `MetalSubBar` (for Play Queue,
/// Starred, Albums, Artists, Search).
struct MetalSubBarTitle: View {
    @Environment(\.appearsActive) private var appearsActive
    let title: String
    var detail = ""
    var icon: String? = nil
    var iconTint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle((iconTint ?? Theme.metalText).opacity(appearsActive ? 1 : 0.65))
            }
            Text(title)
                .font(AquaFont.bold(12))
                .foregroundStyle(Theme.metalText.opacity(appearsActive ? 1 : 0.65))
                .lineLimit(1)
            if !detail.isEmpty {
                Text("· \(detail)")
                    .font(AquaFont.regular(11))
                    .foregroundStyle(Theme.metalSecondaryText.opacity(appearsActive ? 1 : 0.65))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
    }
}

/// Subtle etched horizontal groove on charcoal surfaces (sidebar & What's New).
struct EtchedDivider: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.grooveDark).frame(height: 1)
            Rectangle().fill(Theme.grooveLight).frame(height: 1)
        }
    }
}

/// A flat brushed-metal button inside a 24-pt sub-bar (e.g. Sidebar `+`,
/// What's New Refresh, Lyrics close), recessed darker while pressed.
struct MetalSubBarButtonStyle: ButtonStyle {
    var width: CGFloat? = 26

    func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration, width: width)
    }

    private struct BodyView: View {
        let configuration: Configuration
        let width: CGFloat?
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.appearsActive) private var appearsActive
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.metalText.opacity(isEnabled ? (appearsActive ? 1 : 0.65) : 0.35))
                .frame(width: width, height: Theme.subBarHeight)
                .padding(.horizontal, width == nil ? 8 : 0)
                .background {
                    if configuration.isPressed {
                        Theme.subBarPressed
                    } else if hovering && isEnabled {
                        Theme.subBarHover
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// A compact light-metal Aqua pill button on dark charcoal content
/// (matching the 2010 "More" button on What's New).
struct MetalPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        configuration.label
            .font(AquaFont.bold(11))
            .foregroundStyle(Theme.metalText)
            .padding(.horizontal, 11)
            .frame(height: 20)
            .background {
                shape.fill(LinearGradient(
                    colors: configuration.isPressed
                        ? [Theme.pillPressedTop, Theme.pillPressedBottom]
                        : [Theme.pillTop, Theme.pillBottom],
                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            }
            .overlay(shape.strokeBorder(Theme.pillEdge, lineWidth: 1))
            .contentShape(shape)
            .environment(\.colorScheme, .light)
    }
}

/// Rectangular Aqua text input (white inset field with focus halo), for forms
/// like sign-in, proxy settings, and playlist details.
struct AquaTextField: View {
    @Binding var text: String
    var prompt: String
    var isSecure = false
    var monospaced = false
    var lineLimit: ClosedRange<Int>? = nil
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        let isMultiline = lineLimit != nil
        HStack(alignment: isMultiline ? .top : .center, spacing: 4) {
            Group {
                if isSecure {
                    SecureField(prompt, text: $text)
                } else if let lineLimit {
                    TextField(prompt, text: $text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, design: .monospaced) : AquaFont.regular(12))
            .foregroundStyle(.black)
            .focused($focused)
            .onSubmit(onSubmit)

            if !text.isEmpty && !isMultiline {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.hex(0x8A8A8A))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isMultiline ? 6 : 0)
        .frame(minHeight: 26)
        .frame(height: isMultiline ? nil : 26)
        .background(shape.fill(.white))
        .overlay {
            shape.stroke(.black.opacity(0.32), lineWidth: 2)
                .blur(radius: 1)
                .offset(y: 1)
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(focused ? Theme.hex(0x5E8FD6) : Theme.hex(0x5A5A5A), lineWidth: 1))
        .background {
            if focused {
                shape.stroke(Theme.hex(0x7EAAE8, 0.7), lineWidth: 5).blur(radius: 1.5)
            }
        }
        .environment(\.colorScheme, .light)
    }
}

/// The primary green Aqua action button for key sign-in / approval actions.
struct AquaPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration, fullWidth: fullWidth)
    }

    private struct BodyView: View {
        let configuration: Configuration
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 5)
            configuration.label
                .font(AquaFont.bold(12.5))
                .foregroundStyle(isEnabled ? Theme.hex(0x162200) : Theme.hex(0x2A2A2A, 0.55))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: 30)
                .padding(.horizontal, 14)
                .background {
                    Group {
                        if !isEnabled {
                            shape.fill(LinearGradient(
                                colors: [Theme.hex(0x6E6E6E), Theme.hex(0x585858)],
                                startPoint: .top, endPoint: .bottom))
                        } else if configuration.isPressed {
                            shape.fill(LinearGradient(
                                colors: [Theme.hex(0x699900), Theme.hex(0x7EB400)],
                                startPoint: .top, endPoint: .bottom))
                        } else {
                            shape.fill(LinearGradient(
                                colors: [Theme.hex(0xA4D62A), Theme.green, Theme.hex(0x6EA000)],
                                startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .shadow(color: .black.opacity(isEnabled ? 0.35 : 0.15), radius: 2, y: 1)
                }
                .overlay(
                    shape.strokeBorder(
                        isEnabled ? Theme.hex(0x3D5900) : Theme.hex(0x3A3A3A),
                        lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    if isEnabled && !configuration.isPressed {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.28))
                            .frame(height: 1)
                            .padding(.horizontal, 2)
                            .padding(.top, 1)
                    }
                }
                .contentShape(shape)
        }
    }
}

/// Small toggle segment button for dark graphite forms (e.g. Proxy Mode).
struct DarkSegmentButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        configuration.label
            .font(selected ? AquaFont.bold(11.5) : AquaFont.regular(11.5))
            .foregroundStyle(selected ? Theme.hex(0x162200) : Theme.text)
            .frame(height: 24)
            .padding(.horizontal, 10)
            .background {
                if selected {
                    shape.fill(LinearGradient(
                        colors: [Theme.hex(0x9ED024), Theme.green],
                        startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(LinearGradient(
                        colors: configuration.isPressed
                            ? [Theme.hex(0x383838), Theme.hex(0x464646)]
                            : [Theme.hex(0x4A4A4A), Theme.hex(0x3A3A3A)],
                        startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.strokeBorder(selected ? Theme.hex(0x4A6B00) : Theme.hex(0x202020), lineWidth: 1))
            .contentShape(shape)
    }
}

extension View {
    /// Applies `.pointerStyle(.columnResize)` on macOS 15+, falling back cleanly on macOS 14.
    @ViewBuilder func columnResizePointer() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.columnResize)
        } else {
            self
        }
    }

    /// Applies `.pointerStyle(.link)` when `active` on macOS 15+, falling back cleanly on macOS 14.
    @ViewBuilder func linkPointer(_ active: Bool) -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(active ? .link : nil)
        } else {
            self
        }
    }
}
