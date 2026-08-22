//
//  ChromeButton.swift
//  Nanyin
//

import SwiftUI

struct ChromeButton: View {
    let title: String
    var style = ChromeStyle()
    var action: () -> Void = {}

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ClassicChromeButtonRepresentable(
            style: style,
            isEnabled: isEnabled,
            accessibilityLabel: title,
            action: action
        )
        .overlay {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(isEnabled ? 0.82 : 0.58))
                .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .fixedSize()
    }
}

private struct ClassicChromeButtonRepresentable: NSViewRepresentable {
    let style: ChromeStyle
    let isEnabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    func makeNSView(context: Context) -> ClassicChromeButtonView {
        ClassicChromeButtonView()
    }

    func updateNSView(_ view: ClassicChromeButtonView, context: Context) {
        view.style = style
        view.isEnabled = isEnabled
        view.action = action
        view.setAccessibilityLabel(accessibilityLabel)
    }
}
