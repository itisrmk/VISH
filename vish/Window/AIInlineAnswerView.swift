import AppKit

@MainActor
final class AIInlineAnswerView: NSView {
    private let titleField = NSTextField(labelWithString: "Local AI")
    private let statusField = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var style = LauncherVisualStyle.current

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.borderWidth = 1

        titleField.lineBreakMode = .byTruncatingTail
        statusField.alignment = .right
        statusField.lineBreakMode = .byTruncatingTail

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        scrollView.drawsBackground = false
        scrollView.contentView = NoHorizontalScrollClipView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = textView

        [titleField, statusField, scrollView].forEach(addSubview)
        setAccessibilityIdentifier("vish.ai.answer")
        setAccessibilityLabel("Local AI answer")
        applyStyle(style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        let headerHeight: CGFloat = 26
        let statusWidth = min(bounds.width * 0.35, 160)
        titleField.frame = NSRect(
            x: inset,
            y: bounds.height - headerHeight - 8,
            width: bounds.width - inset * 2 - statusWidth,
            height: headerHeight
        )
        statusField.frame = NSRect(
            x: bounds.width - inset - statusWidth,
            y: titleField.frame.minY,
            width: statusWidth,
            height: headerHeight
        )
        scrollView.frame = NSRect(
            x: 8,
            y: 8,
            width: bounds.width - 16,
            height: max(0, titleField.frame.minY - 8)
        )
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: scrollView.contentView.bounds.width,
            height: max(scrollView.contentView.bounds.height, textView.frame.height)
        )
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentView.bounds.width,
            height: .greatestFiniteMagnitude
        )
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
    }

    func applyStyle(_ style: LauncherVisualStyle) {
        self.style = style
        layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.045).cgColor
        layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.08).cgColor

        titleField.font = .systemFont(ofSize: style.titleFontSize + 1, weight: .semibold)
        titleField.textColor = style.primaryTextColor
        statusField.font = .systemFont(ofSize: max(11, style.subtitleFontSize), weight: .medium)
        statusField.textColor = style.tertiaryTextColor
        textView.font = .systemFont(ofSize: style.titleFontSize, weight: .regular)
        textView.textColor = style.primaryTextColor
        needsLayout = true
    }

    func begin(title: String = "Local AI", status: String = "Thinking") {
        titleField.stringValue = title
        statusField.stringValue = status
        textView.string = ""
    }

    func append(_ chunk: String) {
        textView.textStorage?.append(NSAttributedString(string: chunk, attributes: [
            .font: NSFont.systemFont(ofSize: style.titleFontSize, weight: .regular),
            .foregroundColor: style.primaryTextColor
        ]))
        textView.scrollToEndOfDocument(nil)
    }

    func finish(_ status: String) {
        statusField.stringValue = status
    }

    func showMessage(_ message: String, status: String) {
        begin()
        append(message)
        finish(status)
    }

    func reset() {
        statusField.stringValue = ""
        textView.string = ""
    }
}
