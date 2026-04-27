import AppKit
import UniformTypeIdentifiers

@MainActor
final class QuicklinkSettingsModel: ObservableObject {
    @Published private(set) var items: [QuicklinkRecord] = []
    @Published var selectedID: String?
    @Published var keyword = ""
    @Published var name = ""
    @Published var urlTemplate = ""
    @Published var iconName: QuicklinkIconKind?
    @Published var customIconData: Data?

    var canSave: Bool {
        QuicklinkRecord.normalizedKeyword(keyword) != nil
            && QuicklinkRecord.cleanedName(name) != nil
            && QuicklinkRecord.cleanedURLTemplate(urlTemplate) != nil
            && (customIconData?.count ?? 0) <= QuicklinkRecord.maxIconDataBytes
    }

    var previewIcon: ResultIcon? {
        if let customIconData {
            return .imageData(customIconData)
        }
        if let iconName {
            return .quicklink(iconName)
        }
        guard let normalizedKeyword = QuicklinkRecord.normalizedKeyword(keyword),
              let template = QuicklinkRecord.cleanedURLTemplate(urlTemplate),
              let inferred = QuicklinkIconKind.defaultIcon(keyword: normalizedKeyword, urlTemplate: template)
        else { return nil }
        return .quicklink(inferred)
    }

    func load() {
        Task {
            let loaded = await QuicklinkStore.shared.list()
            items = loaded
            if let selectedID, let selected = loaded.first(where: { $0.id == selectedID }) {
                select(selected)
            } else if selectedID == nil, let first = loaded.first {
                select(first)
            }
        }
    }

    func select(_ item: QuicklinkRecord) {
        selectedID = item.id
        keyword = item.keyword
        name = item.name
        urlTemplate = item.urlTemplate
        iconName = item.iconName
        customIconData = item.customIconData
    }

    func new() {
        selectedID = nil
        keyword = ""
        name = ""
        urlTemplate = ""
        iconName = nil
        customIconData = nil
    }

    func useStarter(_ item: QuicklinkRecord) {
        selectedID = nil
        keyword = item.keyword
        name = item.name
        urlTemplate = item.urlTemplate
        iconName = item.iconName
        customIconData = item.customIconData
    }

    func insertQueryToken() {
        guard !urlTemplate.contains("{query}") else { return }
        urlTemplate += "{query}"
    }

    func save() {
        let id = selectedID
        let keyword = keyword
        let name = name
        let template = urlTemplate
        let iconName = iconName
        let iconData = customIconData
        Task {
            guard let saved = await QuicklinkStore.shared.upsert(
                id: id,
                keyword: keyword,
                name: name,
                urlTemplate: template,
                iconName: iconName,
                customIconData: iconData
            ) else { return }
            items = await QuicklinkStore.shared.list()
            if let selected = items.first(where: { $0.id == saved.id }) {
                select(selected)
            }
        }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        Task {
            await QuicklinkStore.shared.delete(id: id)
            items = await QuicklinkStore.shared.list()
            if let first = items.first {
                select(first)
            } else {
                new()
            }
        }
    }

    func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = Self.normalizedIconData(from: url)
        else { return }
        customIconData = data
        iconName = nil
    }

    func clearCustomIcon() {
        customIconData = nil
        if let normalizedKeyword = QuicklinkRecord.normalizedKeyword(keyword),
           let template = QuicklinkRecord.cleanedURLTemplate(urlTemplate) {
            iconName = QuicklinkIconKind.defaultIcon(keyword: normalizedKeyword, urlTemplate: template)
        } else {
            iconName = nil
        }
    }

    private static func normalizedIconData(from url: URL) -> Data? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        let size = CGFloat(96)
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let scale = min(size / sourceSize.width, size / sourceSize.height)
        let fitted = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let target = NSImage(size: NSSize(width: size, height: size))
        target.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: (size - fitted.width) / 2, y: (size - fitted.height) / 2, width: fitted.width, height: fitted.height),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1
        )
        target.unlockFocus()

        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= QuicklinkRecord.maxIconDataBytes
        else { return nil }
        return png
    }
}
