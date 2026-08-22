//
//  Theme.swift
//  Nanyin
//

import SwiftUI

enum AppThemeID: String, CaseIterable, Identifiable {
    case nanyinDark
    case classic2010

    static let preferenceKey = "appearance.theme"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nanyinDark: "Nanyin Dark"
        case .classic2010: "Classic 2010"
        }
    }

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .nanyinDark
    }
}

struct AppTheme {
    struct Fill {
        struct Stop {
            let color: Color
            let location: CGFloat
        }

        private enum Kind {
            case solid(Color)
            case linear(stops: [Stop], startPoint: UnitPoint, endPoint: UnitPoint)
        }

        private let kind: Kind

        static func solid(_ color: Color) -> Self {
            Self(kind: .solid(color))
        }

        static func linear(
            _ stops: [Stop],
            from startPoint: UnitPoint = .top,
            to endPoint: UnitPoint = .bottom
        ) -> Self {
            Self(kind: .linear(stops: stops, startPoint: startPoint, endPoint: endPoint))
        }

        var isSolid: Bool {
            if case .solid = kind {
                return true
            }
            return false
        }

        var swiftUIStyle: AnyShapeStyle {
            switch kind {
            case let .solid(color):
                AnyShapeStyle(color)
            case let .linear(stops, startPoint, endPoint):
                AnyShapeStyle(
                    LinearGradient(
                        stops: stops.map { .init(color: $0.color, location: $0.location) },
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                )
            }
        }

        fileprivate var fallbackColor: Color {
            switch kind {
            case let .solid(color):
                color
            case let .linear(stops, _, _):
                stops.first?.color ?? .clear
            }
        }
    }

    struct Colors {
        let contentBackground: Fill
        let sidebarBackground: Fill
        let playerBackground: Fill
        let rowHover: Fill
        let primaryText: Color
        let secondaryText: Color
        let accent: Color
    }

    struct Typography {
        let body: Font
        let secondary: Font
        let compact: Font
        let sectionHeader: Font
    }

    struct Metrics {
        let standardRowHeight: CGFloat
        let compactRowHeight: CGFloat
        let controlHeight: CGFloat
        let cornerRadius: CGFloat
    }

    let id: AppThemeID
    let colors: Colors
    let typography: Typography
    let metrics: Metrics

    static func resolve(_ id: AppThemeID) -> Self {
        switch id {
        case .nanyinDark: .nanyinDark
        case .classic2010: .classic2010
        }
    }

    static let nanyinDark = Self(
        id: .nanyinDark,
        colors: Colors(
            contentBackground: .solid(Color(red: 0.071, green: 0.071, blue: 0.071)),
            sidebarBackground: .solid(.black),
            playerBackground: .solid(Color(red: 0.094, green: 0.094, blue: 0.094)),
            rowHover: .solid(Color(white: 0.10)),
            primaryText: .white,
            secondaryText: Color(white: 0.70),
            accent: Color(red: 0.114, green: 0.725, blue: 0.329)
        ),
        typography: Typography(
            body: .system(size: 13),
            secondary: .system(size: 11),
            compact: .system(size: 10),
            sectionHeader: .system(size: 10, weight: .bold)
        ),
        metrics: Metrics(
            standardRowHeight: 40,
            compactRowHeight: 24,
            controlHeight: 28,
            cornerRadius: 4
        )
    )

    static let classic2010 = Self(
        id: .classic2010,
        colors: Colors(
            contentBackground: .linear([
                .init(color: Color(white: 0.16), location: 0),
                .init(color: Color(white: 0.11), location: 1),
            ]),
            sidebarBackground: .linear([
                .init(color: Color(white: 0.19), location: 0),
                .init(color: Color(white: 0.12), location: 1),
            ]),
            playerBackground: .linear([
                .init(color: Color(white: 0.24), location: 0),
                .init(color: Color(white: 0.13), location: 1),
            ]),
            rowHover: .solid(Color(white: 0.22)),
            primaryText: Color(white: 0.94),
            secondaryText: Color(white: 0.70),
            accent: Color(red: 0.36, green: 0.53, blue: 0.22)
        ),
        typography: Typography(
            body: .system(size: 12),
            secondary: .system(size: 10),
            compact: .system(size: 9),
            sectionHeader: .system(size: 10, weight: .semibold)
        ),
        metrics: Metrics(
            standardRowHeight: 40,
            compactRowHeight: 22,
            controlHeight: 24,
            cornerRadius: 3
        )
    )
}

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTheme.nanyinDark
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

/// Phase 2 migrates feature views from these compatibility names to the
/// environment-injected semantic tokens. Keeping the aliases preserves the
/// existing Nanyin Dark rendering while the foundation lands independently.
enum Theme {
    static let background = AppTheme.nanyinDark.colors.contentBackground.fallbackColor
    static let sidebar = AppTheme.nanyinDark.colors.sidebarBackground.fallbackColor
    static let playerBar = AppTheme.nanyinDark.colors.playerBackground.fallbackColor
    static let hover = AppTheme.nanyinDark.colors.rowHover.fallbackColor
    static let accent = AppTheme.nanyinDark.colors.accent
    static let textSecondary = AppTheme.nanyinDark.colors.secondaryText
}

/// Pointing-hand cursor while hovering — shared by every clickable link
/// (track-row artist/album names, player-bar links, artist/album cards).
struct LinkCursor: ViewModifier {
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                inside = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    func linkCursor() -> some View {
        modifier(LinkCursor())
    }
}
