//
//  ChromeButton.swift
//  Nanyin
//

import SwiftUI

struct ChromeButton: View {
    let title: String
    var accessibilityLabel: String? = nil
    var symbolName: String? = nil
    var style = ChromeStyle()
    var action: () -> Void = {}

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appTheme) private var theme

    private var resolvedStyle: ChromeStyle {
        var resolved = style
        resolved.palette = theme.chrome.palette
        return resolved
    }

    var body: some View {
        ClassicChromeButtonRepresentable(
            style: resolvedStyle,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel ?? title,
            action: action
        )
        .overlay {
            Group {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 7, weight: .bold))
                } else {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(.black.opacity(isEnabled ? 0.76 : 0.52))
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
