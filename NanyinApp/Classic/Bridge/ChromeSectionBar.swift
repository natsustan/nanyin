//
//  ChromeSectionBar.swift
//  Nanyin
//

import SwiftUI

struct ChromeSectionBar: View {
    var style = ChromeSectionBarStyle()
    @Environment(\.appTheme) private var theme

    private var resolvedStyle: ChromeSectionBarStyle {
        var resolved = style
        resolved.palette = theme.chrome.palette
        return resolved
    }

    var body: some View {
        ClassicChromeSectionBarRepresentable(style: resolvedStyle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

private struct ClassicChromeSectionBarRepresentable: NSViewRepresentable {
    let style: ChromeSectionBarStyle

    func makeNSView(context: Context) -> ClassicChromeSectionBarView {
        ClassicChromeSectionBarView()
    }

    func updateNSView(_ view: ClassicChromeSectionBarView, context: Context) {
        view.style = style
    }
}
