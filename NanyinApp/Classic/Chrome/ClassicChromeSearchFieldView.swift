//
//  ClassicChromeSearchFieldView.swift
//  Nanyin
//

import AppKit
import ChouTiUI

final class ClassicChromeSearchFieldView: NSView, NSSearchFieldDelegate {
    var style = ChromeSearchStyle() {
        didSet {
            invalidateIntrinsicContentSize()
            updateAppearance()
            requestFocusIfNeeded()
        }
    }

    var onTextChange: (String) -> Void = { _ in }
    var onSubmit: (String) -> Void = { _ in }

    var text: String {
        get { searchField.stringValue }
        set {
            guard searchField.stringValue != newValue else { return }
            searchField.stringValue = newValue
        }
    }

    private let borderLayer = BorderLayer()
    private let searchField = NSSearchField()
    private let submitButton = ClassicSearchSubmitButton()
    private var lastFocusToken = 0
    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(submit)
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.controlSize = .small
        searchField.setAccessibilityLabel("Search Nanyin")
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        submitButton.target = self
        submitButton.action = #selector(submit)
        layer?.addSublayer(borderLayer)
        addSubview(searchField)
        addSubview(submitButton)
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
        true
    }

    override func layout() {
        super.layout()
        borderLayer.frame = bounds
        borderLayer.setNeedsLayout()
        if submitButton.isHidden {
            searchField.frame = NSRect(
                x: 24,
                y: 2,
                width: max(0, bounds.width - 32),
                height: bounds.height - 4
            )
        } else {
            let diameter = min(15, bounds.height - 4)
            submitButton.frame = NSRect(
                x: bounds.maxX - diameter - 2,
                y: (bounds.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            searchField.frame = NSRect(
                x: 24,
                y: 1,
                width: max(0, submitButton.frame.minX - 26),
                height: bounds.height - 2
            )
        }
        layer?.shadowPath = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard style.surface == .titlebarAccessory else {
            drawSearchGlyph()
            drawFocusIndicator()
            return
        }

        let controlBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(
            roundedRect: controlBounds,
            xRadius: controlBounds.height / 2,
            yRadius: controlBounds.height / 2
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowOffset = NSSize(width: 0, height: -0.75)
        shadow.shadowBlurRadius = 1.5
        shadow.set()
        NSGradient(
            colorsAndLocations:
                (NSColor(calibratedWhite: 0.84, alpha: 1), 0),
                (NSColor(calibratedWhite: 0.95, alpha: 1), 0.30),
                (NSColor(calibratedWhite: 0.99, alpha: 1), 1)
        )?.draw(in: path, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.16, alpha: 0.58).setStroke()
        path.lineWidth = 1
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            rect: NSRect(x: 0, y: bounds.midY, width: bounds.width, height: bounds.height / 2)
        ).addClip()
        NSColor.white.withAlphaComponent(0.72).setStroke()
        let highlight = NSBezierPath(
            roundedRect: controlBounds.insetBy(dx: 1, dy: 1),
            xRadius: max(0, controlBounds.height / 2 - 1),
            yRadius: max(0, controlBounds.height / 2 - 1)
        )
        highlight.lineWidth = 0.75
        highlight.stroke()
        NSGraphicsContext.restoreGraphicsState()

        drawSearchGlyph()
        drawFocusIndicator()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(searchField)
        super.mouseDown(with: event)
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange(searchField.stringValue)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        isEditing = true
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        isEditing = false
        needsDisplay = true
    }

    @objc private func submit() {
        onSubmit(searchField.stringValue)
    }

    private func requestFocusIfNeeded() {
        guard style.focusToken != 0, style.focusToken != lastFocusToken else { return }
        lastFocusToken = style.focusToken
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.searchField)
        }
    }

    private func updateAppearance() {
        guard let layer else { return }
        let shape = ChouTiUI.Capsule(style: .circular)
        layer.shape = shape
        borderLayer.borderMask = .shape(shape)
        switch style.surface {
        case .content:
            // The inset fill is the deliberate ChouTiUI preset selected by the
            // Classic chrome token; text and border values still come from AppTheme.
            layer.setBackgroundColor(.concaveGray)
            borderLayer.borderContent = .color(nsColor(style.palette.border))
            borderLayer.borderWidth = 1
            layer.shadowOpacity = 0
            searchField.appearance = nil
        case .titlebarAccessory:
            layer.setBackgroundColor(NSColor.clear)
            borderLayer.borderWidth = 0
            layer.shadowOpacity = 0
            searchField.appearance = NSAppearance(named: .aqua)
        }
        submitButton.isHidden = style.surface != .titlebarAccessory

        searchField.placeholderString = style.placeholder
        searchField.font = .systemFont(ofSize: 12)
        searchField.textColor = style.surface == .titlebarAccessory
            ? NSColor(calibratedWhite: 0.12, alpha: 0.88)
            : nsColor(style.palette.text)
        searchField.placeholderAttributedString = NSAttributedString(
            string: style.placeholder,
            attributes: [
                .foregroundColor: style.surface == .titlebarAccessory
                    ? NSColor(calibratedWhite: 0.24, alpha: 0.60)
                    : nsColor(style.palette.placeholder),
                .font: NSFont.systemFont(ofSize: 12),
            ]
        )
        needsLayout = true
        needsDisplay = true
    }

    private func drawSearchGlyph() {
        let color = style.surface == .titlebarAccessory
            ? NSColor(calibratedWhite: 0.30, alpha: 0.78)
            : nsColor(style.palette.placeholder)
        color.setStroke()

        let lens = NSBezierPath(ovalIn: NSRect(x: 7.5, y: bounds.midY - 2.5, width: 7, height: 7))
        lens.lineWidth = 1.5
        lens.stroke()

        let handle = NSBezierPath()
        handle.lineCapStyle = .round
        handle.lineWidth = 1.5
        handle.move(to: NSPoint(x: 13.5, y: bounds.midY - 1.5))
        handle.line(to: NSPoint(x: 17, y: bounds.midY - 5))
        handle.stroke()
    }

    private func drawFocusIndicator() {
        guard isEditing else { return }
        let focusBounds = bounds.insetBy(dx: 1.25, dy: 1.25)
        let focusPath = NSBezierPath(
            roundedRect: focusBounds,
            xRadius: focusBounds.height / 2,
            yRadius: focusBounds.height / 2
        )
        NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.86).setStroke()
        focusPath.lineWidth = 1.5
        focusPath.stroke()
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

