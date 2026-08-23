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
        let backgroundInset: CGFloat = style.surface == .content ? 0.5 : 0
        backgroundLayer.frame = bounds.insetBy(dx: backgroundInset, dy: backgroundInset)
        backgroundLayer.contentsScale = layer?.contentsScale ?? 2
        backgroundLayer.setNeedsLayout()
        borderLayer.frame = bounds
        borderLayer.setNeedsLayout()
        layer?.shadowPath = style.surface == .titlebarAccessory
            ? chromeShape.path(in: bounds)
            : nil
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

        switch style.surface {
        case .content:
            layer.shape = nil
            layer.setBackgroundColor(NSColor.clear)
            backgroundLayer.isHidden = false
            backgroundLayer.shape = shape
            let colors = state == .pressed
                ? style.palette.controlPressedBackground
                : style.palette.controlBackground
            backgroundLayer.setBackgroundColor(LinearGradientColor(colors.map(nsColor)))
            borderLayer.borderContent = .color(
                nsColor(state == .hovered ? style.palette.controlHoverBorder : style.palette.controlBorder)
            )
            borderLayer.borderWidth = 0.5
            layer.shadowOpacity = 0
        case .titlebarAccessory:
            backgroundLayer.isHidden = true
            backgroundLayer.shape = nil
            layer.shape = shape
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
            borderLayer.borderContent = .color(
                NSColor(
                    calibratedWhite: 0.24,
                    alpha: state == .hovered ? 0.74 : 0.58
                )
            )
            borderLayer.borderWidth = 0.5
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowRadius = 0.75
            layer.shadowOffset = CGSize(width: 0, height: -0.5)
        }
        alphaValue = isEnabled
            ? 1
            : (style.surface == .titlebarAccessory ? 0.78 : style.palette.disabledAlpha)
        needsDisplay = true
    }

    private var chromeShape: any ChouTiUI.Shape {
        switch style.role {
        case .pill:
            ChouTiUI.Capsule(style: .circular)
        case .transport:
            ChouTiUI.Ellipse()
        case .titlebarNavigation:
            ChouTiUI.Rectangle(cornerRadius: 5.75)
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
