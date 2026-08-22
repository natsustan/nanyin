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
        // The inset fill is the deliberate ChouTiUI preset selected by the
        // Classic chrome token; text and border values still come from AppTheme.
        layer.setBackgroundColor(.concaveGray)
        layer.borderColor = nsColor(style.palette.border).cgColor
        layer.borderWidth = 1

        searchField.placeholderString = style.placeholder
        searchField.font = .systemFont(ofSize: 12)
        searchField.textColor = nsColor(style.palette.text)
        searchField.placeholderAttributedString = NSAttributedString(
            string: style.placeholder,
            attributes: [
                .foregroundColor: nsColor(style.palette.placeholder),
                .font: NSFont.systemFont(ofSize: 12),
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
