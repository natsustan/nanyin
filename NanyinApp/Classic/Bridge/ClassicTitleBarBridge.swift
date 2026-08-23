//
//  ClassicTitleBarBridge.swift
//  Nanyin
//

import AppKit
import SwiftUI

/// Installs Classic chrome at the window boundary.
struct ClassicTitleBarBridge: NSViewRepresentable {
    let isClassic: Bool
    let app: AppModel
    let theme: AppTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: WindowAttachmentView, context: Context) {
        context.coordinator.update(isClassic: isClassic, app: app, theme: theme)
        context.coordinator.attach(to: view.window)
    }

    static func dismantleNSView(_ view: WindowAttachmentView, coordinator: Coordinator) {
        coordinator.restoreWindow()
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var originalConfiguration: WindowConfiguration?
        private var titleBarView: ClassicAquaTitleBarView?
        private var accessoryViewController: NSTitlebarAccessoryViewController?
        private var isClassic = false
        private var app: AppModel?
        private var theme: AppTheme?

        func update(isClassic: Bool, app: AppModel, theme: AppTheme) {
            self.isClassic = isClassic
            self.app = app
            self.theme = theme
            applyCurrentMode()
        }

        func attach(to newWindow: NSWindow?) {
            guard window !== newWindow else { return }
            restoreWindow()
            window = newWindow
            applyCurrentMode()
        }

        func restoreWindow() {
            if let accessoryViewController,
               let index = window?.titlebarAccessoryViewControllers.firstIndex(where: {
                   $0 === accessoryViewController
               }) {
                window?.removeTitlebarAccessoryViewController(at: index)
            }
            accessoryViewController = nil
            titleBarView?.removeFromSuperview()
            titleBarView = nil

            guard let window, let originalConfiguration else {
                self.window = nil
                return
            }

            window.styleMask = originalConfiguration.styleMask
            window.titleVisibility = originalConfiguration.titleVisibility
            window.titlebarAppearsTransparent = originalConfiguration.titlebarAppearsTransparent
            window.toolbar?.isVisible = originalConfiguration.isToolbarVisible
            setStandardButtons(hidden: false, in: window)
            self.originalConfiguration = nil
            self.window = nil
        }

        private func applyCurrentMode() {
            guard let window else { return }
            guard isClassic else {
                if originalConfiguration != nil {
                    restoreWindow()
                }
                return
            }
            guard titleBarView == nil, let app, let theme else { return }

            originalConfiguration = WindowConfiguration(window: window)
            window.styleMask.formUnion([
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ])
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar?.isVisible = false
            setStandardButtons(hidden: true, in: window)

            guard let container = titleBarContainer(in: window) else { return }
            let titleBarView = ClassicAquaTitleBarView()
            titleBarView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(titleBarView, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                titleBarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                titleBarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                titleBarView.topAnchor.constraint(equalTo: container.topAnchor),
                titleBarView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            self.titleBarView = titleBarView

            let controls = ClassicTitleBarControls()
                .environment(app)
                .environment(\.appTheme, theme)
            let hostingView = NSHostingView(rootView: AnyView(controls))
            hostingView.frame = NSRect(x: 0, y: 0, width: window.frame.width, height: 24)
            hostingView.autoresizingMask = [.width]

            let accessoryViewController = NSTitlebarAccessoryViewController()
            accessoryViewController.layoutAttribute = .bottom
            accessoryViewController.view = hostingView
            window.addTitlebarAccessoryViewController(accessoryViewController)
            self.accessoryViewController = accessoryViewController
        }

        private func setStandardButtons(hidden: Bool, in window: NSWindow) {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = hidden
            }
        }

        private func titleBarContainer(in window: NSWindow) -> NSView? {
            if let closeButton = window.standardWindowButton(.closeButton) {
                var candidate = closeButton.superview
                while let view = candidate {
                    if String(describing: type(of: view)).contains("NSTitlebarContainerView") {
                        return view
                    }
                    candidate = view.superview
                }
            }

            return window.contentView?.superview?.firstDescendant {
                String(describing: type(of: $0)).contains("NSTitlebarContainerView")
            }
        }
    }
}

