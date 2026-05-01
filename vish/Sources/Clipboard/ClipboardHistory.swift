import AppKit

struct ClipboardHistorySource {
    func search(_ query: String, limit: Int) async -> [SearchResult] {
        guard LauncherPreferences.clipboardHistoryEnabled else { return [] }
        return await ClipboardHistoryStore.shared.search(query, limit: limit)
    }
}

actor ClipboardHistoryStore {
    static let shared = ClipboardHistoryStore()

    private let historyURL: URL
    private var items: [ClipboardHistoryItem]?

    private init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        historyURL = base
            .appendingPathComponent("vish", isDirectory: true)
            .appendingPathComponent("clipboard.plist")
    }

    func record(_ value: String, source: ClipboardCaptureSource? = nil) {
        guard let text = ClipboardHistoryItem.clean(value) else { return }
        let id = ClipboardHistoryItem.id(for: text)
        let now = Date()
        var current = normalizedItems()
        let existing = current.first { $0.id == id }
        current.removeAll { $0.id == id }
        current.append(.init(
            id: id,
            text: text,
            copiedAt: now,
            updatedAt: existing?.updatedAt ?? now,
            pinned: existing?.pinned ?? false,
            sourceBundleID: source?.bundleID ?? existing?.sourceBundleID,
            sourceName: source?.name ?? existing?.sourceName
        ))
        persist(sortedAndTrimmed(current))
    }

    func search(_ query: String, limit: Int) -> [SearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current = normalizedItems()
        guard !current.isEmpty else { return [] }

        var results: [SearchResult] = []
        results.reserveCapacity(min(limit, current.count))

        for (index, item) in current.enumerated() {
            let score: Double
            if normalized.isEmpty {
                score = max(0.55, 0.96 - Double(index) * 0.01)
            } else if let match = FuzzyMatcher.score(query: normalized, candidate: item.searchText) {
                score = min(0.99, match * 0.95 + max(0, 0.04 - Double(index) * 0.001))
            } else {
                continue
            }

            results.append(SearchResult(
                id: "clipboard:\(item.id)",
                kind: .clipboard,
                title: item.title,
                subtitle: item.subtitle,
                score: score,
                icon: item.pinned ? .symbol("pin.fill") : nil,
                action: .pasteClipboard(item.text)
            ))
        }

        results.sort { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    func clear() {
        items = []
        try? FileManager.default.removeItem(at: historyURL)
    }

    func clearUnpinned() {
        persist(normalizedItems().filter(\.pinned))
    }

    func delete(id: String) {
        persist(normalizedItems().filter { $0.id != id })
    }

    func setPinned(id: String, pinned: Bool) {
        persist(sortedAndTrimmed(normalizedItems().map { item in
            guard item.id == id else { return item }
            return item.withPinned(pinned)
        }))
    }

    func togglePinned(id: String) {
        persist(sortedAndTrimmed(normalizedItems().map { item in
            guard item.id == id else { return item }
            return item.withPinned(!item.pinned)
        }))
    }

    func update(id: String, text: String) {
        guard let cleaned = ClipboardHistoryItem.clean(text) else { return }
        let newID = ClipboardHistoryItem.id(for: cleaned)
        let now = Date()
        var current = normalizedItems()
        guard let old = current.first(where: { $0.id == id }) else { return }
        current.removeAll { $0.id == id || $0.id == newID }
        current.append(.init(
            id: newID,
            text: cleaned,
            copiedAt: old.copiedAt,
            updatedAt: now,
            pinned: old.pinned,
            sourceBundleID: old.sourceBundleID,
            sourceName: old.sourceName
        ))
        persist(sortedAndTrimmed(current))
    }

    func summaries(limit: Int = 40) -> [ClipboardHistorySummary] {
        normalizedItems().prefix(limit).map(\.summary)
    }

    func stats() -> ClipboardHistoryStats {
        let current = normalizedItems()
        let attributes = try? FileManager.default.attributesOfItem(atPath: historyURL.path)
        let byteSize = attributes?[.size] as? Int64 ?? 0
        return ClipboardHistoryStats(
            count: current.count,
            pinnedCount: current.filter(\.pinned).count,
            byteSize: byteSize,
            retentionDays: LauncherPreferences.clipboardRetentionDays,
            lastCopiedAt: current.first?.copiedAt,
            historyPath: historyURL.path
        )
    }

    private func loadItems() -> [ClipboardHistoryItem] {
        if let items {
            return items
        }

        let loaded = StorageCodec.load([ClipboardHistoryItem].self, from: historyURL, default: [])
        items = loaded
        return loaded
    }

    private func normalizedItems() -> [ClipboardHistoryItem] {
        let current = loadItems()
        let normalized = sortedAndTrimmed(pruneExpired(current))
        if normalized != current {
            persist(normalized)
        }
        return normalized
    }

    private func pruneExpired(_ current: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        let days = LauncherPreferences.clipboardRetentionDays
        guard days > 0 else { return current }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return current.filter { $0.pinned || $0.copiedAt >= cutoff }
    }

    private func sortedAndTrimmed(_ current: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        var sorted = current.sorted { left, right in
            if left.pinned != right.pinned { return left.pinned }
            return left.copiedAt > right.copiedAt
        }
        if sorted.count > ClipboardHistoryItem.maxItems {
            sorted.removeSubrange(ClipboardHistoryItem.maxItems..<sorted.count)
        }
        return sorted
    }

    private func persist(_ current: [ClipboardHistoryItem]) {
        items = current
        if current.isEmpty {
            try? FileManager.default.removeItem(at: historyURL)
        } else {
            try? StorageCodec.save(current, to: historyURL)
        }
    }
}

@MainActor
final class ClipboardHistoryMonitor {
    private let store: ClipboardHistoryStore
    private var timer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(store: ClipboardHistoryStore = .shared) {
        self.store = store
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncEnabledState()
            }
        }
        syncEnabledState()
    }

    private func syncEnabledState() {
        LauncherPreferences.clipboardHistoryEnabled ? start() : stop()
    }

    private func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        captureCurrentPasteboard()

        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.75
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        captureCurrentPasteboard()
    }

    private func captureCurrentPasteboard() {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let bundleID = sourceApp?.bundleIdentifier
        if let bundleID, LauncherPreferences.clipboardDisabledAppIDs.contains(bundleID) {
            return
        }
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        let store = store
        let source = ClipboardCaptureSource(bundleID: bundleID, name: sourceApp?.localizedName)
        Task.detached(priority: .utility) {
            await store.record(value, source: source)
        }
    }
}

