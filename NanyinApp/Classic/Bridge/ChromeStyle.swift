//
//  ChromeStyle.swift
//  Nanyin
//

import Foundation

enum ChromeButtonRole: Equatable {
    case pill
    case transport
}

enum ChromeInteractionState: Equatable {
    case automatic
    case hovered
    case pressed
}

/// Plain Bridge↔Chrome configuration. It intentionally contains no ChouTiUI
/// type so the SwiftUI layer cannot depend on the drawing implementation.
struct ChromeStyle: Equatable {
    var role: ChromeButtonRole = .pill
    var size = CGSize(width: 88, height: 24)
    var interactionState: ChromeInteractionState = .automatic
}
