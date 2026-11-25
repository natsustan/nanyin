import AppKit
import SwiftUI

/// The track list of the 2010 client: graphite column headers, charcoal
/// zebra rows down to the bottom of the pane, the playing song in green
/// with a speaker in place of its star, artists and albums as links.
/// AppKit's table recycles row views, so thousands of rows stay cheap.
struct TrackTable: NSViewRepresentable {
    enum Column: String {
        case star, track, artist, time, popularity, album, added

        static let standard: [Column] = [.star, .track, .artist, .time, .popularity, .album]

        var isFixed: Bool { self == .star }
        var title: String { isFixed ? "" : rawValue.capitalized }
    }

    struct Actions {
        var play: (TrackRow) -> Void
        var rowAppeared: (Int) -> Void = { _ in }
        var isStarred: (TrackRow) -> Bool? = { _ in nil }
        var toggleStar: (TrackRow) -> Void = { _ in }
        /// The context menu for the selected rows.
        var menu: ([TrackRow]) -> [TrackMenuItem] = { _ in [] }
        /// Opens an artist's or album's page.
        var open: (Route) -> Void
        /// Reorders one track from `from` to `insertBefore` when drag-reordering is enabled.
        var reorder: ((_ from: Int, _ insertBefore: Int, _ uri: String) -> Void)? = nil
    }

    static let reorderPasteboardType = NSPasteboard.PasteboardType("com.cosmoss.nanyin.track-row")

    let rows: [TrackRow]
    let playingURIs: Set<String>
    var isPlaybackActive = true
    /// Changes whenever any star changes.
    var starsVersion = 0
    var columns = Column.standard
    let actions: Actions

