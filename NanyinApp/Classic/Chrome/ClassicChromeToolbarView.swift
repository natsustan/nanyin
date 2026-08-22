//
//  ClassicChromeToolbarView.swift
//  Nanyin
//

import AppKit
import ChouTiUI

final class ClassicChromeToolbarView: NSView {
    var style = ChromeToolbarStyle() {
        didSet {
            invalidateIntrinsicContentSize()
            updateAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: style.height)
    }

    private func updateAppearance() {
        guard let layer else { return }
        layer.shape = ChouTiUI.Rectangle.rectangle
        // silverChrome is the deliberate Classic graphite toolbar preset;
        // palette values keep the boundary/theme contract semantic.
        layer.setBackgroundColor(.silverChrome)
        layer.borderColor = nsColor(style.palette.controlBorder).cgColor
        layer.borderWidth = 1
        needsDisplay = true
    }

    private func nsColor(_ color: ChromeColor) -> NSColor {
        NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}
