import SwiftUI

/// The "textured rounded" button of Snow Leopard toolbars: a light metal
/// gradient with a dark rim, pressed darker. Always drawn light, wherever
/// it sits.
struct TexturedButtonStyle: ButtonStyle {
    var width: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        TexturedButtonBody(configuration: configuration, width: width)
    }

    private struct TexturedButtonBody: View {
        let configuration: Configuration
        let width: CGFloat?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 4)
            configuration.label
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.hex(0x3A3A3A).opacity(isEnabled ? 1 : 0.35))
                .embossed()
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
            .shadow(color: .white.opacity(0.7), radius: 0, y: 0.5)
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
            }
            .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
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
            .engraved()
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }
}

/// A pane header in the graphite gradient, like the column bar of a list.
struct GraphiteHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(AquaFont.bold(12))
            .foregroundStyle(Theme.hex(0xE6E6E6))
            .engraved()
            .padding(.horizontal, 8)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.graphite)
            .hairline(.top, Theme.graphiteHighlight)
            .hairline(.bottom, Theme.graphiteEdge)
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
                .embossed()
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
            .embossed()
            .padding(.horizontal, 11)
            .frame(height: 20)
            .background {
                shape.fill(LinearGradient(
                    colors: configuration.isPressed
                        ? [Theme.pillPressedTop, Theme.pillPressedBottom]
                        : [Theme.pillTop, Theme.pillBottom],
                    startPoint: .top, endPoint: .bottom))
            }
            .overlay(shape.strokeBorder(Theme.pillEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            .contentShape(shape)
            .environment(\.colorScheme, .light)
    }
}

/// Rectangular Aqua text input (white inset field with focus halo), for forms
/// like sign-in and proxy settings rather than the toolbar search capsule.
struct AquaTextField: View {
    @Binding var text: String
    var prompt: String
    var isSecure = false
    var monospaced = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        HStack(spacing: 4) {
            Group {
                if isSecure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, design: .monospaced) : AquaFont.regular(12))
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
        .frame(height: 26)
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
                .shadow(color: .white.opacity(isEnabled ? 0.35 : 0), radius: 0, y: 1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: 30)
                .padding(.horizontal, 14)
                .background {
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
                .shadow(color: .black.opacity(isEnabled ? 0.35 : 0.15), radius: 2, y: 1)
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