private struct WindowConfiguration {
    let styleMask: NSWindow.StyleMask
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarAppearsTransparent: Bool
    let isToolbarVisible: Bool

    init(window: NSWindow) {
        styleMask = window.styleMask
        titleVisibility = window.titleVisibility
        titlebarAppearsTransparent = window.titlebarAppearsTransparent
        isToolbarVisible = window.toolbar?.isVisible ?? false
    }
}

final class WindowAttachmentView: NSView {
    var windowDidChange: (NSWindow?) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange(window)
    }
}

private final class ClassicAquaTitleBarView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let close = ClassicWindowButton(kind: .close)
        let minimize = ClassicWindowButton(kind: .minimize)
        let zoom = ClassicWindowButton(kind: .zoom)
        for button in [close, minimize, zoom] {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            minimize.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 8),
            minimize.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            zoom.leadingAnchor.constraint(equalTo: minimize.trailingAnchor, constant: 8),
            zoom.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(
            starting: NSColor(calibratedHue: 0.5694, saturation: 0.02, brightness: 0.84, alpha: 1),
            ending: NSColor(calibratedHue: 0.5694, saturation: 0.02, brightness: 0.945, alpha: 1)
        )?.draw(in: bounds, angle: 90)
        NSColor(calibratedWhite: 0.50, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class ClassicWindowButton: NSButton {
    enum Kind {
        case close
        case minimize
        case zoom

        var color: NSColor {
            switch self {
            case .close: NSColor(calibratedRed: 1.00, green: 0.40, blue: 0.37, alpha: 1)
            case .minimize: NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.20, alpha: 1)
            case .zoom: NSColor(calibratedWhite: 0.90, alpha: 1)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .close: "Close"
            case .minimize: "Minimize"
            case .zoom: "Zoom"
            }
        }
    }

    private let kind: Kind
    private var hovering = false
    private var observers: [NSObjectProtocol] = []

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        isBordered = false
        title = ""
        target = self
        action = #selector(performWindowAction)
        setAccessibilityLabel(kind.accessibilityLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 12),
            heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.needsDisplay = true
                }
            )
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = window?.isKeyWindow == true
        let oval = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSGraphicsContext.saveGraphicsState()
        oval.addClip()
        let base = active ? kind.color : NSColor(calibratedWhite: 0.72, alpha: 1)
        NSGradient(
            colorsAndLocations:
                (base.blended(withFraction: 0.42, of: .white) ?? base, 0),
                (base, 0.50),
                (base.blended(withFraction: 0.62, of: .white) ?? base, 1)
        )?.draw(in: bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.22, alpha: active ? 0.62 : 0.34).setStroke()
        oval.lineWidth = 0.8
        oval.stroke()

        if isHighlighted {
            NSColor.black.withAlphaComponent(0.22).setFill()
            oval.fill()
        }

        guard hovering, active else { return }
        NSColor(calibratedWhite: 0.15, alpha: 0.72).setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 1
        switch kind {
        case .close:
            mark.move(to: NSPoint(x: 4, y: 4))
            mark.line(to: NSPoint(x: 8, y: 8))
            mark.move(to: NSPoint(x: 8, y: 4))
            mark.line(to: NSPoint(x: 4, y: 8))
        case .minimize:
            mark.move(to: NSPoint(x: 3.5, y: 6))
            mark.line(to: NSPoint(x: 8.5, y: 6))
        case .zoom:
            mark.move(to: NSPoint(x: 4, y: 8))
            mark.line(to: NSPoint(x: 8, y: 4))
        }
        mark.stroke()
    }

    @objc private func performWindowAction() {
        guard let window else { return }
        switch kind {
        case .close: window.performClose(self)
        case .minimize: window.miniaturize(self)
        case .zoom: window.zoom(self)
        }
    }
}

private extension NSView {
    func firstDescendant(where predicate: (NSView) -> Bool) -> NSView? {
        for subview in subviews {
            if predicate(subview) {
                return subview
            }
            if let match = subview.firstDescendant(where: predicate) {
                return match
            }
        }
        return nil
    }
}
