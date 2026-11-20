import AppKit

// The Aqua traffic lights, adapted from Lucy's Classic title bar.

/// How one Aqua gel button is drawn: a two-colour gradient, layered outer
/// shadows (painted outside the circle only, like CSS box-shadow), a thin
/// rim, coloured inner shadow and glow, a top shine and a bottom reflection.
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
    let glyph: NSColor

    static func colored(
        top: NSColor, bottom: NSColor, halo: NSColor, innerShadow: NSColor, innerGlow: NSColor, glyph: NSColor
    ) -> AquaButtonStyle {
        AquaButtonStyle(
            top: top,
            bottom: bottom,
            outerShadows: [
                OuterShadow(color: .black.withAlphaComponent(0.5), offset: NSSize(width: 0, height: -2), blur: 3.5),
                OuterShadow(color: .black.withAlphaComponent(0.4), offset: NSSize(width: 0, height: -1), blur: 2),
                OuterShadow(color: halo, offset: NSSize(width: 0, height: -1), blur: 1),
            ],
            innerShadows: [
                InnerShadow(color: .black.withAlphaComponent(0.3), offset: .zero, blur: 0, spread: 0.5),
                InnerShadow(color: innerShadow, offset: NSSize(width: 0, height: -1), blur: 3, spread: 0),
                InnerShadow(color: innerGlow, offset: NSSize(width: 0, height: -2), blur: 4.5, spread: 1),
                // A softer layer that lifts the middle.
                InnerShadow(
                    color: innerGlow.withAlphaComponent(innerGlow.alphaComponent * 0.5),
                    offset: NSSize(width: 0, height: -3), blur: 5, spread: 1),
            ],
            glyph: glyph
        )
    }

    /// Inactive window: translucent grey to white.
    static let inactive = AquaButtonStyle(
        top: NSColor(calibratedWhite: 0.55, alpha: 0.55),
        bottom: NSColor(calibratedWhite: 1, alpha: 0.55),
        outerShadows: [
            OuterShadow(color: .black.withAlphaComponent(0.2), offset: NSSize(width: 0, height: -2), blur: 3),
            OuterShadow(color: .black.withAlphaComponent(0.3), offset: NSSize(width: 0, height: -1), blur: 1),
        ],
        innerShadows: [
            InnerShadow(color: .black.withAlphaComponent(0.3), offset: .zero, blur: 0, spread: 0.5),
            InnerShadow(color: .black.withAlphaComponent(0.35), offset: NSSize(width: 0, height: -1), blur: 2, spread: 0),
            InnerShadow(color: .white.withAlphaComponent(0.35), offset: NSSize(width: 0, height: -2), blur: 3, spread: 1),
        ],
        glyph: NSColor(calibratedWhite: 0.25, alpha: 0.8)
    )

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    static let close = colored(
        top: srgb(193, 58, 45), bottom: srgb(205, 73, 52), halo: srgb(225, 70, 64, 0.5),
        innerShadow: srgb(150, 40, 30, 0.8), innerGlow: srgb(225, 70, 64, 0.75), glyph: srgb(130, 30, 20, 0.9))
    static let minimize = colored(
        top: srgb(202, 130, 13), bottom: srgb(253, 253, 149), halo: srgb(223, 161, 35, 0.5),
        innerShadow: srgb(155, 78, 21), innerGlow: srgb(241, 157, 20), glyph: srgb(130, 80, 8, 0.9))
    static let zoom = colored(
        top: srgb(111, 174, 58), bottom: srgb(138, 192, 50), halo: srgb(59, 173, 29, 0.5),
        innerShadow: srgb(53, 91, 17), innerGlow: srgb(98, 187, 19), glyph: srgb(45, 90, 18, 0.9))
}

final class AquaWindowButton: NSButton {
    enum Kind: CaseIterable {
        case close
        case minimize
        case zoom

