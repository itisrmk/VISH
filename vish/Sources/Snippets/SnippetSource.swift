import Foundation

struct SnippetSource {
    func search(_ query: String, limit: Int) async -> [SearchResult] {
        await SnippetStore.shared.search(query, limit: limit)
    }
}

actor SnippetStore {
    static let shared = SnippetStore()

    private let snippetsURL: URL
    private var snippets: [SnippetRecord]?

    private init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        snippetsURL = base
            .appendingPathComponent("vish", isDirectory: true)
            .appendingPathComponent("snippets.plist")
    }

    func list() -> [SnippetRecord] {
        sorted(loadSnippets())
    }

    func record(id: String) -> SnippetRecord? {
        loadSnippets().first { $0.id == id }
    }

    @discardableResult
    func upsert(id: String?, trigger: String, expansion: String) -> SnippetRecord? {
        guard let normalized = SnippetRecord.normalizedTrigger(trigger),
              let cleanedExpansion = SnippetRecord.cleanedExpansion(expansion)
        else { return nil }

        var current = loadSnippets()
        let now = Date()
        let itemID = id ?? SnippetRecord.id(for: normalized)
        let existing = current.first { $0.id == itemID }
        let record = SnippetRecord(
            id: itemID,
            trigger: normalized,
            expansion: cleanedExpansion,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            useCount: existing?.useCount ?? 0,
            lastUsedAt: existing?.lastUsedAt
        )

        current.removeAll { $0.id == itemID || $0.trigger.caseInsensitiveCompare(normalized) == .orderedSame }
        current.append(record)
        save(current)
        return record
    }

    @discardableResult
    func saveUnique(trigger: String, expansion: String) -> SnippetRecord? {
        guard let baseTrigger = SnippetRecord.normalizedTrigger(trigger),
              let cleanedExpansion = SnippetRecord.cleanedExpansion(expansion)
        else { return nil }

        var current = loadSnippets()
        let now = Date()
        let normalized = availableTrigger(baseTrigger, existing: current)
        let record = SnippetRecord(
            id: SnippetRecord.id(for: normalized),
            trigger: normalized,
            expansion: cleanedExpansion,
            createdAt: now,
            updatedAt: now,
            useCount: 0,
            lastUsedAt: nil
        )

        current.append(record)
        save(current)
        return record
    }

    func delete(id: String) {
        var current = loadSnippets()
        current.removeAll { $0.id == id }
        save(current)
    }

    func search(_ query: String, limit: Int) -> [SearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current = loadSnippets()
        guard !current.isEmpty else { return [] }

        var results: [SearchResult] = []
        results.reserveCapacity(min(limit, current.count))

        for snippet in current {
            let score: Double
            if normalized.isEmpty {
                score = snippet.rankingScore
            } else if let match = FuzzyMatcher.score(query: normalized, candidate: snippet.searchText) {
                score = min(0.99, match * 0.92 + min(snippet.rankingScore, 0.08))
            } else {
                continue
            }

            results.append(SearchResult(
                id: "snippet:\(snippet.id)",
                kind: .snippet,
                title: snippet.trigger,
                subtitle: snippet.preview,
                score: score,
                action: .pasteSnippet(snippet.id)
            ))
        }

        results.sort { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    func expandedText(id: String, clipboard: String) -> String? {
        var current = loadSnippets()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return nil }

        current[index].useCount += 1
        current[index].lastUsedAt = Date()
        let expansion = current[index].expanded(clipboard: clipboard)
        save(current)
        return expansion
    }

    private func loadSnippets() -> [SnippetRecord] {
        if let snippets {
            return snippets
        }

        let exists = FileManager.default.fileExists(atPath: snippetsURL.path)
        let loaded = StorageCodec.load(
            [SnippetRecord].self,
            from: snippetsURL,
            default: exists ? [] : SnippetRecord.defaults
        )
        snippets = loaded
        if !exists {
            try? StorageCodec.save(loaded, to: snippetsURL)
        }
        return loaded
    }

    private func save(_ records: [SnippetRecord]) {
        let sortedRecords = sorted(records)
        snippets = sortedRecords
        try? StorageCodec.save(sortedRecords, to: snippetsURL)
    }

    private func sorted(_ records: [SnippetRecord]) -> [SnippetRecord] {
        records.sorted { lhs, rhs in
            lhs.trigger.localizedCaseInsensitiveCompare(rhs.trigger) == .orderedAscending
        }
    }

    private func availableTrigger(_ base: String, existing: [SnippetRecord]) -> String {
        let existingTriggers = Set(existing.map { $0.trigger.lowercased() })
        guard existingTriggers.contains(base.lowercased()) else { return base }

        let capacity = max(2, SnippetRecord.maxTriggerCharacters)
        let rootLimit = max(1, capacity - 4)
        let root = String(base.prefix(rootLimit))
        for suffix in 2...999 {
            let candidate = "\(root)\(suffix)"
            if !existingTriggers.contains(candidate.lowercased()) {
                return candidate
            }
        }
        return "\(root)\(Int(Date().timeIntervalSince1970) % 1000)"
    }
}

