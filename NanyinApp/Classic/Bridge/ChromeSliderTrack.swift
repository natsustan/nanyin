//
//  ChromeSliderTrack.swift
//  Nanyin
//

import SwiftUI

struct ChromeSliderTrack: View {
    let style: ChromeSliderStyle
    var fillsAvailableWidth = false
    var onChanged: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void = { _ in }
    var onCancelled: () -> Void = {}
    @Environment(\.appTheme) private var theme

    private var resolvedStyle: ChromeSliderStyle {
        var resolved = style
        resolved.palette = theme.chrome.palette
        return resolved
    }

    @ViewBuilder
    var body: some View {
        if fillsAvailableWidth {
            GeometryReader { geometry in
                track(width: geometry.size.width)
            }
            .frame(height: resolvedStyle.size.height)
        } else {
            track(width: resolvedStyle.size.width)
        }
    }

    private func track(width: CGFloat) -> some View {
        var layoutStyle = resolvedStyle
        layoutStyle.size.width = width
        return ClassicChromeSliderTrackRepresentable(
            style: layoutStyle,
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled
        )
        .frame(width: width, height: layoutStyle.size.height)
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
