import AppKit

@MainActor
final class ResultPreviewView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let kindField = ActionBadgeField()
    private let metadataField = NSTextField(wrappingLabelWithString: "")
    private let imagePreviewView = NSImageView()
    private let bodyScrollView = NSScrollView()
    private let bodyField = NSTextField(wrappingLabelWithString: "")
    private var hasImagePreview = false
    private var style = LauncherVisualStyle.current

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.borderWidth = 1

        iconView.imageAlignment = .alignCenter
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.lineBreakMode = .byTruncatingTail
        subtitleField.lineBreakMode = .byTruncatingTail
        kindField.alignment = .center
        kindField.lineBreakMode = .byTruncatingTail
        metadataField.lineBreakMode = .byWordWrapping
        metadataField.maximumNumberOfLines = 5
        imagePreviewView.imageAlignment = .alignCenter
        imagePreviewView.imageScaling = .scaleProportionallyUpOrDown
        imagePreviewView.isHidden = true
        imagePreviewView.wantsLayer = true
        imagePreviewView.layer?.cornerCurve = .continuous
        imagePreviewView.layer?.cornerRadius = 10
        imagePreviewView.layer?.masksToBounds = true
        bodyField.lineBreakMode = .byWordWrapping
        bodyField.maximumNumberOfLines = 0

        bodyScrollView.drawsBackground = false
        bodyScrollView.hasHorizontalScroller = false
        bodyScrollView.hasVerticalScroller = false
        bodyScrollView.contentView = NoHorizontalScrollClipView()
        bodyScrollView.documentView = bodyField

        [iconView, titleField, subtitleField, kindField, metadataField, imagePreviewView, bodyScrollView].forEach(addSubview)
        setAccessibilityIdentifier("vish.preview")
        setAccessibilityLabel("Preview")
        applyStyle(style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unsupported; vish UI is programmatic")
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        let iconSize = min(max(style.iconSize, 30), 42)
        let badgeWidth: CGFloat = 64
        iconView.frame = NSRect(x: inset, y: bounds.height - inset - iconSize, width: iconSize, height: iconSize)
        kindField.frame = NSRect(
            x: bounds.width - inset - badgeWidth,
            y: bounds.height - inset - 21,
            width: badgeWidth,
            height: 21
        )
        let textX = iconView.frame.maxX + 10
        titleField.frame = NSRect(
            x: textX,
            y: bounds.height - inset - 18,
            width: max(70, kindField.frame.minX - textX - 8),
            height: 18
        )
        subtitleField.frame = NSRect(
            x: textX,
            y: bounds.height - inset - 37,
            width: max(70, bounds.width - textX - inset),
            height: 15
        )
        metadataField.frame = NSRect(
            x: inset,
            y: max(0, bounds.height - 120),
            width: bounds.width - inset * 2,
            height: 56
        )

        if hasImagePreview {
            let messageHeight: CGFloat = 34
            bodyScrollView.frame = NSRect(
                x: inset,
                y: inset,
                width: bounds.width - inset * 2,
                height: messageHeight
            )
            imagePreviewView.frame = NSRect(
                x: inset,
                y: bodyScrollView.frame.maxY + 8,
                width: bounds.width - inset * 2,
                height: max(40, metadataField.frame.minY - bodyScrollView.frame.maxY - 16)
            )
        } else {
            imagePreviewView.frame = .zero
            bodyScrollView.frame = NSRect(
                x: inset,
                y: inset,
                width: bounds.width - inset * 2,
                height: max(0, metadataField.frame.minY - inset - 8)
            )
        }
        layoutBody()
    }

    func configure(_ preview: ResultPreview, result: SearchResult? = nil) {
        titleField.stringValue = preview.title
        subtitleField.stringValue = preview.subtitle
        kindField.stringValue = preview.kind
        metadataField.stringValue = preview.metadata
            .prefix(6)
            .map { "\($0.title): \($0.value)" }
            .joined(separator: "\n")
        bodyField.stringValue = preview.body.isEmpty ? "No preview available." : preview.body
        if let data = preview.imageData, let image = NSImage(data: data) {
            hasImagePreview = true
            imagePreviewView.image = image
            imagePreviewView.isHidden = false
            metadataField.maximumNumberOfLines = 4
        } else {
            hasImagePreview = false
            imagePreviewView.image = nil
            imagePreviewView.isHidden = true
            metadataField.maximumNumberOfLines = 5
        }
        iconView.image = icon(for: result)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func reset() {
        titleField.stringValue = ""
        subtitleField.stringValue = ""
        kindField.stringValue = ""
        metadataField.stringValue = ""
        bodyField.stringValue = ""
        iconView.image = nil
        imagePreviewView.image = nil
        imagePreviewView.isHidden = true
        hasImagePreview = false
    }

    func applyStyle(_ style: LauncherVisualStyle) {
        self.style = style
        layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.045).cgColor
        layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.08).cgColor
        titleField.font = .systemFont(ofSize: style.titleFontSize + 1, weight: .semibold)
        titleField.textColor = style.primaryTextColor
        subtitleField.font = .systemFont(ofSize: style.subtitleFontSize, weight: .regular)
        subtitleField.textColor = style.secondaryTextColor
        kindField.font = .systemFont(ofSize: max(10, style.subtitleFontSize - 1), weight: .semibold)
        kindField.textColor = style.secondaryTextColor
        kindField.layer?.cornerRadius = 7
        kindField.layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.07).cgColor
        kindField.layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.10).cgColor
        kindField.layer?.borderWidth = 1
        metadataField.font = .monospacedSystemFont(ofSize: max(10, style.subtitleFontSize - 1), weight: .medium)
        metadataField.textColor = style.secondaryTextColor
        imagePreviewView.layer?.backgroundColor = style.primaryTextColor.withAlphaComponent(0.05).cgColor
        imagePreviewView.layer?.borderColor = style.primaryTextColor.withAlphaComponent(0.08).cgColor
        imagePreviewView.layer?.borderWidth = 1
        bodyField.font = .systemFont(ofSize: style.subtitleFontSize + 0.5, weight: .regular)
        bodyField.textColor = style.primaryTextColor.withAlphaComponent(0.86)
        needsLayout = true
    }

    private func layoutBody() {
        let width = bodyScrollView.contentView.bounds.width
        let fitting = bodyField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)) ?? .zero
        bodyField.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(bodyScrollView.contentView.bounds.height, fitting.height + 8)
        )
        bodyScrollView.contentView.setBoundsOrigin(.zero)
    }

    private func icon(for result: SearchResult?) -> NSImage? {
        guard let result else { return NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil) }
        if let url = ResultActionExecutor.localURL(for: result.action) {
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: style.iconSize, height: style.iconSize)
            return image
        }
        let name = switch result.kind {
        case .ai:
            "sparkles"
        case .app:
            "app"
        case .calculator:
            "function"
        case .clipboard:
            "doc.on.clipboard"
        case .file:
            "doc"
        case .quicklink:
            "link"
        case .snippet:
            "text.quote"
        case .system:
            "gearshape"
        case .url, .web:
            "globe"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: style.iconSize, height: style.iconSize)
        return image
    }
}
