//
//  ClassicChromeButtonView.swift
//  Nanyin
//

import AppKit
import ChouTiUI

final class ClassicChromeButtonView: NSView {
    var style = ChromeStyle() {
        didSet {
            invalidateIntrinsicContentSize()
            updateAppearance()
        }
    }

    var isEnabled = true {
        didSet {
            if !isEnabled {
                isPressed = false
            }
            setAccessibilityEnabled(isEnabled)
            updateAppearance()
        }
    }

    var action: () -> Void = {}

    private let backgroundLayer = CALayer()
    private let borderLayer = BorderLayer()
    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(borderLayer)
        focusRingType = .default
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityEnabled(true)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        style.size
    }

    override func layout() {
        super.layout()
        let backgroundInset: CGFloat = 0.5
        backgroundLayer.frame = bounds.insetBy(dx: backgroundInset, dy: backgroundInset)
        backgroundLayer.contentsScale = layer?.contentsScale ?? 2
        backgroundLayer.setNeedsLayout()
        borderLayer.frame = bounds
        borderLayer.setNeedsLayout()
        layer?.shadowPath = chromeShape.path(in: bounds.insetBy(dx: 0.5, dy: 0.5))
    }

    override var acceptsFirstResponder: Bool {
        isEnabled
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let shouldActivate = isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        updateAppearance()
        if shouldActivate {
            action()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, !event.isARepeat, event.keyCode == 36 || event.charactersIgnoringModifiers == " " else {
            super.keyDown(with: event)
            return
        }
        action()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        action()
        return true
    }

    override func drawFocusRingMask() {
        NSBezierPath(cgPath: chromeShape.path(in: bounds)).fill()
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    private func updateAppearance() {
        guard let layer else { return }

        let state: ChromeInteractionState
        if style.interactionState == .automatic {
            state = isPressed ? .pressed : (isHovered ? .hovered : .automatic)
        } else {
            state = style.interactionState
        }

        let shape = chromeShape
        // Keep the antialiased stroke inside the host shape mask. A centered
        // stroke loses its outer half and renders unevenly around ellipses.
        borderLayer.borderMask = .shape(shape, offset: -0.5)
        layer.shape = nil
        layer.setBackgroundColor(NSColor.clear)
        backgroundLayer.isHidden = false
        backgroundLayer.shape = shape
        if style.role == .titlebarNavigation, state == .pressed {
            backgroundLayer.setBackgroundColor(
                LinearGradientColor(
                    [
                        NSColor(calibratedWhite: 0.72, alpha: 1),
                        NSColor(calibratedWhite: 0.66, alpha: 1),
                    ],
                    nil,
                    .bottom,
                    .top
                )
            )
        } else if style.role == .titlebarNavigation {
            let hoverLift: CGFloat = state == .hovered ? 0.035 : 0
            backgroundLayer.setBackgroundColor(
                LinearGradientColor(
                    [
                        NSColor(calibratedWhite: 0.94 + hoverLift, alpha: 1),
                        NSColor(calibratedWhite: 0.86 + hoverLift, alpha: 1),
                        NSColor(calibratedWhite: 0.94 + hoverLift, alpha: 1),
                        NSColor(calibratedWhite: 0.88 + hoverLift, alpha: 1),
                    ],
                    [0, 0.50, 0.51, 1],
                    .bottom,
                    .top
                )
            )
        } else {
            backgroundLayer.setBackgroundColor(
                LinearGradientColor(
                    [
                        NSColor(calibratedWhite: 0.90, alpha: 1),
                        NSColor(calibratedWhite: 0.80, alpha: 1),
                        NSColor(calibratedWhite: 0.68, alpha: 1),
                    ],
                    [0, 0.48, 1],
                    .bottom,
                    .top
                )
            )
        }
        if style.role == .titlebarNavigation {
            borderLayer.borderContent = .color(NSColor.clear)
            borderLayer.borderWidth = 0
        } else {
            borderLayer.borderContent = .gradient(
                .linearGradient(
                    LinearGradientColor(
                        [
                            NSColor.white.withAlphaComponent(state == .hovered ? 0.74 : 0.58),
                            NSColor(calibratedWhite: 0.18, alpha: state == .hovered ? 0.68 : 0.52),
                        ],
                        nil,
                        .bottom,
                        .top
                    )
                )
            )
            borderLayer.borderWidth = 0.5
        }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = style.role == .titlebarNavigation ? 0 : 0.30
        layer.shadowRadius = 1
        layer.shadowOffset = CGSize(width: 0, height: -1)
        alphaValue = isEnabled || style.role == .titlebarNavigation ? 1 : style.palette.disabledAlpha
        needsDisplay = true
    }

    private var chromeShape: any ChouTiUI.Shape {
        switch style.role {
        case .pill:
            ChouTiUI.Capsule(style: .circular)
        case .transport:
            ChouTiUI.Ellipse()
        case .titlebarNavigation:
            switch style.segmentPosition {
            case .standalone:
                ChouTiUI.Rectangle(cornerRadius: 4)
            case .leading:
                ChouTiUI.Rectangle(cornerRadius: 4, roundingCorners: [.topLeft, .bottomLeft])
            case .trailing:
                ChouTiUI.Rectangle(cornerRadius: 4, roundingCorners: [.topRight, .bottomRight])
            }
        }
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