struct SnippetRecord: Codable, Equatable, Identifiable, Sendable {
    static let maxTriggerCharacters = 40
    static let maxExpansionCharacters = 20_000
    static let tokens = [
        SnippetToken(label: "Date", value: "{date}"),
        SnippetToken(label: "Time", value: "{time}"),
        SnippetToken(label: "Clipboard", value: "{clipboard}")
    ]
    static let starters = [
        SnippetStarter(title: "Email", trigger: ";email", expansion: "name@example.com"),
        SnippetStarter(title: "Signature", trigger: ";sig", expansion: "Best,\nRahul"),
        SnippetStarter(title: "Reply", trigger: ";reply", expansion: "Thanks, I'll take a look today."),
        SnippetStarter(title: "Clipboard", trigger: ";clip", expansion: "{clipboard}")
    ]

    let id: String
    var trigger: String
    var expansion: String
    var createdAt: Date
    var updatedAt: Date
    var useCount: Int
    var lastUsedAt: Date?

    var searchText: String {
        "\(trigger.dropFirst()) \(trigger) \(expansion)".lowercased()
    }

    var preview: String {
        let value = expansion
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 72 else { return value }
        return "\(value.prefix(72))..."
    }

    var rankingScore: Double {
        let recentBoost: Double
        if let lastUsedAt {
            let age = max(0, Date().timeIntervalSince(lastUsedAt))
            recentBoost = exp(-age / (14 * 24 * 60 * 60)) * 0.12
        } else {
            recentBoost = 0
        }
        return min(0.98, 0.82 + recentBoost + min(Double(useCount), 10) * 0.006)
    }

    static let defaults: [SnippetRecord] = {
        let now = Date()
        return [
            SnippetRecord(id: "default-date", trigger: ";date", expansion: "{date}", createdAt: now, updatedAt: now, useCount: 0, lastUsedAt: nil),
            SnippetRecord(id: "default-time", trigger: ";time", expansion: "{time}", createdAt: now, updatedAt: now, useCount: 0, lastUsedAt: nil),
            SnippetRecord(id: "default-clip", trigger: ";clip", expansion: "{clipboard}", createdAt: now, updatedAt: now, useCount: 0, lastUsedAt: nil)
        ]
    }()

    static func normalizedTrigger(_ value: String) -> String? {
        var trigger = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty else { return nil }
        if !trigger.hasPrefix(";") {
            trigger = ";\(trigger)"
        }
        guard trigger.count >= 2, trigger.count <= maxTriggerCharacters else { return nil }
        guard trigger.dropFirst().allSatisfy({ !$0.isWhitespace && !$0.isNewline }) else { return nil }
        return trigger.lowercased()
    }

    static func cleanedExpansion(_ value: String) -> String? {
        let expansion = value.replacingOccurrences(of: "\u{0000}", with: "")
        guard expansion.count <= maxExpansionCharacters else { return nil }
        guard !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return expansion
    }

    static func id(for trigger: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in trigger.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "snippet-\(String(hash, radix: 16))"
    }

    func expanded(clipboard: String) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return expansion
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
            .replacingOccurrences(of: "{clipboard}", with: clipboard)
    }
}

struct SnippetToken: Identifiable, Sendable {
    var id: String { value }
    let label: String
    let value: String
}

struct SnippetStarter: Identifiable, Sendable {
    var id: String { trigger }
    let title: String
    let trigger: String
    let expansion: String
}