    func makeCoordinator() -> Coordinator { Coordinator() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TrackTableView()
        table.headerView = GraphiteHeaderView()
        table.cornerView = GraphiteCornerView()
        table.rowHeight = 21
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.backgroundColor = Theme.row(0)
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .plain
        table.focusRingType = .none
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.headerCell = GraphiteHeaderCell(textCell: column.title)
            switch column {
            case .star: tableColumn.width = 20; tableColumn.minWidth = 20; tableColumn.maxWidth = 20
            case .track: tableColumn.width = 260; tableColumn.minWidth = 80
            case .artist: tableColumn.width = 170; tableColumn.minWidth = 60
            case .time: tableColumn.width = 46; tableColumn.minWidth = 40; tableColumn.maxWidth = 60
            case .popularity: tableColumn.width = 72; tableColumn.minWidth = 60; tableColumn.maxWidth = 90
            case .album: tableColumn.width = 190; tableColumn.minWidth = 60
            case .added: tableColumn.width = 86; tableColumn.minWidth = 60
            }
            tableColumn.resizingMask = column.isFixed ? [] : [.userResizingMask, .autoresizingMask]
            table.addTableColumn(tableColumn)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.action = #selector(Coordinator.clicked(_:))
        table.menu = context.coordinator.makeMenu()
        table.registerForDraggedTypes([Self.reorderPasteboardType])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        context.coordinator.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.row(0)
        scroll.scrollerStyle = .overlay
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.actions = actions
        guard let table = coordinator.table else { return }
        let old = coordinator.rows
        let wasPlaying = coordinator.playingURIs
        let wasActive = coordinator.isPlaybackActive
        let starsChanged = coordinator.starsVersion != starsVersion
        coordinator.rows = rows
        coordinator.playingURIs = playingURIs
        coordinator.isPlaybackActive = isPlaybackActive
        coordinator.starsVersion = starsVersion
        if old != rows {
            // Rows read through the session carry no popularity.
            table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Column.popularity.rawValue))?
                .isHidden = !rows.contains { $0.popularity != nil }
            guard rows.count > old.count, rows.starts(with: old) else { return table.reloadData() }
            // A page arrived: add its rows, leave the visible ones be.
            table.insertRows(at: IndexSet(old.count ..< rows.count), withAnimation: [])
        }
        // Redraw the rows on screen that changed: every column of the rows
        // that start or stop playing (green), the stars of all of them.
        let visible = table.rows(in: table.visibleRect)
        let start = max(0, visible.location)
        let end = min(rows.count, visible.location + visible.length)
        let onScreen = start < end ? IndexSet(integersIn: start ..< end) : IndexSet()
        if wasPlaying != playingURIs || wasActive != isPlaybackActive {
            let affected = wasActive != isPlaybackActive
                ? wasPlaying.union(playingURIs)
                : wasPlaying.symmetricDifference(playingURIs)
            let changed = onScreen.filter { affected.contains(rows[$0].uri) }
            table.reloadData(forRowIndexes: IndexSet(changed), columnIndexes: IndexSet(integersIn: 0 ..< table.numberOfColumns))
        }
        if starsChanged, let star = columns.firstIndex(of: .star) {
            table.reloadData(forRowIndexes: onScreen, columnIndexes: [star])
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var rows: [TrackRow] = []
        var playingURIs: Set<String> = []
        var isPlaybackActive = true
        var starsVersion = 0
        var actions = Actions(play: { _ in }, open: { _ in })
        weak var table: TrackTableView?

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = tableView.makeView(withIdentifier: ZebraRowView.identifier, owner: nil) as? ZebraRowView ?? ZebraRowView()
            view.identifier = ZebraRowView.identifier
            view.index = row
            actions.rowAppeared(row)
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
            let track = rows[row]
            let isPlaying = playingURIs.contains(track.uri)
            let hover = (tableView as? TrackTableView)?.hovered
            let hovered = hover?.row == row && hover?.column == tableView.column(withIdentifier: tableColumn.identifier)
            switch column {
            case .star:
                // The speaker takes the playing row's star, as in the 2010
                // client; the star shows again under the pointer to be clicked.
                let view = reuse(tableView, "symbol") { SymbolCell() }
                let star = actions.isStarred(track).flatMap { $0 ? SymbolCell.starred : SymbolCell.unstarred }
                let indicator = isPlaybackActive ? SymbolCell.speaker : SymbolCell.pausedSpeaker
                view.image = isPlaying && !hovered ? indicator : star
                return view
            case .popularity:
                let view = reuse(tableView, "popularity") { PopularityCell() }
                view.popularity = track.popularity
                return view
            case .track, .artist, .album, .time, .added:
                let parts: [TextCell.Part] = switch column {
                case .track: [.init(track.name)]
                case .artist: track.artists.enumerated().flatMap { index, artist in
                    (index > 0 ? [TextCell.Part(", ")] : []) + [.init(artist.name, link: artist.route)]
                }
                case .album: [.init(track.album, link: track.albumRoute)]
                case .time: [.init(track.duration)]
                default: [.init(track.added)]
                }
                let view = reuse(tableView, "text") { TextCell() }
                view.set(parts, tone: isPlaying ? .playing : track.isPlayable ? .normal : .unplayable,
                         alignRight: column == .time, hovered: hovered ? hover?.part : nil)
                return view
            }
        }

        /// Typing a song's first letters selects it.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            tableColumn?.identifier.rawValue == Column.track.rawValue ? rows[row].name : nil
        }

        private func reuse<T: NSView>(_ table: NSTableView, _ id: String, make: () -> T) -> T {
            let identifier = NSUserInterfaceItemIdentifier(id)
            if let view = table.makeView(withIdentifier: identifier, owner: nil) as? T { return view }
            let view = make()
            view.identifier = identifier
            return view
        }

        /// A link clicked once, opened unless a second click makes it a
        /// double-click (which plays the row, wherever it lands).
        private var pendingLink: Task<Void, Never>?

        /// A click on a star toggles it, without changing the selection's
        /// meaning; a click on a link opens its page.
        @objc func clicked(_ sender: NSTableView) {
            pendingLink?.cancel()
            guard rows.indices.contains(sender.clickedRow), sender.clickedColumn >= 0 else { return }
            if sender.tableColumns[sender.clickedColumn].identifier.rawValue == Column.star.rawValue {
                actions.toggleStar(rows[sender.clickedRow])
            } else if let table = sender as? TrackTableView, let route = table.releasedOnPressedLink() {
                pendingLink = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                    guard !Task.isCancelled else { return }
                    self?.actions.open(route)
                }
            }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            pendingLink?.cancel()
            let row = sender.clickedRow
            guard rows.indices.contains(row) else { return }
            actions.play(rows[row])
        }

        // MARK: Drag & Drop

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString("\(row)\n\(rows[row].uri)", forType: TrackTable.reorderPasteboardType)
            item.setString(Route.webLink(for: rows[row].uri), forType: .string)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard actions.reorder != nil,
                  info.draggingSource as? NSTableView === tableView,
                  info.draggingPasteboard.pasteboardItems?.count == 1,
                  info.draggingPasteboard.string(forType: TrackTable.reorderPasteboardType) != nil
            else { return [] }
            if dropOperation == .on {
                tableView.setDropRow(row, dropOperation: .above)
            }
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard let reorder = actions.reorder,
                  info.draggingSource as? NSTableView === tableView,
                  info.draggingPasteboard.pasteboardItems?.count == 1,
                  let raw = info.draggingPasteboard.string(forType: TrackTable.reorderPasteboardType),
                  let newline = raw.firstIndex(of: "\n"),
                  let from = Int(raw[..<newline]),
                  rows.indices.contains(from)
            else { return false }
            let draggedURI = String(raw[raw.index(after: newline)...])
            guard rows[from].uri == draggedURI, from != row, from + 1 != row else { return false }
            reorder(from, row, draggedURI)
            return true
        }

        // MARK: Context menu

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            if !table.selectedRowIndexes.contains(table.clickedRow) {
                table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false)
            }
            let selected = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
            for item in actions.menu(selected) { menu.addItem(Self.menuItem(item)) }
        }

        private static func menuItem(_ item: TrackMenuItem) -> NSMenuItem {
            if item.title.isEmpty { return .separator() }
            let entry = MenuAction(title: item.title, action: item.action)
            if !item.children.isEmpty {
                entry.submenu = NSMenu()
                for child in item.children { entry.submenu?.addItem(menuItem(child)) }
            }
            return entry
        }
    }
}