private final class ClassicSearchSubmitButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        focusRingType = .none
        setAccessibilityLabel("Search")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
        shadow.shadowOffset = NSSize(width: 0, height: -0.75)
        shadow.shadowBlurRadius = 1
        shadow.set()
        NSColor(calibratedRed: 0.25, green: 0.65, blue: 0.12, alpha: 1).setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSGradient(
            colorsAndLocations:
                (NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.10, alpha: 1), 0),
                (NSColor(calibratedRed: 0.31, green: 0.72, blue: 0.16, alpha: 1), 0.58),
                (NSColor(calibratedRed: 0.48, green: 0.84, blue: 0.27, alpha: 1), 1)
        )?.draw(in: bounds, angle: 90)
        if isHighlighted {
            NSColor.black.withAlphaComponent(0.20).setFill()
            circle.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.05, alpha: 0.82).setStroke()
        circle.lineWidth = 0.8
        circle.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: bounds.midX - 2, y: bounds.midY - 3.5))
        arrow.line(to: NSPoint(x: bounds.midX + 3.5, y: bounds.midY))
        arrow.line(to: NSPoint(x: bounds.midX - 2, y: bounds.midY + 3.5))
        arrow.close()
        NSColor.white.withAlphaComponent(0.94).setFill()
        arrow.fill()
    }
}
