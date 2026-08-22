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

    }

    struct Colors {
        let contentBackground: Fill
        let sidebarBackground: Fill
        let playerBackground: Fill
        let surface: Fill
        let raisedSurface: Fill
        let cardHover: Fill
        let inputBackground: Fill
        let rowHover: Fill
        let rowSelected: Fill
        let rowCurrent: Fill
        let controlHover: Fill
        let controlPressed: Fill
        let subtleHover: Fill
        let disabledSurface: Fill
        let placeholderBackground: Fill
        let primaryText: Color
        let secondaryText: Color
        let tertiaryText: Color
        let disabledText: Color
        let inverseText: Color
        let accent: Color
        let divider: Color
        let border: Color
        let focusRing: Color
        let sliderTrack: Color
        let warning: Color
        let warningContainer: Fill
        let warningBorder: Color
        let error: Color
        let errorContainer: Fill
        let errorBorder: Color
        let shadow: Color
    }

    struct Typography {
        let body: Font
        let secondary: Font
        let compact: Font
        let sectionHeader: Font
        let pageTitle: Font
        let collectionHeader: Font
        let sectionTitle: Font
        let button: Font
        let controlLabel: Font
        let fieldLabel: Font
        let sheetTitle: Font
        let playerTitle: Font
        let trackIndex: Font
        let queueTitle: Font
        let queueRowTitle: Font
        let sectionLabel: Font
        let messageTitle: Font
        let tileTitle: Font
        let tileSubtitle: Font
        let mono: Font
        let duration: Font
        let metadata: Font
        let bannerText: Font
        let detailTitle: Font
        let bodyEmphasis: Font
        let cardTitle: Font
        let nowPlayingTitle: Font
        let collectionTitle: Font
    }

    struct Metrics {
        let standardRowHeight: CGFloat
        let compactRowHeight: CGFloat
        let controlHeight: CGFloat
        let cornerRadius: CGFloat
        let smallCornerRadius: CGFloat
        let iconButtonCornerRadius: CGFloat
        let imageCornerRadius: CGFloat
        let cardCornerRadius: CGFloat
        let pillCornerRadius: CGFloat
        let heroPillCornerRadius: CGFloat
        let smallPillCornerRadius: CGFloat
        let compactPillCornerRadius: CGFloat
        let pageHorizontalInset: CGFloat
        let pageTopInset: CGFloat
        let pageBottomInset: CGFloat
        let headerBottomInset: CGFloat
        let homeBottomInset: CGFloat
        let sectionHorizontalInset: CGFloat
        let sidebarInset: CGFloat
        let cardPadding: CGFloat
        let bannerHorizontalPadding: CGFloat
        let bannerVerticalPadding: CGFloat
        let fieldHorizontalPadding: CGFloat
        let fieldVerticalPadding: CGFloat
        let dividerVerticalPadding: CGFloat
        let compactFieldHorizontalPadding: CGFloat
        let compactFieldVerticalPadding: CGFloat
        let sectionTopPadding: CGFloat
        let sectionBottomPadding: CGFloat
        let smallPadding: CGFloat
        let trackRowVerticalPadding: CGFloat
        let queueRowVerticalPadding: CGFloat
        let likeButtonLeadingPadding: CGFloat
        let controlHorizontalPadding: CGFloat
        let controlVerticalPadding: CGFloat
        let sidebarWidth: CGFloat
        let playerBarHeight: CGFloat
        let toolbarSpacerHeight: CGFloat
        let queueRowHeight: CGFloat
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat
        let bannerCornerRadius: CGFloat
        let sheetPadding: CGFloat
        let sheetWidth: CGFloat
        let detailArtworkSize: CGFloat
        let homeFeatureArtworkSize: CGFloat
        let artistArtworkSize: CGFloat
        let discographyArtworkSize: CGFloat
        let collectionArtworkSize: CGFloat
        let collectionGridMinimum: CGFloat
    }

    struct ChromeTokens {
        let palette: ChromePalette
    }

    let id: AppThemeID
    let colors: Colors
    let typography: Typography
    let metrics: Metrics
    let chrome: ChromeTokens

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
            surface: .solid(Color(white: 0.09)),
            raisedSurface: .solid(Color(white: 0.16)),
            cardHover: .solid(Color(white: 0.13)),
            inputBackground: .solid(Color(white: 0.13)),
            rowHover: .solid(Color(white: 0.10)),
            rowSelected: .solid(Color(white: 0.12)),
            // The dark theme keeps the existing clear row background; the
            // current title/equalizer already provide the visual indication.
            rowCurrent: .solid(.clear),
            controlHover: .solid(Color(white: 0.14)),
            controlPressed: .solid(Color(white: 0.09)),
            subtleHover: .solid(Color(white: 0.10)),
            disabledSurface: .solid(Color(red: 0.114, green: 0.725, blue: 0.329).opacity(0.4)),
            placeholderBackground: .solid(Color(white: 0.14)),
            primaryText: .white,
            secondaryText: Color(white: 0.70),
            tertiaryText: Color(white: 0.42),
            disabledText: Color(white: 0.35),
            inverseText: .black,
            accent: Color(red: 0.114, green: 0.725, blue: 0.329),
            divider: Color(white: 0.18),
            border: Color(white: 0.20),
            focusRing: Color(red: 0.114, green: 0.725, blue: 0.329),
            sliderTrack: Color(white: 0.28),
            warning: .orange,
            warningContainer: .solid(Color.orange.opacity(0.10)),
            warningBorder: Color.orange.opacity(0.35),
            error: .red,
            // Text-only errors remain visually unchanged in Nanyin Dark;
            // Classic adds a restrained container treatment.
            errorContainer: .solid(.clear),
            errorBorder: .clear,
            shadow: .black
        ),
        typography: Typography(
            body: .system(size: 13),
            secondary: .system(size: 11),
            compact: .system(size: 10),
            sectionHeader: .system(size: 10, weight: .bold),
            pageTitle: .system(size: 28, weight: .bold),
            collectionHeader: .system(size: 24, weight: .bold),
            sectionTitle: .system(size: 15, weight: .bold),
            button: .system(size: 12, weight: .bold),
            controlLabel: .system(size: 13, weight: .semibold),
            fieldLabel: .system(size: 11, weight: .semibold),
            sheetTitle: .system(size: 16, weight: .bold),
            playerTitle: .system(size: 12, weight: .semibold),
            trackIndex: .system(size: 12, design: .monospaced),
            queueTitle: .system(size: 22, weight: .bold),
            queueRowTitle: .system(size: 12, weight: .medium),
            sectionLabel: .system(size: 14, weight: .bold),
            messageTitle: .system(size: 16, weight: .medium),
            tileTitle: .system(size: 12, weight: .medium),
            tileSubtitle: .system(size: 10),
            mono: .system(size: 10, design: .monospaced),
            duration: .system(size: 11, design: .monospaced),
            metadata: .system(size: 12),
            bannerText: .system(size: 12, weight: .medium),
            detailTitle: .system(size: 32, weight: .bold),
            bodyEmphasis: .system(size: 14, weight: .semibold),
            cardTitle: .system(size: 13, weight: .medium),
            nowPlayingTitle: .system(size: 13, weight: .semibold),
            collectionTitle: .system(size: 15, weight: .semibold)
        ),
        metrics: Metrics(
            standardRowHeight: 40,
            compactRowHeight: 24,
            controlHeight: 28,
            cornerRadius: 4,
            smallCornerRadius: 3,
            iconButtonCornerRadius: 5,
            imageCornerRadius: 6,
            cardCornerRadius: 8,
            pillCornerRadius: 20,
            heroPillCornerRadius: 24,
            smallPillCornerRadius: 16,
            compactPillCornerRadius: 14,
            pageHorizontalInset: 28,
            pageTopInset: 24,
            pageBottomInset: 20,
            headerBottomInset: 16,
            homeBottomInset: 28,
            sectionHorizontalInset: 24,
            sidebarInset: 16,
            cardPadding: 14,
            bannerHorizontalPadding: 14,
            bannerVerticalPadding: 10,
            fieldHorizontalPadding: 12,
            fieldVerticalPadding: 9,
            dividerVerticalPadding: 10,
            compactFieldHorizontalPadding: 10,
            compactFieldVerticalPadding: 6,
            sectionTopPadding: 16,
            sectionBottomPadding: 6,
            smallPadding: 8,
            trackRowVerticalPadding: 7,
            queueRowVerticalPadding: 5,
            likeButtonLeadingPadding: 4,
            controlHorizontalPadding: 22,
            controlVerticalPadding: 9,
            sidebarWidth: 230,
            playerBarHeight: 84,
            toolbarSpacerHeight: 54,
            queueRowHeight: 36,
            shadowRadius: 8,
            shadowYOffset: 4,
            bannerCornerRadius: 6,
            sheetPadding: 24,
            sheetWidth: 400,
            detailArtworkSize: 140,
            homeFeatureArtworkSize: 134,
            artistArtworkSize: 88,
            discographyArtworkSize: 112,
            collectionArtworkSize: 170,
            collectionGridMinimum: 170
        ),
        chrome: ChromeTokens(palette: .nanyinDark)
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
            surface: .linear([
                .init(color: Color(white: 0.15), location: 0),
                .init(color: Color(white: 0.11), location: 1),
            ]),
            raisedSurface: .linear([
                .init(color: Color(white: 0.24), location: 0),
                .init(color: Color(white: 0.18), location: 1),
            ]),
            cardHover: .linear([
                .init(color: Color(white: 0.18), location: 0),
                .init(color: Color(white: 0.14), location: 1),
            ]),
            inputBackground: .solid(Color(white: 0.10)),
            rowHover: .solid(Color(white: 0.22)),
            rowSelected: .linear([
                .init(color: Color(white: 0.27), location: 0),
                .init(color: Color(white: 0.20), location: 1),
            ]),
            rowCurrent: .solid(Color(red: 0.36, green: 0.53, blue: 0.22).opacity(0.22)),
            controlHover: .solid(Color(white: 0.24)),
            controlPressed: .solid(Color(white: 0.14)),
            subtleHover: .solid(Color(white: 0.18)),
                disabledSurface: .solid(Color(white: 0.14)),
            placeholderBackground: .solid(Color(white: 0.14)),
            primaryText: Color(white: 0.94),
            secondaryText: Color(white: 0.70),
            tertiaryText: Color(white: 0.58),
            disabledText: Color(white: 0.40),
            inverseText: Color(white: 0.08),
            accent: Color(red: 0.36, green: 0.53, blue: 0.22),
            divider: Color(white: 0.30),
            border: Color(white: 0.36),
            focusRing: Color(red: 0.52, green: 0.68, blue: 0.32),
            sliderTrack: Color(white: 0.34),
            warning: .orange,
            warningContainer: .solid(Color.orange.opacity(0.12)),
            warningBorder: Color.orange.opacity(0.42),
            error: .red,
            errorContainer: .solid(Color.red.opacity(0.12)),
            errorBorder: Color.red.opacity(0.42),
            shadow: .black
        ),
        typography: Typography(
            body: .system(size: 12),
            secondary: .system(size: 10),
            compact: .system(size: 9),
            sectionHeader: .system(size: 10, weight: .semibold),
            pageTitle: .system(size: 24, weight: .bold),
            collectionHeader: .system(size: 20, weight: .semibold),
            sectionTitle: .system(size: 14, weight: .semibold),
            button: .system(size: 12, weight: .semibold),
            controlLabel: .system(size: 12, weight: .semibold),
            fieldLabel: .system(size: 10, weight: .semibold),
            sheetTitle: .system(size: 15, weight: .semibold),
                playerTitle: .system(size: 11, weight: .semibold),
                trackIndex: .system(size: 10, design: .monospaced),
                queueTitle: .system(size: 20, weight: .semibold),
                queueRowTitle: .system(size: 11, weight: .medium),
                sectionLabel: .system(size: 13, weight: .semibold),
                messageTitle: .system(size: 14, weight: .medium),
                tileTitle: .system(size: 11, weight: .medium),
                tileSubtitle: .system(size: 9),
            mono: .system(size: 9, design: .monospaced),
            duration: .system(size: 10, design: .monospaced),
            metadata: .system(size: 11),
            bannerText: .system(size: 11, weight: .medium),
            detailTitle: .system(size: 26, weight: .semibold),
            bodyEmphasis: .system(size: 13, weight: .semibold),
            cardTitle: .system(size: 12, weight: .medium),
            nowPlayingTitle: .system(size: 12, weight: .semibold),
            collectionTitle: .system(size: 14, weight: .semibold)
        ),
        metrics: Metrics(
            standardRowHeight: 40,
            compactRowHeight: 22,
            controlHeight: 24,
            cornerRadius: 3,
            smallCornerRadius: 2,
            iconButtonCornerRadius: 3,
            imageCornerRadius: 3,
            cardCornerRadius: 4,
            pillCornerRadius: 12,
            heroPillCornerRadius: 14,
            smallPillCornerRadius: 10,
            compactPillCornerRadius: 9,
            pageHorizontalInset: 20,
            pageTopInset: 16,
            pageBottomInset: 14,
            headerBottomInset: 12,
            homeBottomInset: 20,
            sectionHorizontalInset: 16,
            sidebarInset: 12,
            cardPadding: 10,
            bannerHorizontalPadding: 10,
            bannerVerticalPadding: 8,
            fieldHorizontalPadding: 10,
            fieldVerticalPadding: 7,
            dividerVerticalPadding: 8,
            compactFieldHorizontalPadding: 8,
            compactFieldVerticalPadding: 5,
            sectionTopPadding: 12,
            sectionBottomPadding: 5,
            smallPadding: 6,
            trackRowVerticalPadding: 5,
            queueRowVerticalPadding: 4,
            likeButtonLeadingPadding: 3,
            controlHorizontalPadding: 18,
            controlVerticalPadding: 7,
            sidebarWidth: 210,
            playerBarHeight: 72,
            toolbarSpacerHeight: 42,
            queueRowHeight: 30,
            shadowRadius: 3,
            shadowYOffset: 1,
            bannerCornerRadius: 3,
            sheetPadding: 18,
            sheetWidth: 360,
            detailArtworkSize: 72,
            homeFeatureArtworkSize: 116,
            artistArtworkSize: 72,
            discographyArtworkSize: 88,
            collectionArtworkSize: 132,
            collectionGridMinimum: 132
        ),
        chrome: ChromeTokens(palette: .classic2010)
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

/// Adds a theme-owned pressed surface while retaining each control's local
/// hover and disabled rendering.
struct ThemePressFeedbackButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? theme.colors.controlPressed.swiftUIStyle
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: theme.metrics.cornerRadius)
            )
    }
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