/// One entry of a track's context menu, built by whoever owns the table.
struct TrackMenuItem {
    let title: String
    var children: [TrackMenuItem] = []
    var action: (() -> Void)?

    static var separator: TrackMenuItem { TrackMenuItem(title: "") }
}

/// Track menu items in a SwiftUI context menu.
struct TrackMenuContent: View {
    let items: [TrackMenuItem]

    var body: some View {
        ForEach(items.indices, id: \.self) { index in
            let item = items[index]
            if item.title.isEmpty {
                Divider()
            } else if item.children.isEmpty {
                Button(item.title) { item.action?() }
            } else {
                Menu(item.title) { AnyView(TrackMenuContent(items: item.children)) }
            }
        }
    }
}

/// A menu item that runs a closure.
private final class MenuAction: NSMenuItem {
    private let run: (() -> Void)?

    init(title: String, action: (() -> Void)?) {
        run = action
        super.init(title: title, action: action == nil ? nil : #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func runAction() { run?() }
}

/// Return plays the selection, as in iTunes. Links in cells underline
/// under the pointer and open on a click that goes down and up on them; a
/// star shows under the pointer where the speaker stands.
final class TrackTableView: NSTableView {
    /// A cell under the pointer: a star cell, or a link (`part`) in a text cell.
    struct Spot: Equatable {
        let row: Int, column: Int
        var part: Int?
    }

    /// Read when configuring cells, so a recycled cell never keeps it.
    private(set) var hovered: Spot?
    private var pressed: Spot?
    private var trackingArea: NSTrackingArea?
    private var scrollObserver: (any NSObjectProtocol)?

    private func spot(at point: NSPoint) -> Spot? {
        let row = row(at: point), column = column(at: point)
        guard row >= 0, column >= 0 else { return nil }
        switch view(atColumn: column, row: row, makeIfNecessary: false) {
        case let cell as TextCell:
            return cell.link(at: cell.convert(point, from: self)).map { Spot(row: row, column: column, part: $0) }
        case is SymbolCell:
            return Spot(row: row, column: column)
        default:
            return nil
        }
    }

    private func pointer(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }

    /// The page to open, when the click in progress ends on the link it began on.
    func releasedOnPressedLink() -> Route? {
        guard let pressed, let part = pressed.part, let event = NSApp.currentEvent, spot(at: pointer(event)) == pressed,
              let cell = view(atColumn: pressed.column, row: pressed.row, makeIfNecessary: false) as? TextCell
        else { return nil }
        return cell.route(part)
    }

    override func mouseDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
        pressed = plain && event.clickCount == 1 ? spot(at: pointer(event)) : nil
        defer { pressed = nil }
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover(at: pointer(event))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover(at: nil)
    }

    /// Rows move under a still pointer while the list scrolls. Watched on
    /// the clip view: overriding `scrollWheel` would end responsive scrolling.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scrollObserver.map(NotificationCenter.default.removeObserver)
        scrollObserver = nil
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                self.hover(at: self.visibleRect.contains(point) ? point : nil)
            }
        }
    }

    /// Moves the hover, redrawing the cell it leaves and the one it enters.
    private func hover(at point: NSPoint?) {
        let spot = point.flatMap(spot(at:))
        guard spot != hovered else { return }
        let left = hovered
        hovered = spot
        for changed in [left, spot].compactMap(\.self) where changed.row < numberOfRows {
            reloadData(forRowIndexes: [changed.row], columnIndexes: [changed.column])
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let coordinator = delegate as? TrackTable.Coordinator else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 36, 76: // return, enter
            if coordinator.rows.indices.contains(selectedRow) {
                coordinator.actions.play(coordinator.rows[selectedRow])
            }
        default:
            super.keyDown(with: event)
        }
    }

    /// Zebra stripes continue below the last row, to the bottom of the pane.
    override func drawBackground(inClipRect clipRect: NSRect) {
        let height = rowHeight + intercellSpacing.height
        guard height > 0 else { return super.drawBackground(inClipRect: clipRect) }
        var index = max(0, Int(clipRect.minY / height))
        while CGFloat(index) * height < clipRect.maxY {
            Theme.row(index).setFill()
            NSRect(x: clipRect.minX, y: CGFloat(index) * height, width: clipRect.width, height: height).fill()
            index += 1
        }
    }
}

