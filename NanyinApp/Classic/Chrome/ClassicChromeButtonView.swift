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
        }
        layer.setBackgroundColor(state == .pressed ? .concaveGray : .convexGray)
        layer.borderColor = NSColor(white: state == .hovered ? 0.58 : 0.38, alpha: 1).cgColor
        layer.borderWidth = 1
        alphaValue = isEnabled ? 1 : 0.45
        needsDisplay = true
    }
}
