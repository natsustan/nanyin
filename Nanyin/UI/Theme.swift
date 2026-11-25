import AppKit
import SwiftUI

/// The 2010 Spotify-for-Mac look: light Aqua metal around a charcoal
/// library, Lucida Grande throughout, the lime green of that era as accent.
/// Colours are defined once as `NSColor` (AppKit drawing needs them) and
/// bridged for SwiftUI.
enum Theme {
    static func ns(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
    }

    static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> Color {
        Color(nsColor: ns(value, alpha))
    }

    // Accent
    static let nsGreen = ns(0x84BD00)
    static let green = Color(nsColor: nsGreen)
    /// A starred song's star.
    static let nsStar = ns(0xF2C230)
    static let star = Color(nsColor: nsStar)

    // The small button laid over artwork
    static let artworkButton = hex(0x000000, 0.6)
    static let artworkButtonEdge = hex(0xFFFFFF, 0.35)
    static let artworkButtonGlyph = hex(0xFFFFFF)

    // Metal (title bar, unified toolbar, buttons on it)
    static let metalText = hex(0x262626)
    static let metalEdge = hex(0x4E4E4E)
    static func metal(active: Bool) -> LinearGradient {
        LinearGradient(
            colors: active ? [hex(0xDCDCDC), hex(0xA9A9A9)] : [hex(0xEDEDED), hex(0xD3D3D3)],
            startPoint: .top, endPoint: .bottom)
    }

    // Graphite (player bar, pane and column headers)
    static let nsGraphiteTop = ns(0x585858)
    static let nsGraphiteBottom = ns(0x363636)
    static let nsGraphiteEdge = ns(0x1C1C1C)
    static let nsGraphiteHighlight = NSColor.white.withAlphaComponent(0.14)
    static let graphiteEdge = Color(nsColor: nsGraphiteEdge)
    static let graphiteHighlight = Color(nsColor: nsGraphiteHighlight)
    static let graphite = LinearGradient(
        colors: [Color(nsColor: nsGraphiteTop), Color(nsColor: nsGraphiteBottom)], startPoint: .top, endPoint: .bottom)

    // Library
    static let sidebar = hex(0x3B3B3B)
    static let sidebarText = hex(0xD8D8D8)
    static let sidebarHeading = hex(0x9C9C9C)
    static let content = hex(0x2A2A2A)
    static let nsText = ns(0xE2E2E2)
    static let text = Color(nsColor: nsText)
    static let nsSecondaryText = ns(0x9A9A9A)
    static let secondaryText = Color(nsColor: nsSecondaryText)
    static let divider = hex(0x1E1E1E)
    static let pageHeader = LinearGradient(colors: [hex(0x3A3A3A), hex(0x2C2C2C)], startPoint: .top, endPoint: .bottom)

    private static let nsRows = [ns(0x2D2D2D), ns(0x323232)]
    /// Zebra stripe colour of row `index`.
    static func row(_ index: Int) -> NSColor { nsRows[index & 1] }

    static let nsSelectionTop = ns(0x767676)
    static let nsSelectionBottom = ns(0x5C5C5C)
    static let selection = LinearGradient(
        colors: [Color(nsColor: nsSelectionTop), Color(nsColor: nsSelectionBottom)], startPoint: .top, endPoint: .bottom)
}

/// Lucida Grande, the Aqua system font (still shipped with macOS).
enum AquaFont {
    static let family = "Lucida Grande"

    static func regular(_ size: CGFloat) -> Font { .custom(family, fixedSize: size) }
    static func bold(_ size: CGFloat) -> Font { .custom(family, fixedSize: size).bold() }

    static func ns(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "LucidaGrande-Bold" : family, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

extension View {
    /// A 1-pt line along the top or bottom edge.
    func hairline(_ edge: VerticalEdge, _ color: Color) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle().fill(color).frame(height: 1)
        }
    }

    /// Light text pressed into a dark surface.
    func engraved() -> some View {
        shadow(color: .black.opacity(0.6), radius: 0, y: -1)
    }

    /// Dark text raised from a light metal surface.
    func embossed() -> some View {
        shadow(color: .white.opacity(0.6), radius: 0, y: 1)
    }
}
