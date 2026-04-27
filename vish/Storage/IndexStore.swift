import Foundation

actor IndexStore {
    static let shared = IndexStore()

    private let appCatalogURL: URL
    private let frecencyURL: URL
    private let legacyAppCatalogURL: URL
    private let legacyFrecencyURL: URL
    private var frecency: [String: FrecencyRecord]?

    private init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("vish", isDirectory: true)
        appCatalogURL = directory.appendingPathComponent("apps.plist")
        frecencyURL = directory.appendingPathComponent("frecency.plist")
        legacyAppCatalogURL = directory.appendingPathComponent("apps.json")
        legacyFrecencyURL = directory.appendingPathComponent("frecency.json")
    }

    func loadApps() -> [AppRecord] {
        StorageCodec.load([AppRecord].self, from: appCatalogURL, legacyJSONURL: legacyAppCatalogURL, default: [])
    }

    func saveApps(_ apps: [AppRecord]) {
        try? StorageCodec.save(apps, to: appCatalogURL)
    }

    func recordActivation(_ result: SearchResult) {
        guard let item = IndexedItem(result) else { return }
        var records = loadFrecency()
        var record = records[item.key] ?? FrecencyRecord(item: item)
        record.item = item
        record.useCount += 1
        record.lastUsedAt = Date()
        records[item.key] = record
        frecency = records
        saveFrecency(records)
    }

    func frecencyResults(matching query: String, limit: Int) -> [SearchResult] {
        let normalized = query.lowercased()
        guard !normalized.isEmpty else { return [] }

        var results: [SearchResult] = []
        results.reserveCapacity(limit)

        for record in loadFrecency().values {
            guard let result = record.item.searchResult(score: record.score) else { continue }
            let haystack = "\(result.title) \(result.subtitle)".lowercased()
            guard let matchScore = FuzzyMatcher.score(query: normalized, candidate: haystack) else { continue }
            results.append(result.withScore(0.85 * matchScore + min(record.score, 5) * 0.08))
        }

        results.sort { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    func ranked(_ results: [SearchResult], limit: Int) -> [SearchResult] {
        let records = loadFrecency()
        let boosted = results.map { result in
            guard let record = records[IndexedItem.key(for: result)] else { return result }
            return result.withScore(result.score * (1 + min(record.score, 5) * 0.1))
        }

        return Array(boosted
            .sorted { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
            .prefix(limit))
    }

    private func loadFrecency() -> [String: FrecencyRecord] {
        if let frecency {
            return frecency
        }

        let records = StorageCodec.load(
            [String: FrecencyRecord].self,
            from: frecencyURL,
            legacyJSONURL: legacyFrecencyURL,
            default: [:]
        )
        frecency = records
        return records
    }

    private func saveFrecency(_ records: [String: FrecencyRecord]) {
        try? StorageCodec.save(records, to: frecencyURL)
    }
}

private struct FrecencyRecord: Codable, Sendable {
    var item: IndexedItem
    var useCount: Int
    var lastUsedAt: Date

    init(item: IndexedItem) {
        self.item = item
        useCount = 0
        lastUsedAt = .distantPast
    }

    var score: Double {
        let halfLife = 14.0 * 24.0 * 60.0 * 60.0
        let age = max(0, Date().timeIntervalSince(lastUsedAt))
        return Double(useCount) * exp(-age / halfLife)
    }
}

private struct IndexedItem: Codable, Sendable {
    enum ActionKind: String, Codable, Sendable {
        case app
        case copy
        case file
        case reveal
        case url
    }

    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let actionKind: ActionKind
    let payload: String

    var key: String {
        "\(kind.rawValue):\(id)"
    }

    init?(_ result: SearchResult) {
        guard result.kind != .clipboard, result.kind != .snippet else { return nil }

        id = result.id
        kind = result.kind
        title = result.title
        subtitle = result.subtitle

        switch result.action {
        case .askAI:
            return nil
        case .copy(let value):
            actionKind = .copy
            payload = value
        case .openApplication(let url):
            actionKind = .app
            payload = url.path
        case .openFile(let url):
            actionKind = .file
            payload = url.path
        case .openURL(let url):
            actionKind = .url
            payload = url.absoluteString
        case .pasteClipboard, .pasteSnippet:
            return nil
        case .revealFile(let url):
            actionKind = .reveal
            payload = url.path
        case .system:
            return nil
        }
    }

    static func key(for result: SearchResult) -> String {
        "\(result.kind.rawValue):\(result.id)"
    }

    func searchResult(score: Double) -> SearchResult? {
        let action: ResultAction

        switch actionKind {
        case .app:
            action = .openApplication(URL(fileURLWithPath: payload))
        case .copy:
            action = .copy(payload)
        case .file:
            action = .openFile(URL(fileURLWithPath: payload))
        case .reveal:
            action = .revealFile(URL(fileURLWithPath: payload))
        case .url:
            guard let url = URL(string: payload) else { return nil }
            action = .openURL(url)
        }

        return SearchResult(id: id, kind: kind, title: title, subtitle: subtitle, score: score, action: action)
    }
}

extension SearchResult {
    func withScore(_ score: Double) -> SearchResult {
        SearchResult(id: id, kind: kind, title: title, subtitle: subtitle, score: score, icon: icon, action: action)
    }
}

enum StorageCodec {
    static func load<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        legacyJSONURL: URL? = nil,
        default defaultValue: @autoclosure () -> T
    ) -> T {
        if let data = try? Data(contentsOf: url),
           let value = try? PropertyListDecoder().decode(type, from: data) {
            return value
        }

        if let legacyJSONURL,
           let data = try? Data(contentsOf: legacyJSONURL),
           let value = try? JSONDecoder().decode(type, from: data) {
            return value
        }

        return defaultValue()
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
