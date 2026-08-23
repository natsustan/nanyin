//
//  ChromeStyle.swift
//  Nanyin
//

import Foundation

struct ChromeColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}

struct ChromePalette: Equatable {
    let border: ChromeColor
    let text: ChromeColor
    let placeholder: ChromeColor
    let controlBorder: ChromeColor
    let controlHoverBorder: ChromeColor
    let sliderBorder: ChromeColor
    let sliderProgress: ChromeColor
    let disabledAlpha: CGFloat

    static let nanyinDark = Self(
        border: ChromeColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
        text: ChromeColor(red: 1, green: 1, blue: 1, alpha: 0.92),
        placeholder: ChromeColor(red: 1, green: 1, blue: 1, alpha: 0.58),
        controlBorder: ChromeColor(red: 1, green: 1, blue: 1, alpha: 0.38),
        controlHoverBorder: ChromeColor(red: 1, green: 1, blue: 1, alpha: 0.58),
        sliderBorder: ChromeColor(red: 1, green: 1, blue: 1, alpha: 0.38),
        sliderProgress: ChromeColor(red: 0.72, green: 0.72, blue: 0.72, alpha: 1),
        disabledAlpha: 0.45
    )

    static let classic2010 = Self(
        border: ChromeColor(red: 0.28, green: 0.28, blue: 0.28, alpha: 0.72),
        text: ChromeColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.92),
        placeholder: ChromeColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.58),
        controlBorder: ChromeColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 0.55),
        controlHoverBorder: ChromeColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 0.80),
        sliderBorder: ChromeColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 0.70),
        sliderProgress: ChromeColor(red: 0.70, green: 0.76, blue: 0.58, alpha: 1),
        disabledAlpha: 0.45
    )
}

enum ChromeButtonRole: Equatable {
    case pill
    case transport
    case titlebarNavigation
}

enum ChromeInteractionState: Equatable {
    case automatic
    case hovered
    case pressed
}

enum ChromeSurface: Equatable {
    case content
    case titlebarAccessory
}

/// Plain Bridge↔Chrome configuration. It intentionally contains no ChouTiUI
/// type so the SwiftUI layer cannot depend on the drawing implementation.
struct ChromeStyle: Equatable {
    var role: ChromeButtonRole = .pill
    var size = CGSize(width: 88, height: 24)
    var interactionState: ChromeInteractionState = .automatic
    var surface = ChromeSurface.content
    var palette = ChromePalette.classic2010
}

struct ChromeSearchStyle: Equatable {
    var size = CGSize(width: 280, height: 26)
    var placeholder = "Search Nanyin"
    var focusToken = 0
    var surface = ChromeSurface.content
    var palette = ChromePalette.classic2010
}

struct ChromeSliderStyle: Equatable {
    var size = CGSize(width: 220, height: 12)
    var fraction = 0.0
    var isEnabled = true
    var palette = ChromePalette.classic2010
}

struct ChromeToolbarStyle: Equatable {
    var height: CGFloat = 38
    var palette = ChromePalette.classic2010
}

struct ChromeSectionBarStyle: Equatable {
    var height: CGFloat = 72
    var palette = ChromePalette.classic2010
}
