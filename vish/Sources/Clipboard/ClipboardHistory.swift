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

    func record(_ value: String) {
        guard let text = ClipboardHistoryItem.clean(value) else { return }
        let id = ClipboardHistoryItem.id(for: text)
        var current = loadItems().filter { $0.id != id }
        current.insert(.init(id: id, text: text, copiedAt: Date()), at: 0)
        if current.count > ClipboardHistoryItem.maxItems {
            current.removeSubrange(ClipboardHistoryItem.maxItems..<current.count)
        }
        items = current
        try? StorageCodec.save(current, to: historyURL)
    }

    func search(_ query: String, limit: Int) -> [SearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current = loadItems()
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

    private func loadItems() -> [ClipboardHistoryItem] {
        if let items {
            return items
        }

        let loaded = StorageCodec.load([ClipboardHistoryItem].self, from: historyURL, default: [])
        items = loaded
        return loaded
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

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.5
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
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        let store = store
        Task.detached(priority: .utility) {
            await store.record(value)
        }
    }
}

private struct ClipboardHistoryItem: Codable, Sendable, Identifiable {
    static let maxItems = 100
    private static let maxCharacters = 50_000

    let id: String
    let text: String
    let copiedAt: Date

    var searchText: String {
        text.lowercased()
    }

    var title: String {
        let value = flattened
        guard value.count > 72 else { return value }
        return "\(value.prefix(72))..."
    }

    var subtitle: String {
        let lineCount = text.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
        let size = lineCount > 1 ? "\(lineCount) lines" : "\(text.count) chars"
        return "\(size) - \(ageText)"
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
