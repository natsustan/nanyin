//
//  ChromeButton.swift
//  Nanyin
//

import SwiftUI

struct ChromeButton: View {
    let title: String
    var accessibilityLabel: String? = nil
    var symbolName: String? = nil
    var assetName: String? = nil
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
                if let assetName {
                    Image(assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: symbolSize, height: symbolSize)
                } else if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: symbolSize, weight: .bold))
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.black.opacity(symbolOpacity))
            .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .fixedSize()
    }

    private var symbolSize: CGFloat {
        switch style.role {
        case .transport: assetName == nil ? 10 : 12
        case .titlebarNavigation: 10
        case .pill: 9
        }
    }

    private var symbolOpacity: Double {
        if isEnabled {
            0.78
        } else {
            style.role == .titlebarNavigation ? 0.35 : 0.52
        }
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
