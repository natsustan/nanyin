//
//  ClassicChromeSectionBarView.swift
//  Nanyin
//

import AppKit
import ChouTiUI

final class ClassicChromeSectionBarView: NSView {
    var style = ChromeSectionBarStyle() {
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
        borderLayer.borderMask = .shape(shape, offset: -0.5)
        layer.setBackgroundColor(LinearGradientColor(style.palette.sectionBackground.map(nsColor)))
        borderLayer.borderContent = .color(nsColor(style.palette.controlBorder))
        borderLayer.borderWidth = 0.5
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
