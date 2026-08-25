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
            guard let container = titleBarContainer(in: window) else { return }

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
    private let titleField = NSTextField(labelWithString: "NanYin")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let close = ClassicWindowButton(kind: .close)
        let minimize = ClassicWindowButton(kind: .minimize)
        let zoom = ClassicWindowButton(kind: .zoom)
        for button in [close, minimize, zoom] {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont(name: "Lucida Grande", size: 12)
            ?? .systemFont(ofSize: 12, weight: .regular)
        titleField.textColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        titleField.alignment = .center
        titleField.lineBreakMode = .byClipping
        addSubview(titleField)

        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            minimize.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 2),
            minimize.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            zoom.leadingAnchor.constraint(equalTo: minimize.trailingAnchor, constant: 2),
            zoom.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === titleField ? self : hitView
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(
            colorsAndLocations:
                (NSColor(calibratedWhite: 0.46, alpha: 1), 0),
                (NSColor(calibratedWhite: 0.53, alpha: 1), 0.08),
                (NSColor(calibratedWhite: 0.56, alpha: 1), 0.22),
                (NSColor(calibratedWhite: 0.61, alpha: 1), 0.58),
                (NSColor(calibratedWhite: 0.66, alpha: 1), 0.85),
                (NSColor(calibratedWhite: 0.70, alpha: 1), 1)
        )?.draw(in: bounds, angle: 90)

        NSColor.white.withAlphaComponent(0.24).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSRect(x: 0, y: 1, width: bounds.width, height: 1).fill()
        NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Visual recipe for one Aqua gel button, ported from ryOS
/// (TrafficLightButton.tsx): vertical two-stop gradient, layered outer drop
/// shadows, a hairline rim, colored inner shadow + glow, then a top shine
/// capsule and bottom white glow clipped to the circle.
private struct AquaButtonStyle {
    struct OuterShadow {
        let color: NSColor
        let offset: NSSize
        let blur: CGFloat
    }

    struct InnerShadow {
        let color: NSColor
        let offset: NSSize
        let blur: CGFloat
        let spread: CGFloat
    }

    let top: NSColor
    let bottom: NSColor
    let outerShadows: [OuterShadow]
    let innerShadows: [InnerShadow]
    let icon: NSColor?

    static func colored(
        top: NSColor,
        bottom: NSColor,
        halo: NSColor,
        innerShadow: NSColor,
        innerGlow: NSColor,
        icon: NSColor
    ) -> AquaButtonStyle {
        AquaButtonStyle(
            top: top,
            bottom: bottom,
            outerShadows: [
                OuterShadow(
                    color: .black.withAlphaComponent(0.5),
                    offset: NSSize(width: 0, height: -2),
                    blur: 3.5
                ),
                OuterShadow(
                    color: .black.withAlphaComponent(0.4),
                    offset: NSSize(width: 0, height: -1),
                    blur: 2
                ),
                OuterShadow(color: halo, offset: NSSize(width: 0, height: -1), blur: 1),
            ],
            innerShadows: [
                InnerShadow(
                    color: .black.withAlphaComponent(0.3),
                    offset: .zero,
                    blur: 0,
                    spread: 0.5
                ),
                InnerShadow(
                    color: innerShadow,
                    offset: NSSize(width: 0, height: -1),
                    blur: 3,
                    spread: 0
                ),
                InnerShadow(
                    color: innerGlow,
                    offset: NSSize(width: 0, height: -2),
                    blur: 4.5,
                    spread: 1
                ),
                // Extra soft pass lifts the mid-body like the browser's
                // wider inset-glow falloff.
                InnerShadow(
                    color: innerGlow.withAlphaComponent(innerGlow.alphaComponent * 0.5),
                    offset: NSSize(width: 0, height: -3),
                    blur: 5,
                    spread: 1
                ),
            ],
            icon: icon
        )
    }

    // ryOS inactive gradient is semi-transparent gray→white; pre-blended here
    // against the title bar's mid gray so shadow passes can fill opaquely.
    static let inactive = AquaButtonStyle(
        top: NSColor(calibratedWhite: 0.62, alpha: 1),
        bottom: NSColor(calibratedWhite: 0.85, alpha: 1),
        outerShadows: [
            OuterShadow(
                color: .black.withAlphaComponent(0.2),
                offset: NSSize(width: 0, height: -2),
                blur: 3
            ),
            OuterShadow(
                color: .black.withAlphaComponent(0.3),
                offset: NSSize(width: 0, height: -1),
                blur: 1
            ),
        ],
        innerShadows: [
            InnerShadow(
                color: .black.withAlphaComponent(0.3),
                offset: .zero,
                blur: 0,
                spread: 0.5
            ),
            InnerShadow(
                color: .black.withAlphaComponent(0.4),
                offset: NSSize(width: 0, height: -1),
                blur: 2,
                spread: 0
            ),
            InnerShadow(
                color: NSColor(calibratedWhite: 0.73, alpha: 1),
                offset: NSSize(width: 0, height: -2),
                blur: 3,
                spread: 1
            ),
        ],
        icon: nil
    )
}

