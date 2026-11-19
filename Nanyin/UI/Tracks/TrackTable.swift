import AppKit
import SwiftUI

/// The track list of the 2010 client: graphite column headers, charcoal
/// zebra rows down to the bottom of the pane, a green speaker on the playing
/// row. AppKit's table recycles row views, so thousands of rows stay cheap.
struct TrackTable: NSViewRepresentable {
    enum Column: String, CaseIterable {
        case indicator, track, artist, time, popularity, album, added

        var title: String {
            switch self {
            case .indicator: ""
            case .track: "Track"
            case .artist: "Artist"
            case .time: "Time"
            case .popularity: "Popularity"
            case .album: "Album"
            case .added: "Added"
            }
        }
    }

    struct Actions {
        var play: (TrackRow) -> Void
        var addToQueue: (TrackRow) -> Void
        var togglePlayPause: () -> Void
        var rowAppeared: (Int) -> Void = { _ in }
    }

    let rows: [TrackRow]
    let playingURI: String?
    var columns: [Column] = [.indicator, .track, .artist, .time, .popularity, .album]
    let actions: Actions

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TrackTableView()
        table.headerView = GraphiteHeaderView()
        table.cornerView = GraphiteCornerView()
        table.rowHeight = 19
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.backgroundColor = Theme.rowEven
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
        scroll.backgroundColor = Theme.rowEven
        scroll.scrollerStyle = .overlay
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.actions = actions
        guard let table = coordinator.table else { return }
        table.actions = actions
        if coordinator.rows != rows {
            coordinator.rows = rows
            table.reloadData()
        } else if coordinator.playingURI != playingURI {
            let changed = coordinator.rows.indices.filter {
                coordinator.rows[$0].uri == coordinator.playingURI || coordinator.rows[$0].uri == playingURI
            }
            coordinator.playingURI = playingURI
            table.reloadData(
                forRowIndexes: IndexSet(changed),
                columnIndexes: IndexSet(integersIn: 0 ..< table.numberOfColumns))
        }
        coordinator.playingURI = playingURI
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
            default:
                let view = reuse(tableView, "text") { TextCell() }
                view.set(text(for: column, of: track), secondary: !track.isPlayable, alignRight: column == .time)
                return view
            }
        }

        private func text(for column: Column, of track: TrackRow) -> String {
            switch column {
            case .track: track.name
            case .artist: track.artistNames
            case .album: track.album
            case .time: Self.duration(track.durationMs)
            case .added: track.addedAt.flatMap(Self.addedDate) ?? ""
            case .indicator, .popularity: ""
            }
        }

        private func reuse<T: NSView>(_ table: NSTableView, _ id: String, make: () -> T) -> T {
            let identifier = NSUserInterfaceItemIdentifier(id)
            if let view = table.makeView(withIdentifier: identifier, owner: nil) as? T { return view }
            let view = make()
            view.identifier = identifier
            return view
        }

        static func duration(_ ms: Int) -> String {
            let seconds = ms / 1000
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

        private static let isoParser = ISO8601DateFormatter()
        static func addedDate(_ value: String) -> String? {
            isoParser.date(from: value)?.formatted(date: .numeric, time: .omitted)
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
    var actions: TrackTable.Actions?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // return, enter
            if let coordinator = delegate as? TrackTable.Coordinator, coordinator.rows.indices.contains(selectedRow) {
                actions?.play(coordinator.rows[selectedRow])
            }
        case 49: // space
            actions?.togglePlayPause()
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
            (index.isMultiple(of: 2) ? Theme.rowEven : Theme.rowOdd).setFill()
            NSRect(x: clipRect.minX, y: CGFloat(index) * height, width: clipRect.width, height: height).fill()
            index += 1
        }
    }
}

final class ZebraRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("zebra")
    var index = 0 { didSet { needsDisplay = true } }

    override func drawBackground(in dirtyRect: NSRect) {
        (index.isMultiple(of: 2) ? Theme.rowEven : Theme.rowOdd).setFill()
        bounds.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let active = isEmphasized
        NSGradient(
            starting: active ? Theme.nsSelectionTop : Theme.nsHex(0x5A5A5A),
            ending: active ? Theme.nsSelectionBottom : Theme.nsHex(0x4A4A4A))?
            .draw(in: bounds, angle: -90)
        NSColor.white.withAlphaComponent(0.15).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class TextCell: NSTableCellView {
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
        label.textColor = secondary ? Theme.nsSecondaryText.withAlphaComponent(0.6) : Theme.nsText
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

    override func draw(_ dirtyRect: NSRect) {
        guard let popularity else { return }
        let lit = Int((Double(popularity) / 100 * Double(Self.bars)).rounded())
        let barWidth: CGFloat = 2, gap: CGFloat = 2, height: CGFloat = 8
        let y = (bounds.height - height) / 2
        for bar in 0 ..< Self.bars {
            (bar < lit ? Theme.nsHex(0xBDBDBD) : Theme.nsHex(0x555555)).setFill()
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
    static func drawBackground(in rect: NSRect) {
        NSGradient(starting: Theme.nsHex(0x585858), ending: Theme.nsHex(0x383838))?.draw(in: rect, angle: -90)
        Theme.nsHex(0x1C1C1C).setFill()
        NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.drawBackground(in: cellFrame)
        // Column separator.
        Theme.nsHex(0x2A2A2A).setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 3, width: 1, height: cellFrame.height - 6).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.6)
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AquaFont.ns(11, bold: true),
            .foregroundColor: Theme.nsHex(0xE0E0E0),
            .shadow: shadow,
        ]
        let text = NSAttributedString(string: stringValue, attributes: attributes)
        let size = text.size()
        text.draw(in: NSRect(
            x: cellFrame.minX + 5, y: cellFrame.midY - size.height / 2,
            width: cellFrame.width - 10, height: size.height))
    }
}
