//
//  ChromeToolbar.swift
//  Nanyin
//

import SwiftUI

struct ChromeToolbar: View {
    var style = ChromeToolbarStyle()
    @Environment(\.appTheme) private var theme

    private var resolvedStyle: ChromeToolbarStyle {
        var resolved = style
        resolved.palette = theme.chrome.palette
        return resolved
    }

    var body: some View {
        ClassicChromeToolbarRepresentable(style: resolvedStyle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

private struct ClassicChromeToolbarRepresentable: NSViewRepresentable {
    let style: ChromeToolbarStyle

    func makeNSView(context: Context) -> ClassicChromeToolbarView {
        ClassicChromeToolbarView()
    }

    func updateNSView(_ view: ClassicChromeToolbarView, context: Context) {
        view.style = style
    }
}
