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
                .font(AquaFont.regular(11))
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
            .font(AquaFont.bold(11))
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
