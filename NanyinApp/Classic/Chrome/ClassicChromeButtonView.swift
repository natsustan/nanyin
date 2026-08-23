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

    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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
        layer?.shadowPath = switch (style.surface, style.role) {
        case (.titlebarAccessory, .titlebarNavigation):
            CGPath(
                roundedRect: bounds,
                cornerWidth: 4,
                cornerHeight: 4,
                transform: nil
            )
        case (.titlebarAccessory, _):
            CGPath(ellipseIn: bounds, transform: nil)
        case (.content, _):
            nil
        }
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
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
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

        switch style.role {
        case .pill:
            layer.shape = ChouTiUI.Capsule(style: .circular)
        case .transport:
            layer.shape = ChouTiUI.Ellipse()
        case .titlebarNavigation:
            layer.shape = ChouTiUI.Rectangle(cornerRadius: 4)
        }

        switch style.surface {
        case .content:
            // ChouTiUI owns the Classic convex/concave surface recipes; the
            // palette controls the semantic interaction edges around them.
            layer.setBackgroundColor(state == .pressed ? .concaveGray : .convexGray)
            layer.borderColor = nsColor(
                state == .hovered ? style.palette.controlHoverBorder : style.palette.controlBorder
            ).cgColor
            layer.borderWidth = 1
            layer.shadowOpacity = 0
        case .titlebarAccessory:
            let colors: [NSColor]
            if state == .pressed {
                colors = [
                    NSColor(calibratedWhite: 0.76, alpha: 1),
                    NSColor(calibratedWhite: 0.84, alpha: 1),
                    NSColor(calibratedWhite: 0.91, alpha: 1),
                ]
            } else {
                colors = [
                    NSColor(calibratedWhite: 0.99, alpha: 1),
                    NSColor(calibratedWhite: 0.87, alpha: 1),
                    NSColor(calibratedWhite: 0.72, alpha: 1),
                ]
            }
            layer.setBackgroundColor(LinearGradientColor(colors, [0, 0.52, 1]))
            layer.borderColor = NSColor(
                calibratedWhite: 0.24,
                alpha: state == .hovered ? 0.58 : 0.44
            ).cgColor
            layer.borderWidth = 0.75
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 0.75
            layer.shadowOffset = CGSize(width: 0, height: -0.5)
        }
        alphaValue = isEnabled ? 1 : style.palette.disabledAlpha
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
