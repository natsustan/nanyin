//
//  ClassicChromeSliderTrackView.swift
//  Nanyin
//

import AppKit
import ChouTiUI

final class ClassicChromeSliderTrackView: NSView {
    var style = ChromeSliderStyle() {
        didSet {
            if !style.isEnabled, isDragging {
                isDragging = false
                onCancelled()
            }
            invalidateIntrinsicContentSize()
            updateAppearance()
        }
    }

    var onChanged: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void = { _ in }
    var onCancelled: () -> Void = {}

    private let borderLayer = BorderLayer()
    private let progressView = NSView()
    private let thumbView = NSView()
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Playback progress")

        layer?.addSublayer(borderLayer)
        progressView.wantsLayer = true
        progressView.isHidden = true
        addSubview(progressView)
        thumbView.wantsLayer = true
        addSubview(thumbView)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        style.size
    }

    override var acceptsFirstResponder: Bool {
        style.isEnabled
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        borderLayer.frame = bounds
        borderLayer.setNeedsLayout()
        let inset: CGFloat = 1
        let trackBounds = bounds.insetBy(dx: inset, dy: inset)
        let width = trackBounds.width * CGFloat(clampedFraction)
        progressView.frame = NSRect(
            x: trackBounds.minX,
            y: trackBounds.minY,
            width: max(width, width > 0 ? 3 : 0),
            height: trackBounds.height
        )
        let thumbDiameter = trackBounds.height
        let thumbRadius = thumbDiameter / 2
        let thumbCenterX = min(
            max(trackBounds.minX + width, trackBounds.minX + thumbRadius),
            trackBounds.maxX - thumbRadius
        )
        thumbView.frame = NSRect(
            x: thumbCenterX - thumbRadius,
            y: trackBounds.midY - thumbRadius,
            width: thumbDiameter,
            height: thumbDiameter
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard style.isEnabled else { return }
        isDragging = true
        window?.makeFirstResponder(self)
        onChanged(fraction(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, style.isEnabled else { return }
        onChanged(fraction(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let value = fraction(for: event)
        if style.isEnabled {
            onEnded(value)
        } else {
            onCancelled()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard style.isEnabled else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 123:
            onEnded(max(clampedFraction - 0.05, 0))
        case 124:
            onEnded(min(clampedFraction + 0.05, 1))
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard style.isEnabled else { return false }
        onEnded(min(clampedFraction + 0.05, 1))
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard style.isEnabled else { return false }
        onEnded(max(clampedFraction - 0.05, 0))
        return true
    }

    private var clampedFraction: Double {
        min(max(style.fraction, 0), 1)
    }

    private func fraction(for event: NSEvent) -> Double {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return 0 }
        return min(max(Double(point.x / bounds.width), 0), 1)
    }

    private func updateAppearance() {
        guard let layer,
              let progressLayer = progressView.layer,
              let thumbLayer = thumbView.layer else { return }
        let shape = ChouTiUI.Capsule(style: .circular)
        layer.shape = shape
        borderLayer.borderMask = .shape(shape, offset: -0.5)
        layer.setBackgroundColor(LinearGradientColor(style.palette.sliderBackground.map(nsColor)))
        borderLayer.borderContent = .color(nsColor(style.palette.sliderBorder))
        borderLayer.borderWidth = 0.5

        progressLayer.shape = ChouTiUI.Capsule(style: .circular)
        progressLayer.backgroundColor = nsColor(style.palette.sliderProgress).cgColor
        progressView.isHidden = clampedFraction <= 0
        thumbLayer.shape = ChouTiUI.Capsule(style: .circular)
        thumbLayer.backgroundColor = nsColor(style.palette.sliderThumb).cgColor
        alphaValue = style.isEnabled ? 1 : style.palette.disabledAlpha
        setAccessibilityEnabled(style.isEnabled)
        setAccessibilityValue(NSNumber(value: clampedFraction))
        setAccessibilityMinValue(NSNumber(value: 0))
        setAccessibilityMaxValue(NSNumber(value: 1))
        needsLayout = true
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
