//
//  ClassicChromePreviewHarness.swift
//  Nanyin
//

import SwiftUI

/// Offline preview fixture for the Bridge↔Chrome contract. The List is kept
/// native SwiftUI and separate from chrome so feature rows never require an
/// AppKit wrapper or a Spotify session.
struct ClassicChromePreviewHarness: View {
    private let states: [(String, ChromeStyle)] = [
        ("Default", ChromeStyle()),
        ("Hovered", ChromeStyle(interactionState: .hovered)),
        ("Pressed", ChromeStyle(interactionState: .pressed)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(states, id: \.0) { title, style in
                    ChromeButton(title: title, style: style)
                }
                ChromeButton(title: "Disabled")
                    .disabled(true)
            }

            ChromeButton(title: "Outside List")

            List {
                Section("List independence") {
                    ForEach(0..<24, id: \.self) { index in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                            Text("Native SwiftUI row \(index + 1)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }
            .frame(height: 72)
        }
        .padding(20)
        .background(Color(white: 0.18))
    }
}

#Preview("Classic Chrome Offline Harness") {
    ClassicChromePreviewHarness()
}
