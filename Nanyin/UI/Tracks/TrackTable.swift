import AppKit
import SwiftUI

/// The track list of the 2010 client: graphite column headers, charcoal
/// zebra rows down to the bottom of the pane, a green speaker on the playing
/// row. AppKit's table recycles row views, so thousands of rows stay cheap.
struct TrackTable: NSViewRepresentable {
    enum Column: String {
        case indicator, track, artist, time, popularity, album, added

        static let standard: [Column] = [.indicator, .track, .artist, .time, .popularity, .album]

        var title: String { self == .indicator ? "" : rawValue.capitalized }
    }

    struct Actions {
        var play: (TrackRow) -> Void
        var addToQueue: (TrackRow) -> Void
        var togglePlayPause: () -> Void
        var rowAppeared: (Int) -> Void = { _ in }
    }

    let rows: [TrackRow]
    let playingURI: String?
    var columns = Column.standard
    let actions: Actions

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TrackTableView()
        table.headerView = GraphiteHeaderView()
        table.cornerView = GraphiteCornerView()
        table.rowHeight = 19
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
            case .indicator: tableColumn.width = 22; tableColumn.minWidth = 22; tableColumn.maxWidth = 22
            case .track: tableColumn.width = 260; tableColumn.minWidth = 80
            case .artist: tableColumn.width = 170; tableColumn.minWidth = 60
            case .time: tableColumn.width = 46; tableColumn.minWidth = 40; tableColumn.maxWidth = 60
            case .popularity: tableColumn.width = 72; tableColumn.minWidth = 60; tableColumn.maxWidth = 90
            case .album: tableColumn.width = 190; tableColumn.minWidth = 60
            case .added: tableColumn.width = 86; tableColumn.minWidth = 60
            }
            tableColumn.resizingMask = column == .indicator ? [] : [.userResizingMask, .autoresizingMask]
            table.addTableColumn(tableColumn)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.menu = context.coordinator.makeMenu()
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
        if old != rows {
            coordinator.rows = rows
            coordinator.playingURI = playingURI
            if rows.count > old.count, rows.starts(with: old) {
                // A page arrived: add its rows, leave the visible ones be.
                table.insertRows(at: IndexSet(old.count ..< rows.count), withAnimation: [])
            } else {
                table.reloadData()
            }
        } else if coordinator.playingURI != playingURI {
            coordinator.playingURI = playingURI
            // Only the speaker moves: redraw that column for the rows on screen.
            if let column = columns.firstIndex(of: .indicator) {
                let visible = table.rows(in: table.visibleRect)
                table.reloadData(
                    forRowIndexes: IndexSet(integersIn: visible.location ..< visible.location + visible.length),
                    columnIndexes: IndexSet(integer: column))
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var rows: [TrackRow] = []
        var playingURI: String?
        var actions = Actions(play: { _ in }, addToQueue: { _ in }, togglePlayPause: {})
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
            let isPlaying = track.uri == playingURI
            switch column {
            case .indicator:
                let view = reuse(tableView, "indicator") { IndicatorCell() }
                view.isPlaying = isPlaying
                return view
            case .popularity:
                let view = reuse(tableView, "popularity") { PopularityCell() }
                view.popularity = track.popularity
                return view
            case .track, .artist, .album, .time, .added:
                let text = switch column {
                case .track: track.name
                case .artist: track.artistNames
                case .album: track.album
                case .time: track.duration
                default: track.added
                }
                let view = reuse(tableView, "text") { TextCell() }
                view.set(text, secondary: !track.isPlayable, alignRight: column == .time)
                return view
            }
        }

        private func reuse<T: NSView>(_ table: NSTableView, _ id: String, make: () -> T) -> T {
            let identifier = NSUserInterfaceItemIdentifier(id)
            if let view = table.makeView(withIdentifier: identifier, owner: nil) as? T { return view }
            let view = make()
            view.identifier = identifier
            return view
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard rows.indices.contains(row) else { return }
            actions.play(rows[row])
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
            let row = table.clickedRow
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            menu.addItem(item("Play", #selector(playClicked)))
            menu.addItem(item("Add to Play Queue", #selector(queueClicked)))
            menu.addItem(.separator())
            menu.addItem(item("Copy Spotify Link", #selector(copyLink)))
        }

        private func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private var targetRows: [TrackRow] {
            guard let table else { return [] }
            return table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
        }

        @objc private func playClicked() {
            targetRows.first.map(actions.play)
        }

        @objc private func queueClicked() {
            targetRows.forEach(actions.addToQueue)
        }

        @objc private func copyLink() {
            let links = targetRows.map { row -> String in
                let parts = row.uri.split(separator: ":")
                return parts.count == 3 ? "https://open.spotify.com/\(parts[1])/\(parts[2])" : row.uri
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
        }
    }
}

/// Return plays the selection; space plays or pauses, as in iTunes.
final class TrackTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        guard let coordinator = delegate as? TrackTable.Coordinator else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 36, 76: // return, enter
            if coordinator.rows.indices.contains(selectedRow) {
                coordinator.actions.play(coordinator.rows[selectedRow])
            }
        case 49: // space
            coordinator.actions.togglePlayPause()
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

private final class TextCell: NSTableCellView {
    private static let unplayable = Theme.nsSecondaryText.withAlphaComponent(0.6)
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = AquaFont.ns(11)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func set(_ text: String, secondary: Bool, alignRight: Bool) {
        label.stringValue = text
        label.textColor = secondary ? Self.unplayable : Theme.nsText
        label.alignment = alignRight ? .right : .left
    }
}

/// The green speaker on the row that is playing.
private final class IndicatorCell: NSView {
    var isPlaying = false { didSet { needsDisplay = true } }
    private static let image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Playing")?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .regular).applying(.init(paletteColors: [Theme.nsGreen])))

    override func draw(_ dirtyRect: NSRect) {
        guard isPlaying, let image = Self.image else { return }
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

final class GraphiteCornerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        GraphiteHeaderCell.drawBackground(in: bounds)
    }
}

final class GraphiteHeaderCell: NSTableHeaderCell {
    private static let gradient = NSGradient(starting: Theme.nsGraphiteTop, ending: Theme.nsGraphiteBottom)
    private static let separator = Theme.ns(0x2A2A2A)
    private static let attributes: [NSAttributedString.Key: Any] = {
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.6)
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        return [.font: AquaFont.ns(11, bold: true), .foregroundColor: Theme.ns(0xE0E0E0), .shadow: shadow]
    }()

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
