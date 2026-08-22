//
//  ChromeButton.swift
//  Nanyin
//

import SwiftUI

struct ChromeButton: View {
    let title: String
    var configuration = ClassicChromeButtonConfiguration()
    var action: () -> Void = {}

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ClassicChromeButtonRepresentable(
            configuration: configuration,
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
        }
        .frame(width: configuration.size.width, height: configuration.size.height)
    }
}

private struct ClassicChromeButtonRepresentable: NSViewRepresentable {
    let configuration: ClassicChromeButtonConfiguration
    let isEnabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    func makeNSView(context: Context) -> ClassicChromeButtonView {
        ClassicChromeButtonView()
    }

    func updateNSView(_ view: ClassicChromeButtonView, context: Context) {
        view.configuration = configuration
        view.isEnabled = isEnabled
        view.action = action
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

#Preview("Classic Chrome Button States") {
    HStack(spacing: 14) {
        ChromeButton(title: "Default")
        ChromeButton(
            title: "Hovered",
            configuration: ClassicChromeButtonConfiguration(interactionState: .hovered)
        )
        ChromeButton(
            title: "Pressed",
            configuration: ClassicChromeButtonConfiguration(interactionState: .pressed)
        )
        ChromeButton(title: "Disabled")
            .disabled(true)
    }
    .padding(20)
    .background(Color(white: 0.18))
}
