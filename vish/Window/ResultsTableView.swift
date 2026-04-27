import AppKit
import QuartzCore

@MainActor
final class ResultsTableView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private var results: [SearchResult] = []
    private var style = LauncherVisualStyle.current
    var onSelectionChange: ((SearchResult?) -> Void)?

    var selectedResult: SearchResult? {
        let row = tableView.selectedRow
        guard results.indices.contains(row) else { return nil }
        return results[row]
    }

    var primaryResult: SearchResult? {
        selectedResult ?? results.first
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        drawsBackground = false
        contentView = NoHorizontalScrollClipView()
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .none

        tableView.addTableColumn(NSTableColumn(identifier: .init("result")))
        tableView.backgroundColor = .clear
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.rowHeight = 48
        tableView.selectionHighlightStyle = .regular

        documentView = tableView
        setAccessibilityIdentifier("vish.results")
        setAccessibilityLabel("Search results")
        applyStyle(style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    func reload(_ newResults: [SearchResult]) {
        let previous = results.map(Self.signature)
        results = newResults
        let next = results.map(Self.signature)
        if previous.count == next.count {
            let changed = IndexSet(next.indices.filter { previous[$0] != next[$0] })
            if changed.isEmpty {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(next.indices))
            } else {
                tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
            }
        } else {
            tableView.reloadData()
        }

        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        notifySelectionChange()

        tableView.layoutSubtreeIfNeeded()
        syncDocumentWidth()
        tableView.displayIfNeeded()
        PerformanceProbe.endKeystrokeToRender()
    }

    func applyStyle(_ style: LauncherVisualStyle) {
        self.style = style
        tableView.rowHeight = style.rowHeight
        tableView.enclosingScrollView?.verticalScroller?.alphaValue = style.tertiaryTextColor.alphaComponent
    }

    override func layout() {
        super.layout()
        syncDocumentWidth()
    }

    private func syncDocumentWidth() {
        let width = contentView.bounds.width
        tableView.tableColumns.first?.width = width
        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(contentView.bounds.height, tableView.frame.height)
        )
        contentView.setBoundsOrigin(NSPoint(x: 0, y: contentView.bounds.origin.y))
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        if delta <= -1_000 {
            let index = min(max(-delta - 1_000, 0), results.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            scrollRowToVisible(index, animated: false)
            notifySelectionChange()
            return
        }

        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + delta, 0), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        scrollRowToVisible(next, animated: true)
        notifySelectionChange()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }

        let cell = tableView.makeView(
            withIdentifier: ResultCellView.reuseIdentifier,
            owner: self
        ) as? ResultCellView ?? ResultCellView()

        cell.identifier = ResultCellView.reuseIdentifier
        cell.configure(with: results[row], index: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRowView(style: style)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        notifySelectionChange()
    }

    private static func signature(_ result: SearchResult) -> String {
        "\(result.kind.rawValue):\(result.id):\(result.title):\(result.subtitle)"
    }

    private func notifySelectionChange() {
        onSelectionChange?(selectedResult)
    }

    private func scrollRowToVisible(_ row: Int, animated: Bool) {
        guard results.indices.contains(row), let clipView = tableView.enclosingScrollView?.contentView else { return }
        let rowRect = tableView.rect(ofRow: row).insetBy(dx: 0, dy: -4)
        let visible = clipView.bounds
        guard !visible.contains(rowRect) else { return }

        var origin = visible.origin
        if rowRect.minY < visible.minY {
            origin.y = rowRect.minY
        } else if rowRect.maxY > visible.maxY {
            origin.y = rowRect.maxY - visible.height
        }

        let maxY = max(0, tableView.bounds.height - visible.height)
        origin.y = min(max(origin.y, 0), maxY)

        guard animated else {
            clipView.setBoundsOrigin(origin)
            reflectScrolledClipView(clipView)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(origin)
        }
    }
}

@MainActor
private final class ResultRowView: NSTableRowView {
    private let style: LauncherVisualStyle

    init(style: LauncherVisualStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        style.primaryTextColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 5, dy: 2),
            xRadius: 10,
            yRadius: 10
        ).fill()
    }
}
