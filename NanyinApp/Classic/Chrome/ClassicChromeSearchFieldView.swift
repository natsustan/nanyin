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

    private let searchField = NSSearchField()
    private var lastFocusToken = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(submit)
        searchField.focusRingType = .default
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.controlSize = .small
        searchField.setAccessibilityLabel("Search Nanyin")
        addSubview(searchField)
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
        searchField.frame = bounds.insetBy(dx: 9, dy: 2)
        layer?.shadowPath = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard style.surface == .titlebarAccessory else { return }

        let controlBounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(
            roundedRect: controlBounds,
            xRadius: controlBounds.height / 2,
            yRadius: controlBounds.height / 2
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1
        shadow.set()
        NSGradient(
            starting: NSColor(calibratedWhite: 0.80, alpha: 1),
            ending: NSColor(calibratedWhite: 0.99, alpha: 1)
        )?.draw(in: path, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.20, alpha: 0.34).setStroke()
        path.lineWidth = 1
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(
            rect: NSRect(x: 0, y: bounds.midY, width: bounds.width, height: bounds.height / 2)
        ).addClip()
        NSColor.white.withAlphaComponent(0.62).setStroke()
        let highlight = NSBezierPath(
            roundedRect: controlBounds.insetBy(dx: 1, dy: 1),
            xRadius: max(0, controlBounds.height / 2 - 1),
            yRadius: max(0, controlBounds.height / 2 - 1)
        )
        highlight.lineWidth = 0.75
        highlight.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(searchField)
        super.mouseDown(with: event)
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange(searchField.stringValue)
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
        layer.shape = ChouTiUI.Capsule(style: .circular)
        switch style.surface {
        case .content:
            // The inset fill is the deliberate ChouTiUI preset selected by the
            // Classic chrome token; text and border values still come from AppTheme.
            layer.setBackgroundColor(.concaveGray)
            layer.borderColor = nsColor(style.palette.border).cgColor
            layer.borderWidth = 1
            layer.shadowOpacity = 0
            searchField.appearance = nil
        case .titlebarAccessory:
            layer.setBackgroundColor(NSColor.clear)
            layer.borderWidth = 0
            layer.shadowOpacity = 0
            searchField.appearance = NSAppearance(named: .aqua)
        }

        searchField.placeholderString = style.placeholder
        searchField.font = .systemFont(ofSize: style.surface == .titlebarAccessory ? 11 : 12)
        searchField.textColor = style.surface == .titlebarAccessory
            ? NSColor(calibratedWhite: 0.12, alpha: 0.88)
            : nsColor(style.palette.text)
        searchField.placeholderAttributedString = NSAttributedString(
            string: style.placeholder,
            attributes: [
                .foregroundColor: style.surface == .titlebarAccessory
                    ? NSColor(calibratedWhite: 0.24, alpha: 0.60)
                    : nsColor(style.palette.placeholder),
                .font: NSFont.systemFont(ofSize: style.surface == .titlebarAccessory ? 11 : 12),
            ]
        )
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