final class ZebraRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("zebra")
    var index = 0 { didSet { needsDisplay = true } }

    private static let selection = NSGradient(starting: Theme.nsSelectionTop, ending: Theme.nsSelectionBottom)
    private static let inactiveSelection = NSGradient(starting: Theme.ns(0x5A5A5A), ending: Theme.ns(0x4A4A4A))
    private static let shine = NSColor.white.withAlphaComponent(0.15)

    override func drawBackground(in dirtyRect: NSRect) {
        Theme.row(index).setFill()
        bounds.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        (isEmphasized ? Self.selection : Self.inactiveSelection)?.draw(in: bounds, angle: -90)
        Self.shine.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// A line of text in parts, some of them links: the artists of a song,
/// each opening their page. A link underlines while hovered and shows the
/// pointing hand. The playing song's text is green. The text and its
/// measurements are made once per `set`, not per draw or pointer move.
private final class TextCell: NSView {
    enum Tone {
        case normal, playing, unplayable

        var color: NSColor {
            switch self {
            case .normal: Theme.nsText
            case .playing: Theme.nsGreen
            case .unplayable: Theme.nsSecondaryText.withAlphaComponent(0.6)
            }
        }
    }

    struct Part {
        let text: String
        var link: Route?

        init(_ text: String, link: Route? = nil) {
            self.text = text
            self.link = link
        }
    }

    private static let font = AquaFont.ns(12)
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
    private static let inset: CGFloat = 7
    private static let ellipsis = NSAttributedString(string: "…", attributes: [.font: font]).size().width
    private static let leftAligned = paragraph(.left)
    private static let rightAligned = paragraph(.right)

    private static func paragraph(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        return style
    }

    private var parts: [Part] = []
    private var alignRight = false
    private var text = NSAttributedString()
    /// Where each part ends, from the text's start.
    private var ends: [CGFloat] = []

    override var isFlipped: Bool { true }

    func set(_ parts: [Part], tone: Tone, alignRight: Bool = false, hovered: Int? = nil) {
        self.parts = parts
        self.alignRight = alignRight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: tone.color, .paragraphStyle: alignRight ? Self.rightAligned : Self.leftAligned,
        ]
        let text = NSMutableAttributedString()
        ends = []
        for (index, part) in parts.enumerated() {
            let run = NSAttributedString(string: part.text, attributes: attributes)
            ends.append((ends.last ?? 0) + run.size().width)
            text.append(run)
            if index == hovered {
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                  range: NSRange(location: text.length - run.length, length: run.length))
            }
        }
        self.text = text
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func route(_ part: Int) -> Route? { parts.indices.contains(part) ? parts[part].link : nil }

    private var textRect: NSRect {
        NSRect(
            x: Self.inset, y: ((bounds.height - Self.lineHeight) / 2).rounded(),
            width: max(0, bounds.width - 2 * Self.inset), height: Self.lineHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// The links' spans on screen, by part: nothing past where a truncated
    /// line's ellipsis begins.
    private var linkSpans: [(part: Int, span: ClosedRange<CGFloat>)] {
        guard !alignRight else { return [] }
        let rect = textRect
        let shown = (ends.last ?? 0) <= rect.width ? rect.maxX : rect.maxX - Self.ellipsis
        return parts.indices.compactMap { index in
            let start = rect.minX + (index > 0 ? ends[index - 1] : 0)
            let end = min(rect.minX + ends[index], shown)
            return parts[index].link != nil && start < end ? (index, start ... end) : nil
        }
    }

    /// The part of the link at `point`, in this view's coordinates.
    func link(at point: NSPoint) -> Int? {
        guard point.y >= 0, point.y < bounds.height else { return nil }
        return linkSpans.first { $0.span.contains(point.x) }?.part
    }

    override func resetCursorRects() {
        for (_, span) in linkSpans {
            addCursorRect(NSRect(x: span.lowerBound, y: 0, width: span.upperBound - span.lowerBound, height: bounds.height),
                          cursor: .pointingHand)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { text.string }
}

/// A small symbol centred in its cell: a star, or the playing speaker.
private final class SymbolCell: NSView {
    var image: NSImage? { didSet { if image !== oldValue { needsDisplay = true } } }

    static func symbol(_ name: String, _ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular).applying(.init(paletteColors: [color])))
    }

    static let speaker = symbol("speaker.wave.2.fill", Theme.nsGreen)
    static let pausedSpeaker = symbol("speaker.fill", Theme.nsGreen)
    /// The 2010 star: an outline until starred, then filled in gold.
    static let starred = symbol("star.fill", Theme.nsStar)
    static let unstarred = symbol("star", Theme.nsSecondaryText.withAlphaComponent(0.5))

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let size = image.size
        image.draw(in: NSRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height))
    }
}

