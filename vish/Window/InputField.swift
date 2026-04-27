import AppKit

@MainActor
final class InputField: NSTextField, NSTextFieldDelegate {
    var onTextChange: ((String) -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onActivateSelection: (() -> Void)?
    var onRevealSelection: (() -> Void)?
    var onSearchWeb: (() -> Void)?
    var onShowActions: (() -> Void)?
    var onQuickLookSelection: (() -> Void)?
    var onShowDetails: (() -> Void)?
    var onToggleBuffer: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        cell = VerticallyCenteredTextFieldCell(textCell: "")
        action = #selector(commit)
        backgroundColor = .clear
        delegate = self
        drawsBackground = false
        focusRingType = .none
        let fieldFont = NSFont.systemFont(ofSize: 21, weight: .regular)
        font = fieldFont
        isBezeled = false
        isBordered = false
        isEditable = true
        isEnabled = true
        isSelectable = true
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        textColor = NSColor.white.withAlphaComponent(0.96)
        placeholderAttributedString = NSAttributedString(
            string: "",
            attributes: [
                .font: fieldFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.38)
            ]
        )
        cell?.isScrollable = true
        cell?.isEditable = true
        cell?.isSelectable = true
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        setAccessibilityIdentifier("vish.search")
        setAccessibilityLabel("Search")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override var acceptsFirstResponder: Bool { true }

    func applyStyle(_ style: LauncherVisualStyle) {
        let fieldFont = NSFont.systemFont(ofSize: style.inputFontSize, weight: .regular)
        font = fieldFont
        textColor = style.primaryTextColor
        setPlaceholder("", font: fieldFont, color: style.tertiaryTextColor)
    }

    func setPlaceholder(_ value: String) {
        setPlaceholder(value, font: font ?? .systemFont(ofSize: LauncherVisualStyle.current.inputFontSize), color: LauncherVisualStyle.current.tertiaryTextColor)
    }

    func setText(_ value: String) {
        stringValue = value
        guard let editor = currentEditor() else { return }
        editor.string = value
        editor.selectedRange = NSRange(location: value.utf16.count, length: 0)
    }

    private func setPlaceholder(_ value: String, font: NSFont, color: NSColor) {
        placeholderAttributedString = NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        PerformanceProbe.beginKeystrokeToRender()
        onTextChange?(stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(insertNewline(_:)):
            onActivateSelection?()
        case #selector(cancelOperation(_:)):
            onCancel?()
        case #selector(moveUp(_:)):
            onMoveSelection?(-1)
        case #selector(moveDown(_:)):
            onMoveSelection?(1)
        case #selector(insertTab(_:)):
            onShowActions?()
        default:
            return false
        }

        return true
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyCommand(event) {
            return
        }

        super.keyDown(with: event)
    }

    @discardableResult
    func handleKeyCommand(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 36, 76:
            if modifiers.contains(.command) {
                onRevealSelection?()
                return true
            }
            if modifiers.contains(.control) {
                onSearchWeb?()
                return true
            }
            onActivateSelection?()
        case 53:
            onCancel?()
        case 31 where modifiers.contains(.command):
            onActivateSelection?()
        case 44 where modifiers.contains(.command):
            onShowActions?()
        case 40 where modifiers.contains(.command):
            onShowActions?()
        case 16 where modifiers.contains(.command):
            onQuickLookSelection?()
        case 34 where modifiers.contains(.command):
            onShowDetails?()
        case 11 where modifiers.contains(.command):
            onToggleBuffer?()
        case 43 where modifiers.contains(.command):
            onOpenSettings?()
        case 48:
            onShowActions?()
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        default:
            if event.modifierFlags.contains(.command), let index = Self.commandNumberIndex(event) {
                onMoveSelection?(index - 1_000)
                onActivateSelection?()
                return true
            }

            return false
        }

        return true
    }

    @objc private func commit() {
        onActivateSelection?()
    }

    private static func commandNumberIndex(_ event: NSEvent) -> Int? {
        guard let key = event.charactersIgnoringModifiers?.first else { return nil }
        guard let value = key.wholeNumberValue, (1...9).contains(value) else { return nil }
        return value - 1
    }
}

@MainActor
private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(in: super.drawingRect(forBounds: rect), bounds: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredRect(in: super.drawingRect(forBounds: rect), bounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredRect(in: super.drawingRect(forBounds: rect), bounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func centeredRect(in rect: NSRect, bounds: NSRect) -> NSRect {
        var centered = rect
        centered.size.height = min(cellSize(forBounds: bounds).height, bounds.height)
        centered.origin.y = bounds.origin.y + floor((bounds.height - centered.height) / 2)
        return centered
    }
}
