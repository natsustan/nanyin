//
//  Theme.swift
//  Nanyin
//

import SwiftUI

/// Classic flat dark palette — early official desktop client era.
enum Theme {
    static let background = Color(red: 0.071, green: 0.071, blue: 0.071) // #121212
    static let sidebar = Color.black
    static let playerBar = Color(red: 0.094, green: 0.094, blue: 0.094) // #181818
    static let hover = Color(white: 0.10)
    static let accent = Color(red: 0.114, green: 0.725, blue: 0.329) // #1DB954
    static let textSecondary = Color(white: 0.70) // #B3B3B3

    static func fmtTime(_ ms: UInt32) -> String {
        let s = Int(ms) / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
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
