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

    private let borderLayer = BorderLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(borderLayer)
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

    override func layout() {
        super.layout()
        borderLayer.frame = bounds
        borderLayer.setNeedsLayout()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let shape = ChouTiUI.Rectangle.rectangle
        layer.shape = shape
        borderLayer.borderMask = .shape(shape)
        layer.setBackgroundColor(
            LinearGradientColor(
                [
                    NSColor(calibratedWhite: 0.96, alpha: 1),
                    NSColor(calibratedWhite: 0.88, alpha: 1),
                    NSColor(calibratedWhite: 0.80, alpha: 1),
                ],
                [0, 0.58, 1]
            )
        )
        borderLayer.borderContent = .color(nsColor(style.palette.controlBorder))
        borderLayer.borderWidth = 1
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
