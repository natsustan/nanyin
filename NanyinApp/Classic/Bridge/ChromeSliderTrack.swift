//
//  ChromeSliderTrack.swift
//  Nanyin
//

import SwiftUI

struct ChromeSliderTrack: View {
    let style: ChromeSliderStyle
    var onChanged: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void = { _ in }
    var onCancelled: () -> Void = {}
    @Environment(\.appTheme) private var theme

    private var resolvedStyle: ChromeSliderStyle {
        var resolved = style
        resolved.palette = theme.chrome.palette
        return resolved
    }

    var body: some View {
        ClassicChromeSliderTrackRepresentable(
            style: resolvedStyle,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
        .frame(width: resolvedStyle.size.width, height: resolvedStyle.size.height)
    }
}

private struct ClassicChromeSliderTrackRepresentable: NSViewRepresentable {
    let style: ChromeSliderStyle
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    let onCancelled: () -> Void

    func makeNSView(context: Context) -> ClassicChromeSliderTrackView {
        ClassicChromeSliderTrackView()
    }

    func updateNSView(_ view: ClassicChromeSliderTrackView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onCancelled = onCancelled
        view.style = style
    }
}