        fileprivate var style: AquaButtonStyle {
            switch self {
            case .close: .close
            case .minimize: .minimize
            case .zoom: .zoom
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

    /// The three buttons of one window: hovering any shows all glyphs.
    /// Asks where the mouse is rather than counting enters and exits: a
    /// click that minimises the window or takes it full screen moves it out
    /// from under the mouse, and no exit ever comes.
    @MainActor
    final class Group {
        private var pendingCheck: DispatchWorkItem?
        fileprivate let buttons = NSHashTable<AquaWindowButton>.weakObjects()
        fileprivate private(set) var showsGlyphs = false

        fileprivate func mouseEntered() {
            pendingCheck?.cancel()
            setShowsGlyphs(true)
        }

        /// Moving between buttons sends exit before enter; look again a
        /// moment later so glyphs do not flicker.
        fileprivate func mouseExited() {
            pendingCheck?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.update() }
            }
            pendingCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        /// Shows the glyphs only while the mouse is over a button.
        func update() {
            setShowsGlyphs(buttons.allObjects.contains(where: \.containsMouse))
        }

        private func setShowsGlyphs(_ value: Bool) {
            guard showsGlyphs != value else { return }
            showsGlyphs = value
            buttons.allObjects.forEach { $0.needsDisplay = true }
        }
    }

    /// Circle diameter. Shine, glow and glyphs are designed at 14pt and scaled.
    private static let diameter: CGFloat = 12
    private static let scale = diameter / 14
    /// Room around the circle for the outer shadow.
    static let size: CGFloat = diameter + 6

    let kind: Kind
    private let group: Group

    // Drawn with y up: shine at maxY, shadow towards minY.
    override var isFlipped: Bool { false }

    init(kind: Kind, group: Group) {
        self.kind = kind
        self.group = group
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        isBordered = false
        title = ""
        target = self
        action = #selector(performWindowAction)
        setAccessibilityLabel(kind.accessibilityLabel)
        group.buttons.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { group.mouseEntered() }
    override func mouseExited(with event: NSEvent) { group.mouseExited() }

    /// Over this button, and not behind another window that covers it.
    fileprivate var containsMouse: Bool {
        guard let window, window.isVisible, !window.isMiniaturized,
              bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        else { return false }
        return NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
    }

    /// Clickable while the window is inactive, like the system buttons.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    /// Redrawn by `TrafficLightsView` when the window's key state changes.
    private var isActive: Bool { window?.isFrontmost ?? false }

    override func draw(_ dirtyRect: NSRect) {
        let active = isActive
        let style = active ? kind.style : .inactive
        let inset = (bounds.width - Self.diameter) / 2
        let circle = bounds.insetBy(dx: inset, dy: inset)
        let oval = NSBezierPath(ovalIn: circle)

        // Outer shadows, outside the circle only.
        NSGraphicsContext.saveGraphicsState()
        let outside = NSBezierPath(rect: bounds)
        outside.append(oval)
        outside.windingRule = .evenOdd
        outside.addClip()
        for outer in style.outerShadows {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = outer.color
            shadow.shadowOffset = outer.offset
            shadow.shadowBlurRadius = outer.blur
            shadow.set()
            NSColor.black.setFill()
            oval.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        oval.addClip()

        // The gel: dark at the top, light at the bottom.
        NSGradient(colorsAndLocations: (style.bottom, 0), (style.top, 1))?.draw(in: circle, angle: 90)

        for inner in style.innerShadows {
            drawInnerShadow(
                hole: circle.insetBy(dx: inner.spread, dy: inner.spread), around: circle,
                color: inner.color, offset: inner.offset, blur: inner.blur)
        }

        // Bottom reflection.
        let s = Self.scale
        let glow = NSRect(x: circle.midX - 5 * s, y: circle.minY + s, width: 10 * s, height: circle.height * 0.33)
        NSGraphicsContext.saveGraphicsState()
        Self.domePath(in: glow, roundedSide: .down).addClip()
        NSGradient(
            colorsAndLocations: (NSColor.white.withAlphaComponent(0.5), 0), (NSColor.white.withAlphaComponent(0.15), 1)
        )?.draw(in: glow, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Top shine, with two faint passes for a soft edge.
        let shineHeight = circle.height * 0.30
        let shine = NSRect(x: circle.midX - 3.5 * s, y: circle.maxY - s - shineHeight, width: 7 * s, height: shineHeight)
        for pass in [(inset: -1.0, alpha: 0.06), (inset: -0.5, alpha: 0.10), (inset: 0, alpha: 1)] {
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

        if isHighlighted {
            NSColor.black.withAlphaComponent(0.22).setFill()
            NSBezierPath(rect: circle).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if group.showsGlyphs {
            drawGlyph(color: style.glyph, center: NSPoint(x: circle.midX, y: circle.midY))
        }
    }

    private enum RoundedSide {
        case up
        case down
    }

    /// A shape rounded on one side and flat on the other.
    private static func domePath(in rect: NSRect, roundedSide: RoundedSide) -> NSBezierPath {
        let radius = min(rect.width / 2, rect.height)
        let path = NSBezierPath()
        switch roundedSide {
        case .up:
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY - radius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius, startAngle: 180, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.maxY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius, startAngle: 90, endAngle: 0, clockwise: true)
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        case .down:
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
            path.appendArc(
                withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: 180, endAngle: 270, clockwise: false)
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
            path.appendArc(
                withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: 270, endAngle: 360, clockwise: false)
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        }
        path.close()
        return path
    }

    /// An inset shadow: fill a ring around `hole` so only its shadow falls inside the clip.
    private func drawInnerShadow(hole: NSRect, around circle: NSRect, color: NSColor, offset: NSSize, blur: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let ring = NSBezierPath(rect: circle.insetBy(dx: -blur - 4, dy: -blur - 4))
        ring.windingRule = .evenOdd
        ring.append(NSBezierPath(ovalIn: hole))
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
        let s = Self.scale
        let x = 2.4 * s, bar = 3 * s
        color.setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 1.25 * s
        mark.lineCapStyle = .round
        switch kind {
        case .close:
            mark.move(to: NSPoint(x: center.x - x, y: center.y - x))
            mark.line(to: NSPoint(x: center.x + x, y: center.y + x))
            mark.move(to: NSPoint(x: center.x - x, y: center.y + x))
            mark.line(to: NSPoint(x: center.x + x, y: center.y - x))
        case .minimize:
            mark.move(to: NSPoint(x: center.x - bar, y: center.y))
            mark.line(to: NSPoint(x: center.x + bar, y: center.y))
        case .zoom:
            mark.move(to: NSPoint(x: center.x - bar, y: center.y))
            mark.line(to: NSPoint(x: center.x + bar, y: center.y))
            mark.move(to: NSPoint(x: center.x, y: center.y - bar))
            mark.line(to: NSPoint(x: center.x, y: center.y + bar))
        }
        mark.stroke()
    }

    /// Same as the system buttons: green toggles full screen, Option-click zooms.
    @objc private func performWindowAction() {
        guard let window else { return }
        switch kind {
        case .close:
            window.performClose(self)
        case .minimize:
            window.performMiniaturize(self)
        case .zoom:
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                window.performZoom(self)
            } else {
                window.toggleFullScreen(self)
            }
        }
    }
}
