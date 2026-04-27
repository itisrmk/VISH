import AppKit

@MainActor
struct InlineActionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let badge: String
    let symbolName: String
    let run: @MainActor () -> Void
}

@MainActor
final class InlineActionsView: NSView {
    private let lockedTitleField = NSTextField(labelWithString: "")
    private let lockedSubtitleField = NSTextField(labelWithString: "")
    private let lockedBadgeField = ActionBadgeField(text: "Locked")
    private let scrollView = NSScrollView()
    private let rowsContainer = FlippedRowsView()
    private var actions: [InlineActionItem] = []
    private var rowViews: [InlineActionRowControl] = []
    private var selectedIndex = 0
    private var style = LauncherVisualStyle.current

    var selectedAction: InlineActionItem? {
        guard actions.indices.contains(selectedIndex) else { return actions.first }
        return actions[selectedIndex]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.borderWidth = 1

        lockedTitleField.lineBreakMode = .byTruncatingTail
        lockedSubtitleField.lineBreakMode = .byTruncatingTail
        lockedBadgeField.alignment = .center
        lockedBadgeField.lineBreakMode = .byTruncatingTail
        lockedBadgeField.wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.contentView = NoHorizontalScrollClipView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = rowsContainer

        [lockedTitleField, lockedSubtitleField, lockedBadgeField, scrollView].forEach(addSubview)
        setAccessibilityIdentifier("vish.actions")
        setAccessibilityLabel("Actions")
        applyStyle(style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 16
        let headerHeight: CGFloat = 54
        let badgeWidth: CGFloat = 68
        lockedBadgeField.frame = NSRect(
            x: bounds.width - inset - badgeWidth,
            y: bounds.height - 36,
            width: badgeWidth,
            height: 22
        )
        lockedTitleField.frame = NSRect(
            x: inset,
            y: bounds.height - 30,
            width: max(80, lockedBadgeField.frame.minX - inset - 12),
            height: 18
        )
        lockedSubtitleField.frame = NSRect(
            x: inset,
            y: bounds.height - 48,
            width: lockedTitleField.frame.width,
            height: 15
        )
        scrollView.frame = NSRect(
            x: inset,
            y: 6,
            width: bounds.width - inset * 2,
            height: max(0, bounds.height - headerHeight - 8)
        )
        layoutRows()
    }

    func configure(result: SearchResult, actions: [InlineActionItem]) {
        lockedTitleField.stringValue = result.title
        lockedSubtitleField.stringValue = result.subtitle.isEmpty ? result.kind.rawValue : result.subtitle
        reload(actions)
    }

    func reload(_ actions: [InlineActionItem]) {
        self.actions = actions
        selectedIndex = actions.isEmpty ? -1 : 0
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = actions.enumerated().map { index, action in
            let row = InlineActionRowControl()
            row.onSelect = { [weak self] in self?.selectRow(index) }
            row.configure(action, style: style)
            rowsContainer.addSubview(row)
            return row
        }
        applySelection()
        layoutRows()
        rowViews.first?.scrollToVisible(rowViews.first?.bounds ?? .zero)
        PerformanceProbe.endKeystrokeToRender()
    }

    func moveSelection(by delta: Int) {
        guard !actions.isEmpty else { return }
        selectRow(min(max(selectedIndex + delta, 0), actions.count - 1))
    }

    func applyStyle(_ style: LauncherVisualStyle) {
        self.style = style
        layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.045).cgColor
        layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.08).cgColor
        lockedTitleField.font = .systemFont(ofSize: style.titleFontSize + 1, weight: .semibold)
        lockedTitleField.textColor = style.primaryTextColor
        lockedSubtitleField.font = .systemFont(ofSize: style.subtitleFontSize, weight: .regular)
        lockedSubtitleField.textColor = style.secondaryTextColor
        lockedBadgeField.font = .systemFont(ofSize: max(10, style.subtitleFontSize - 1), weight: .semibold)
        lockedBadgeField.textColor = style.secondaryTextColor
        lockedBadgeField.layer?.cornerRadius = 8
        lockedBadgeField.layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.07).cgColor
        lockedBadgeField.layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.10).cgColor
        lockedBadgeField.layer?.borderWidth = 1
        rowViews.forEach { $0.applyStyle(style) }
        needsLayout = true
    }

    private func selectRow(_ index: Int) {
        guard actions.indices.contains(index) else { return }
        selectedIndex = index
        applySelection()
        rowViews[index].scrollToVisible(rowViews[index].bounds)
    }

    private func applySelection() {
        for (index, row) in rowViews.enumerated() {
            row.isSelected = index == selectedIndex
        }
    }

    private func layoutRows() {
        let width = scrollView.contentView.bounds.width
        let rowHeight = max(46, style.rowHeight)
        let gap: CGFloat = 3
        var y: CGFloat = 0
        for row in rowViews {
            row.frame = NSRect(x: 0, y: y, width: width, height: rowHeight)
            y += rowHeight + gap
        }
        rowsContainer.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(scrollView.contentView.bounds.height, y)
        )
        scrollView.contentView.setBoundsOrigin(.zero)
    }
}