private final class ClassicWindowButton: NSButton {
    enum Kind {
        case close
        case minimize
        case zoom

        var style: AquaButtonStyle {
            switch self {
            case .close:
                .colored(
                    top: NSColor(srgbRed: 193 / 255, green: 58 / 255, blue: 45 / 255, alpha: 1),
                    bottom: NSColor(srgbRed: 205 / 255, green: 73 / 255, blue: 52 / 255, alpha: 1),
                    halo: NSColor(srgbRed: 225 / 255, green: 70 / 255, blue: 64 / 255, alpha: 0.5),
                    innerShadow: NSColor(
                        srgbRed: 150 / 255, green: 40 / 255, blue: 30 / 255, alpha: 0.8
                    ),
                    innerGlow: NSColor(
                        srgbRed: 225 / 255, green: 70 / 255, blue: 64 / 255, alpha: 0.75
                    ),
                    icon: NSColor(srgbRed: 130 / 255, green: 30 / 255, blue: 20 / 255, alpha: 0.9)
                )
            case .minimize:
                .colored(
                    top: NSColor(srgbRed: 202 / 255, green: 130 / 255, blue: 13 / 255, alpha: 1),
                    bottom: NSColor(
                        srgbRed: 253 / 255, green: 253 / 255, blue: 149 / 255, alpha: 1
                    ),
                    halo: NSColor(
                        srgbRed: 223 / 255, green: 161 / 255, blue: 35 / 255, alpha: 0.5
                    ),
                    innerShadow: NSColor(
                        srgbRed: 155 / 255, green: 78 / 255, blue: 21 / 255, alpha: 1
                    ),
                    innerGlow: NSColor(
                        srgbRed: 241 / 255, green: 157 / 255, blue: 20 / 255, alpha: 1
                    ),
                    icon: NSColor(srgbRed: 130 / 255, green: 80 / 255, blue: 8 / 255, alpha: 0.9)
                )
            case .zoom:
                .colored(
                    top: NSColor(srgbRed: 111 / 255, green: 174 / 255, blue: 58 / 255, alpha: 1),
                    bottom: NSColor(srgbRed: 138 / 255, green: 192 / 255, blue: 50 / 255, alpha: 1),
                    halo: NSColor(srgbRed: 59 / 255, green: 173 / 255, blue: 29 / 255, alpha: 0.5),
                    innerShadow: NSColor(
                        srgbRed: 53 / 255, green: 91 / 255, blue: 17 / 255, alpha: 1
                    ),
                    innerGlow: NSColor(
                        srgbRed: 98 / 255, green: 187 / 255, blue: 19 / 255, alpha: 1
                    ),
                    icon: NSColor(srgbRed: 45 / 255, green: 90 / 255, blue: 18 / 255, alpha: 0.9)
                )
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

    // NSControl defaults to flipped coordinates; the Aqua layer math below is
    // written y-up (shine at maxY, drop shadows toward minY).
    override var isFlipped: Bool { false }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 19, height: 19))
        isBordered = false
        title = ""
        target = self
        action = #selector(performWindowAction)
        setAccessibilityLabel(kind.accessibilityLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 19),
            heightAnchor.constraint(equalToConstant: 19),
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
        let circle = bounds.insetBy(dx: 3, dy: 3)
        let oval = NSBezierPath(ovalIn: circle)
        let style = active ? kind.style : AquaButtonStyle.inactive

        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        if !active {
            cgContext.saveGState()
            cgContext.setAlpha(0.7)
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        // Outer drop shadows (two dark passes plus a colored halo when active).
        for outer in style.outerShadows {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = outer.color
            shadow.shadowOffset = outer.offset
            shadow.shadowBlurRadius = outer.blur
            shadow.set()
            style.top.setFill()
            oval.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        oval.addClip()

        // Base gel: dark top color into lighter bottom color.
        NSGradient(colorsAndLocations: (style.bottom, 0), (style.top, 1))?
            .draw(in: circle, angle: 90)

        // Hairline rim, colored inner shadow, and colored inner glow.
        for inner in style.innerShadows {
            drawInnerShadow(
                hole: circle.insetBy(dx: inner.spread, dy: inner.spread),
                around: circle,
                color: inner.color,
                offset: inner.offset,
                blur: inner.blur
            )
        }

        // Bottom white glow: dome opening downward, hugging the lower arc.
        let glowHeight = circle.height * 0.33
        let glow = NSRect(
            x: circle.midX - 5, y: circle.minY + 1, width: 10, height: glowHeight
        )
        NSGraphicsContext.saveGraphicsState()
        Self.domePath(in: glow, roundedSide: .down).addClip()
        NSGradient(
            colorsAndLocations:
                (NSColor.white.withAlphaComponent(0.5), 0),
                (NSColor.white.withAlphaComponent(0.15), 1)
        )?.draw(in: glow, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Top shine: dome hugging the upper arc. Feather passes fake the
        // soft antialiased edge a browser gives this layer.
        let shineHeight = circle.height * 0.30
        let shine = NSRect(
            x: circle.midX - 3.5,
            y: circle.maxY - 1 - shineHeight,
            width: 7,
            height: shineHeight
        )
        let featherPasses: [(inset: CGFloat, alpha: CGFloat)] = [
            (-1.0, 0.06), (-0.5, 0.10), (0, 1),
        ]
        for pass in featherPasses {
            let rect = shine.insetBy(dx: pass.inset, dy: pass.inset)
            NSGraphicsContext.saveGraphicsState()
            Self.domePath(in: rect, roundedSide: .up).addClip()
            NSGradient(
                colorsAndLocations:
                    (NSColor.white.withAlphaComponent(0.04 * pass.alpha), 0),
                    (NSColor.white.withAlphaComponent(0.26 * pass.alpha), 0.45),
                    (NSColor.white.withAlphaComponent(0.65 * pass.alpha), 1)
            )?.draw(in: rect, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }

        if hovering, active {
            NSColor.white.withAlphaComponent(0.1).setFill()
            NSBezierPath(rect: circle).fill()
        }
        if isHighlighted {
            NSColor.black.withAlphaComponent(0.22).setFill()
            NSBezierPath(rect: circle).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if !active {
            cgContext.endTransparencyLayer()
            cgContext.restoreGState()
        }

        guard hovering, active, let iconColor = style.icon else { return }
        drawGlyph(color: iconColor, center: NSPoint(x: circle.midX, y: circle.midY))
    }

    private enum RoundedSide {
        case up
        case down
    }

    /// Rect with one fully rounded side (radius = min(width/2, height)) and
    /// one flat side — the shape CSS `border-radius: 6px 6px 0 0` gives the
    /// shine layer.
    private static func domePath(in rect: NSRect, roundedSide: RoundedSide) -> NSBezierPath {
        let radius = min(rect.width / 2, rect.height)
        let path = NSBezierPath()
        switch roundedSide {
        case .up:
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY - radius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius, startAngle: 180, endAngle: 90, clockwise: true
            )
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.maxY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius, startAngle: 90, endAngle: 0, clockwise: true
            )
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        case .down:
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: 180, endAngle: 270, clockwise: false
            )
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: 270, endAngle: 360, clockwise: false
            )
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        }
        path.close()
        return path
    }

