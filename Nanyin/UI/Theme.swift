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
    /// The Library house tint in the 2010 rsms sidebar.
    static let sidebarLibraryTint = hex(0x76C4E8)

    // The small button laid over artwork
    static let artworkButton = hex(0x000000, 0.6)
    static let artworkButtonEdge = hex(0xFFFFFF, 0.35)
    static let artworkButtonGlyph = hex(0xFFFFFF)

    // Metal (title bar, unified toolbar, buttons on it)
    static let metalText = hex(0x262626)
    static let metalSecondaryText = hex(0x525252)
    static let metalEdge = hex(0x4E4E4E)
    static func metal(active: Bool) -> LinearGradient {
        LinearGradient(
            colors: active ? [hex(0xDCDCDC), hex(0xA9A9A9)] : [hex(0xEDEDED), hex(0xD3D3D3)],
            startPoint: .top, endPoint: .bottom)
    }

    // Sub-bar (the 24-pt brushed metal header shared by the sidebar, What's New tabs, and lyrics pane)
    static let subBarHeight: CGFloat = 24
    static let subBarDividerDark = hex(0x6E6E6E)
    static let subBarDividerLight = hex(0xFFFFFF, 0.38)
    static let subBarHighlight = hex(0xFFFFFF, 0.45)
    static let subBarHover = hex(0xFFFFFF, 0.16)
    static let subBarPressed = LinearGradient(
        colors: [hex(0x888888), hex(0xA4A4A4)],
        startPoint: .top, endPoint: .bottom)
    static let subBarActiveTab = LinearGradient(
        colors: [hex(0x323232), hex(0x2A2A2A)],
        startPoint: .top, endPoint: .bottom)
    static let subBarActiveTabHighlight = hex(0x3E3E3E)
    static func subBar(active: Bool) -> LinearGradient {
        LinearGradient(
            colors: active ? [hex(0xC9C9C9), hex(0x9E9E9E)] : [hex(0xDEDEDE), hex(0xC6C6C6)],
            startPoint: .top, endPoint: .bottom)
    }

    // Compact metallic pill button (e.g. "More" on dark charcoal pages)
    static let pillTop = hex(0xEDEDED)
    static let pillBottom = hex(0xBABABA)
    static let pillPressedTop = hex(0x9E9E9E)
    static let pillPressedBottom = hex(0xBDBDBD)
    static let pillEdge = hex(0x161616)

    // Etched horizontal grooves on charcoal surfaces
    static let grooveDark = hex(0x1E1E1E)
    static let grooveLight = hex(0xFFFFFF, 0.06)

    // Sidebar source-list selection (2010 Spotify / Aqua cool ice-blue metal)
    static let sidebarSelectionText = hex(0x1A2633)
    static let sidebarSelectionEdgeTop = hex(0xFFFFFF, 0.45)
    static let sidebarSelectionEdgeBottom = hex(0x1B2530, 0.75)
    static func sidebarSelection(active: Bool) -> LinearGradient {
        LinearGradient(
            colors: active
                ? [hex(0xC5D8EC), hex(0x98B5D4)]
                : [hex(0x9A9FA5), hex(0x7E848A)],
            startPoint: .top, endPoint: .bottom)
    }

    // Vinyl disc placeholder (rsms 2010 bottom-left record silhouette)
    static let vinylBackground = hex(0x272727)
    static let vinylDiscOuter = hex(0x363636)
    static let vinylDiscInner = hex(0x2D2D2D)
    static let vinylGroove = hex(0xFFFFFF, 0.05)
    static let vinylLabel = hex(0x3E3E3E)
    static let vinylSpindle = hex(0x222222)

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

    // Bottom player bar (Snow Leopard / 2010 Spotify brushed aluminum)
    static let playerBarEdge = hex(0x464646)
    static let playerBarHighlight = hex(0xFFFFFF, 0.55)
    static func playerBar(active: Bool) -> LinearGradient {
        LinearGradient(
            colors: active ? [hex(0xCECECE), hex(0x9C9C9C)] : [hex(0xE4E4E4), hex(0xC9C9C9)],
            startPoint: .top, endPoint: .bottom)
    }

    // Track table selection (2010 Snow Leopard / Spotify deep Aqua steel-blue)
    static let nsSelectionTop = ns(0x4F7CB6)
    static let nsSelectionBottom = ns(0x375E94)
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
