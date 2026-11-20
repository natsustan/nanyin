import AppKit
import SwiftUI

extension NSWindow {
    /// Key or main: chrome draws in its active colours.
    var isFrontmost: Bool { isKeyWindow || isMainWindow }
}

/// Configures the window Nanyin draws its own chrome into: no system title
/// or traffic lights, content under the title bar, dark controls.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.windowDidChange = { [coordinator = context.coordinator] window in
            coordinator.configure(window)
        }
        return view
    }

    func updateNSView(_ view: WindowAttachmentView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var observer: NSObjectProtocol?

        func configure(_ window: NSWindow?) {
            guard let window, window !== self.window else { return }
            self.window = window
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.setFrameAutosaveName("Main")
            Self.hideSystemButtons(in: window)
            observer.map(NotificationCenter.default.removeObserver)
            // SwiftUI puts the buttons back when the window leaves full screen.
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated { window.map(Self.hideSystemButtons) }
            }
        }

        private static func hideSystemButtons(in window: NSWindow) {
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = true
            }
        }
    }
}

/// Only reports the window it lands in; never takes clicks.
final class WindowAttachmentView: NSView {
    var windowDidChange: (NSWindow?) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange(window)
    }
}

/// The Aqua close / minimise / zoom buttons.
struct TrafficLights: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightsView { TrafficLightsView() }
    func updateNSView(_ view: TrafficLightsView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TrafficLightsView, context: Context) -> CGSize? {
        TrafficLightsView.size
    }
}

final class TrafficLightsView: NSView {
    static let spacing: CGFloat = 20
    static let size = CGSize(width: AquaWindowButton.size + spacing * 2, height: AquaWindowButton.size)

    private let buttons: [AquaWindowButton]
    private let group: AquaWindowButton.Group
    private var observers: [NSObjectProtocol] = []

    init() {
        let group = AquaWindowButton.Group()
        self.group = group
        buttons = AquaWindowButton.Kind.allCases.map { AquaWindowButton(kind: $0, group: group) }
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for (index, button) in buttons.enumerated() {
            button.frame.origin = NSPoint(x: CGFloat(index) * Self.spacing, y: 0)
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.buttons.forEach { $0.needsDisplay = true }
                    // The window may have moved out from under the mouse.
                    self.group.update()
                }
            })
        }
    }
}

/// Behind the title bar: drags the window and handles double-clicks the way
/// the system title bar does. Tracks the mouse itself rather than relying on
/// the window server's draggable regions, which SwiftUI hosting views break.
struct TitleBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "None": break
                case "Minimize": window.performMiniaturize(nil)
                default: window.performZoom(nil)
                }
                return
            }
            let start = NSEvent.mouseLocation
            let origin = window.frame.origin
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
                let mouse = NSEvent.mouseLocation
                var frame = window.frame
                frame.origin = NSPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y)
                window.setFrameOrigin(window.constrainFrameRect(frame, to: window.screen).origin)
            }
        }
    }
}
