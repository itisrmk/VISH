import AppKit

private final class CenteredBadgeField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = CenteredTextFieldCell(textCell: "")
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

private final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        drawingRect.origin.y = rect.origin.y + floor((rect.height - textSize.height) / 2)
        drawingRect.size.height = textSize.height
        return drawingRect
    }
}

@MainActor
final class ResultCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultCellView")
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let kindField = CenteredBadgeField()
    private let shortcutField = NSTextField(labelWithString: "")
    private var style = LauncherVisualStyle.current
    private var representedResultID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        iconView.imageAlignment = .alignCenter
        iconView.imageScaling = .scaleProportionallyUpOrDown

        applyStyle(style)
        kindField.layer?.cornerRadius = 7
        shortcutField.alignment = .right
        titleField.lineBreakMode = .byTruncatingTail
        subtitleField.lineBreakMode = .byTruncatingTail

        addSubview(iconView)
        addSubview(titleField)
        addSubview(subtitleField)
        addSubview(kindField)
        addSubview(shortcutField)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func layout() {
        super.layout()
        let iconSize = style.iconSize
        let iconX: CGFloat = 13
        let textX = max(60, iconX + iconSize + 13)
        let trailingInset: CGFloat = 30
        let shortcutWidth: CGFloat = 34
        let kindTextWidth = (kindField.stringValue as NSString).size(withAttributes: [.font: kindField.font ?? NSFont.systemFont(ofSize: 11)]).width
        let kindWidth = min(64, max(48, ceil(kindTextWidth + 22)))
        let kindHeight: CGFloat = 20
        let showsShortcut = bounds.width >= 360 && !shortcutField.stringValue.isEmpty
        let shortcutX = bounds.width - shortcutWidth - trailingInset
        let kindX = showsShortcut ? shortcutX - kindWidth - 8 : bounds.width - kindWidth - trailingInset
        let textWidth = max(24, kindX - textX - 10)
        iconView.frame = NSRect(x: iconX, y: floor((bounds.height - iconSize) / 2), width: iconSize, height: iconSize)
        titleField.frame = NSRect(x: textX, y: bounds.height - 25, width: textWidth, height: 18)
        subtitleField.frame = NSRect(x: textX, y: 8, width: textWidth, height: 15)
        kindField.frame = NSRect(x: kindX, y: floor((bounds.height - kindHeight) / 2), width: kindWidth, height: kindHeight)
        shortcutField.isHidden = !showsShortcut
        shortcutField.frame = NSRect(x: shortcutX, y: floor((bounds.height - 16) / 2), width: shortcutWidth, height: 16)
    }

    func configure(with result: SearchResult, index: Int) {
        applyStyle(LauncherVisualStyle.current)
        representedResultID = result.id
        iconView.image = ResultIconProvider.cachedIcon(for: result)
        ResultIconProvider.loadIconIfNeeded(for: result) { [weak self] resultID, image in
            guard self?.representedResultID == resultID else { return }
            self?.iconView.image = image
        }
        titleField.stringValue = result.title
        subtitleField.stringValue = result.subtitle
        kindField.stringValue = result.kind.rawValue
        shortcutField.stringValue = index < 9 ? "⌘\(index + 1)" : ""
        setAccessibilityLabel("\(result.title). \(result.subtitle). \(result.kind.rawValue).")
        setAccessibilityHelp("\(index < 9 ? "Command \(index + 1). " : "")Press Return to \(Self.accessibilityAction(for: result)). Press Tab for actions.")
    }

    private func applyStyle(_ style: LauncherVisualStyle) {
        self.style = style
        titleField.font = .systemFont(ofSize: style.titleFontSize, weight: .medium)
        titleField.textColor = style.primaryTextColor
        subtitleField.font = .systemFont(ofSize: style.subtitleFontSize, weight: .regular)
        subtitleField.textColor = style.secondaryTextColor
        kindField.font = .systemFont(ofSize: max(10, style.subtitleFontSize - 1), weight: .semibold)
        kindField.textColor = style.secondaryTextColor
        kindField.layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.07).cgColor
        kindField.layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.10).cgColor
        kindField.layer?.borderWidth = 1
        shortcutField.font = .systemFont(ofSize: 12, weight: .medium)
        shortcutField.textColor = style.tertiaryTextColor
    }

    private static func accessibilityAction(for result: SearchResult) -> String {
        switch result.action {
        case .askAI:
            return "ask"
        case .copy:
            return "copy"
        case .openApplication, .openFile, .openURL:
            return "open"
        case .pasteClipboard, .pasteSnippet:
            return "paste"
        case .revealFile:
            return "reveal"
        case .system:
            return "run"
        }
    }
}

@MainActor
private enum ResultIconProvider {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    private static var pending: [NSURL: [(NSImage) -> Void]] = [:]

    static func cachedIcon(for result: SearchResult) -> NSImage? {
        if let image = QuicklinkIconRenderer.image(for: result.icon, size: LauncherVisualStyle.current.iconSize) {
            return image
        }

        switch result.action {
        case .askAI:
            return symbol("sparkle.magnifyingglass")
        case .openApplication(let url), .openFile(let url), .revealFile(let url):
            if let cached = cache.object(forKey: url as NSURL) {
                return sized(cached, size: LauncherVisualStyle.current.iconSize)
            }
            return symbol(result.kind == .app ? "app" : "doc")
        case .openURL:
            return symbol("globe")
        case .pasteClipboard:
            return symbol("doc.on.clipboard")
        case .pasteSnippet:
            return symbol("text.quote")
        case .copy:
            return symbol("function")
        case .system(let action):
            return symbol(symbolName(for: action))
        }
    }

    static func loadIconIfNeeded(
        for result: SearchResult,
        completion: @escaping (String, NSImage) -> Void
    ) {
        guard let url = fileURL(for: result) else { return }
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            completion(result.id, sized(cached, size: LauncherVisualStyle.current.iconSize))
            return
        }

        pending[key, default: []].append { image in
            completion(result.id, image)
        }
        guard pending[key]?.count == 1 else { return }

        let path = url.path
        let size = LauncherVisualStyle.current.iconSize
        Task.detached(priority: .utility) {
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: size, height: size)
            await MainActor.run {
                let cacheKey = NSURL(fileURLWithPath: path)
                cache.setObject(image, forKey: cacheKey, cost: max(1, Int(size * size * 4)))
                let completions = pending.removeValue(forKey: cacheKey) ?? []
                completions.forEach { $0(image) }
            }
        }
    }

    private static func symbolName(for action: SystemAction) -> String {
        switch action {
        case .emptyTrash:
            return "trash"
        case .ejectDisks:
            return "eject"
        case .hideHiddenFiles:
            return "eye.slash"
        case .lockScreen:
            return "lock"
        case .logOut:
            return "rectangle.portrait.and.arrow.right"
        case .restart:
            return "arrow.clockwise"
        case .showHiddenFiles:
            return "eye"
        case .shutDown:
            return "power"
        case .sleep:
            return "moon"
        case .toggleDarkMode:
            return "circle.lefthalf.filled"
        }
    }

    private static func fileURL(for result: SearchResult) -> URL? {
        switch result.action {
        case .openApplication(let url), .openFile(let url), .revealFile(let url):
            return url
        case .askAI, .openURL, .copy, .pasteClipboard, .pasteSnippet, .system:
            return nil
        }
    }

    private static func sized(_ image: NSImage, size: CGFloat) -> NSImage {
        image.size = NSSize(width: size, height: size)
        return image
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 20, height: 20)
        return image
    }
}