/// Spotify's popularity meter: a row of thin bars, lit up to the value.
private final class PopularityCell: NSView {
    var popularity: Int? { didSet { needsDisplay = true } }
    private static let bars = 12
    private static let lit = Theme.ns(0xBDBDBD)
    private static let unlit = Theme.ns(0x555555)

    override func draw(_ dirtyRect: NSRect) {
        guard let popularity else { return }
        let lit = Int((Double(popularity) / 100 * Double(Self.bars)).rounded())
        let barWidth: CGFloat = 2, gap: CGFloat = 2, height: CGFloat = 8
        let y = (bounds.height - height) / 2
        for bar in 0 ..< Self.bars {
            (bar < lit ? Self.lit : Self.unlit).setFill()
            NSRect(x: 6 + CGFloat(bar) * (barWidth + gap), y: y, width: barWidth, height: height).fill()
        }
    }
}

// MARK: Header

final class GraphiteHeaderView: NSTableHeaderView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.frame.size.height = 20
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        GraphiteHeaderCell.drawBackground(in: bounds)
        super.draw(dirtyRect)
    }
}

/// The header's piece above the scroller. Flipped like the header view, so
/// the shared drawing lands the same way up.
final class GraphiteCornerView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        GraphiteHeaderCell.drawBackground(in: bounds)
    }
}

final class GraphiteHeaderCell: NSTableHeaderCell {
    private static let gradient = NSGradient(starting: Theme.nsGraphiteTop, ending: Theme.nsGraphiteBottom)
    private static let separator = Theme.ns(0x2A2A2A)
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: AquaFont.ns(12, bold: true),
        .foregroundColor: Theme.ns(0xE0E0E0),
    ]

    static func drawBackground(in rect: NSRect) {
        gradient?.draw(in: rect, angle: -90)
        Theme.nsGraphiteEdge.setFill()
        NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
        Theme.nsGraphiteHighlight.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.drawBackground(in: cellFrame)
        Self.separator.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 3, width: 1, height: cellFrame.height - 6).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let text = NSAttributedString(string: stringValue, attributes: Self.attributes)
        let height = text.size().height
        text.draw(in: NSRect(
            x: cellFrame.minX + 5, y: cellFrame.midY - height / 2,
            width: cellFrame.width - 10, height: height))
    }
}