@MainActor
private final class InlineActionRowControl: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let badgeField = ActionBadgeField()
    private var style = LauncherVisualStyle.current
    var onSelect: (() -> Void)?
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.imageAlignment = .alignCenter
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.lineBreakMode = .byTruncatingTail
        subtitleField.lineBreakMode = .byTruncatingTail
        badgeField.layer?.cornerRadius = 7
        [iconView, titleField, subtitleField, badgeField].forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func layout() {
        super.layout()
        let rowInset: CGFloat = 18
        let iconSize: CGFloat = 22
        let badgeWidth: CGFloat = 68
        let titleHeight: CGFloat = 18
        let subtitleHeight: CGFloat = 15
        let textGap: CGFloat = 2
        let textStackHeight = titleHeight + textGap + subtitleHeight
        let textStackY = floor((bounds.height - textStackHeight) / 2)
        iconView.frame = NSRect(x: rowInset, y: floor((bounds.height - iconSize) / 2), width: iconSize, height: iconSize)
        badgeField.frame = NSRect(
            x: bounds.width - badgeWidth - rowInset,
            y: floor((bounds.height - 20) / 2),
            width: badgeWidth,
            height: 20
        )
        let textX = iconView.frame.maxX + 12
        let textWidth = max(80, badgeField.frame.minX - textX - 12)
        subtitleField.frame = NSRect(x: textX, y: textStackY, width: textWidth, height: subtitleHeight)
        titleField.frame = NSRect(
            x: textX,
            y: textStackY + subtitleHeight + textGap,
            width: textWidth,
            height: titleHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        style.primaryTextColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 4, dy: 2),
            xRadius: 10,
            yRadius: 10
        ).fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    func configure(_ item: InlineActionItem, style: LauncherVisualStyle) {
        titleField.stringValue = item.title
        subtitleField.stringValue = item.subtitle
        badgeField.stringValue = item.badge
        iconView.image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil)
        applyStyle(style)
    }

    func applyStyle(_ style: LauncherVisualStyle) {
        self.style = style
        titleField.font = .systemFont(ofSize: style.titleFontSize, weight: .medium)
        titleField.textColor = style.primaryTextColor
        subtitleField.font = .systemFont(ofSize: style.subtitleFontSize, weight: .regular)
        subtitleField.textColor = style.secondaryTextColor
        badgeField.font = .systemFont(ofSize: max(10, style.subtitleFontSize - 1), weight: .semibold)
        badgeField.textColor = style.secondaryTextColor
        badgeField.layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.07).cgColor
        badgeField.layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.10).cgColor
        badgeField.layer?.borderWidth = 1
        iconView.contentTintColor = style.secondaryTextColor
        needsLayout = true
        needsDisplay = true
    }
}

private final class FlippedRowsView: NSView {
    override var isFlipped: Bool { true }
}

final class ActionBadgeField: NSTextField {
    convenience init(text: String) {
        self.init(frame: .zero)
        stringValue = text
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ActionBadgeCell(textCell: "")
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        lineBreakMode = .byTruncatingTail
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }
}

private final class ActionBadgeCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        drawingRect.origin.y = rect.origin.y + floor((rect.height - textSize.height) / 2)
        drawingRect.size.height = textSize.height
        return drawingRect
    }
}
