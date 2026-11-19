import AppKit
import SwiftUI

/// The 2010 Spotify-for-Mac look: light Aqua metal around a charcoal
/// library, Lucida Grande throughout, the lime green of that era as accent.
enum Theme {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha)
    }

    static func nsHex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
    }

    // Accent
    static let green = hex(0x84BD00)
    static let nsGreen = nsHex(0x84BD00)

    // Metal (title bar, unified toolbar)
    static let metalTop = hex(0xDCDCDC)
    static let metalBottom = hex(0xA9A9A9)
    static let metalInactiveTop = hex(0xEDEDED)
    static let metalInactiveBottom = hex(0xD3D3D3)
    static let metalEdge = hex(0x4E4E4E)
    static let metalText = hex(0x262626)

    // Graphite (player bar, pane headers)
    static let graphiteTop = hex(0x585858)
    static let graphiteBottom = hex(0x363636)
    static let graphiteEdge = hex(0x1C1C1C)
    static let graphiteHighlight = hex(0xFFFFFF, 0.14)

    // Library
    static let sidebar = hex(0x3B3B3B)
    static let sidebarText = hex(0xD8D8D8)
    static let sidebarHeading = hex(0x9C9C9C)
    static let content = hex(0x2A2A2A)
    static let rowEven = nsHex(0x2D2D2D)
    static let rowOdd = nsHex(0x323232)
    static let text = hex(0xE2E2E2)
    static let nsText = nsHex(0xE2E2E2)
    static let secondaryText = hex(0x9A9A9A)
    static let nsSecondaryText = nsHex(0x9A9A9A)
    static let divider = hex(0x1E1E1E)
    static let selectionTop = hex(0x767676)
    static let selectionBottom = hex(0x5C5C5C)
    static let nsSelectionTop = nsHex(0x767676)
    static let nsSelectionBottom = nsHex(0x5C5C5C)

    static var metal: LinearGradient {
        LinearGradient(colors: [metalTop, metalBottom], startPoint: .top, endPoint: .bottom)
    }

    static var graphite: LinearGradient {
        LinearGradient(colors: [graphiteTop, graphiteBottom], startPoint: .top, endPoint: .bottom)
    }

    static var selection: LinearGradient {
        LinearGradient(colors: [selectionTop, selectionBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Lucida Grande, the Aqua system font (still shipped with macOS).
enum AquaFont {
    static let family = "Lucida Grande"

    static func regular(_ size: CGFloat) -> Font { .custom(family, fixedSize: size) }
    static func bold(_ size: CGFloat) -> Font { .custom(family, fixedSize: size).bold() }

    static func ns(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let font = NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
    }
}