struct ClipboardCaptureSource: Sendable {
    let bundleID: String?
    let name: String?
}

struct ClipboardHistorySummary: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let text: String
    let pinned: Bool
    let sourceBundleID: String?
    let sourceName: String
    let copiedAt: Date
}

struct ClipboardHistoryStats: Sendable {
    static let empty = ClipboardHistoryStats(
        count: 0,
        pinnedCount: 0,
        byteSize: 0,
        retentionDays: ClipboardRetentionOption.default.rawValue,
        lastCopiedAt: nil,
        historyPath: ""
    )

    let count: Int
    let pinnedCount: Int
    let byteSize: Int64
    let retentionDays: Int
    let lastCopiedAt: Date?
    let historyPath: String

    var byteSizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var retentionText: String {
        ClipboardRetentionOption(rawValue: retentionDays)?.displayName ?? ClipboardRetentionOption.default.displayName
    }
}

private struct ClipboardHistoryItem: Codable, Sendable, Identifiable, Equatable {
    static let maxItems = 100
    private static let maxCharacters = 50_000

    let id: String
    let text: String
    let copiedAt: Date
    let updatedAt: Date
    let pinned: Bool
    let sourceBundleID: String?
    let sourceName: String?

    init(
        id: String,
        text: String,
        copiedAt: Date,
        updatedAt: Date,
        pinned: Bool,
        sourceBundleID: String?,
        sourceName: String?
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case copiedAt
        case updatedAt
        case pinned
        case sourceBundleID
        case sourceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? copiedAt
        pinned = (try? container.decode(Bool.self, forKey: .pinned)) ?? false
        sourceBundleID = try? container.decode(String.self, forKey: .sourceBundleID)
        sourceName = try? container.decode(String.self, forKey: .sourceName)
    }

    var searchText: String {
        "\(text) \(sourceName ?? "")".lowercased()
    }

    var title: String {
        let value = flattened
        guard value.count > 72 else { return value }
        return "\(value.prefix(72))..."
    }

    var subtitle: String {
        let lineCount = text.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
        let size = lineCount > 1 ? "\(lineCount) lines" : "\(text.count) chars"
        let source = sourceName.map { " · \($0)" } ?? ""
        return "\(pinned ? "Pinned · " : "")\(size) · \(ageText)\(source)"
    }

    var summary: ClipboardHistorySummary {
        ClipboardHistorySummary(
            id: id,
            title: title,
            subtitle: subtitle,
            text: text,
            pinned: pinned,
            sourceBundleID: sourceBundleID,
            sourceName: sourceName ?? "Unknown app",
            copiedAt: copiedAt
        )
    }

    static func clean(_ value: String) -> String? {
        guard value.count <= maxCharacters else { return nil }
        let text = value.replacingOccurrences(of: "\u{0000}", with: "")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    static func id(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    func withPinned(_ value: Bool) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            text: text,
            copiedAt: copiedAt,
            updatedAt: Date(),
            pinned: value,
            sourceBundleID: sourceBundleID,
            sourceName: sourceName
        )
    }

    private var flattened: String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ageText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(copiedAt)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