    /// Casts `color` inward from the circle's edge (CSS inset box-shadow):
    /// fills an even-odd ring outside `hole` so only its shadow lands inside
    /// the current oval clip.
    private func drawInnerShadow(
        hole: NSRect,
        around circle: NSRect,
        color: NSColor,
        offset: NSSize,
        blur: CGFloat
    ) {
        NSGraphicsContext.saveGraphicsState()
        let ring = NSBezierPath(rect: circle.insetBy(dx: -blur - 4, dy: -blur - 4))
        ring.windingRule = .evenOdd
        ring.append(NSBezierPath(ovalIn: hole))
        // When the hole is inset (CSS spread), the sliver of ring inside the
        // oval clip is painted too, so fill with the shadow color itself —
        // opaque black here bled through as a harsh dark rim.
        if blur > 0 || offset != .zero {
            let shadow = NSShadow()
            shadow.shadowColor = color
            shadow.shadowOffset = offset
            shadow.shadowBlurRadius = blur
            shadow.set()
        }
        color.setFill()
        ring.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGlyph(color: NSColor, center: NSPoint) {
        color.setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 1.25
        mark.lineCapStyle = .round
        switch kind {
        case .close:
            mark.move(to: NSPoint(x: center.x - 2.3, y: center.y - 2.3))
            mark.line(to: NSPoint(x: center.x + 2.3, y: center.y + 2.3))
            mark.move(to: NSPoint(x: center.x - 2.3, y: center.y + 2.3))
            mark.line(to: NSPoint(x: center.x + 2.3, y: center.y - 2.3))
        case .minimize:
            mark.move(to: NSPoint(x: center.x - 2.8, y: center.y))
            mark.line(to: NSPoint(x: center.x + 2.8, y: center.y))
        case .zoom:
            mark.move(to: NSPoint(x: center.x - 2.8, y: center.y))
            mark.line(to: NSPoint(x: center.x + 2.8, y: center.y))
            mark.move(to: NSPoint(x: center.x, y: center.y - 2.8))
            mark.line(to: NSPoint(x: center.x, y: center.y + 2.8))
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
