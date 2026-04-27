import Foundation

struct QuicklinkSource {
    func search(_ query: String, limit: Int) async -> [SearchResult] {
        await QuicklinkStore.shared.search(query, limit: limit)
    }
}

actor QuicklinkStore {
    static let shared = QuicklinkStore()

    private let quicklinksURL: URL
    private var quicklinks: [QuicklinkRecord]?
    private var index: [String: QuicklinkRecord] = [:]

    private init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        quicklinksURL = base
            .appendingPathComponent("vish", isDirectory: true)
            .appendingPathComponent("quicklinks.plist")
    }

    func list() -> [QuicklinkRecord] {
        sorted(loadQuicklinks())
    }

    @discardableResult
    func upsert(
        id: String?,
        keyword: String,
        name: String,
        urlTemplate: String,
        iconName: QuicklinkIconKind? = nil,
        customIconData: Data? = nil
    ) -> QuicklinkRecord? {
        guard let normalizedKeyword = QuicklinkRecord.normalizedKeyword(keyword),
              let cleanedName = QuicklinkRecord.cleanedName(name),
              let cleanedTemplate = QuicklinkRecord.cleanedURLTemplate(urlTemplate)
        else { return nil }

        var current = loadQuicklinks()
        let now = Date()
        let itemID = id ?? QuicklinkRecord.id(for: normalizedKeyword)
        let existing = current.first { $0.id == itemID }
        let finalIconName = customIconData == nil
            ? iconName ?? QuicklinkIconKind.defaultIcon(keyword: normalizedKeyword, urlTemplate: cleanedTemplate)
            : nil
        let record = QuicklinkRecord(
            id: itemID,
            keyword: normalizedKeyword,
            name: cleanedName,
            urlTemplate: cleanedTemplate,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            useCount: existing?.useCount ?? 0,
            lastUsedAt: existing?.lastUsedAt,
            iconName: finalIconName,
            customIconData: customIconData
        )

        current.removeAll { $0.id == itemID || $0.keyword == normalizedKeyword }
        current.append(record)
        save(current)
        return record
    }

    func delete(id: String) {
        var current = loadQuicklinks()
        current.removeAll { $0.id == id }
        save(current)
    }

    func recordActivation(resultID: String) {
        let parts = resultID.split(separator: ":", maxSplits: 2)
        guard parts.count >= 2 else { return }
        let keyword = String(parts[1])
        var current = loadQuicklinks()
        guard let index = current.firstIndex(where: { $0.keyword == keyword }) else { return }
        current[index].useCount += 1
        current[index].lastUsedAt = Date()
        save(current)
    }

    func search(_ query: String, limit: Int) -> [SearchResult] {
        let parsed = QuicklinkQuery(query)
        guard !parsed.keyword.isEmpty else { return [] }
        let current = loadQuicklinks()
        guard !current.isEmpty else { return [] }

        if let exact = index[parsed.keyword] {
            guard let result = exact.result(for: parsed.argument, score: 0.88 + min(exact.rankingBoost, 0.08)) else { return [] }
            return [result]
        }

        guard !parsed.hasArgument else { return [] }
        var results: [SearchResult] = []
        results.reserveCapacity(min(limit, current.count))

        for quicklink in current {
            let score: Double
            if quicklink.keyword.hasPrefix(parsed.keyword) {
                score = 0.66 + min(quicklink.rankingBoost, 0.08)
            } else if let match = FuzzyMatcher.score(query: parsed.keyword, candidate: quicklink.searchText) {
                score = min(0.64, match * 0.72 + min(quicklink.rankingBoost, 0.06))
            } else {
                continue
            }

            if let result = quicklink.result(for: "", score: score) {
                results.append(result)
            }
        }

        results.sort { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    private func loadQuicklinks() -> [QuicklinkRecord] {
        if let quicklinks {
            return quicklinks
        }

        let exists = FileManager.default.fileExists(atPath: quicklinksURL.path)
        let rawLoaded = StorageCodec.load(
            [QuicklinkRecord].self,
            from: quicklinksURL,
            default: exists ? [] : QuicklinkRecord.defaults
        )
        let loaded = rawLoaded.map(\.withDefaultIconIfNeeded)
        setSnapshot(loaded)
        if !exists || loaded != rawLoaded {
            try? StorageCodec.save(loaded, to: quicklinksURL)
        }
        return loaded
    }

    private func save(_ records: [QuicklinkRecord]) {
        let sortedRecords = sorted(records.map(\.withDefaultIconIfNeeded))
        setSnapshot(sortedRecords)
        try? StorageCodec.save(sortedRecords, to: quicklinksURL)
    }

    private func setSnapshot(_ records: [QuicklinkRecord]) {
        let sortedRecords = sorted(records)
        quicklinks = sortedRecords
        index = [:]
        index.reserveCapacity(sortedRecords.count)
        for record in sortedRecords {
            index[record.keyword] = record
        }
    }

    private func sorted(_ records: [QuicklinkRecord]) -> [QuicklinkRecord] {
        records.sorted { lhs, rhs in
            lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
        }
    }
}

struct QuicklinkRecord: Codable, Equatable, Identifiable, Sendable {
    static let maxKeywordCharacters = 32
    static let maxNameCharacters = 80
    static let maxTemplateCharacters = 2_048
    static let maxIconDataBytes = 128_000

    let id: String
    var keyword: String
    var name: String
    var urlTemplate: String
    var createdAt: Date
    var updatedAt: Date
    var useCount: Int
    var lastUsedAt: Date?
    var iconName: QuicklinkIconKind?
    var customIconData: Data?

    var searchText: String {
        "\(keyword) \(name)".lowercased()
    }

    var preview: String {
        urlTemplate.count <= 72 ? urlTemplate : "\(urlTemplate.prefix(72))..."
    }

    var rankingBoost: Double {
        let recent: Double
        if let lastUsedAt {
            recent = exp(-max(0, Date().timeIntervalSince(lastUsedAt)) / (14 * 24 * 60 * 60)) * 0.08
        } else {
            recent = 0
        }
        return recent + min(Double(useCount), 10) * 0.005
    }

    var resultIcon: ResultIcon? {
        if let customIconData {
            return .imageData(customIconData)
        }
        if let iconName {
            return .quicklink(iconName)
        }
        return nil
    }

    var withDefaultIconIfNeeded: QuicklinkRecord {
        guard customIconData == nil, iconName == nil,
              let defaultIcon = QuicklinkIconKind.defaultIcon(keyword: keyword, urlTemplate: urlTemplate)
        else { return self }

        var copy = self
        copy.iconName = defaultIcon
        return copy
    }

    static let defaults: [QuicklinkRecord] = {
        let now = Date()
        return [
            QuicklinkRecord(id: "default-gh", keyword: "gh", name: "GitHub", urlTemplate: "https://github.com/search?q={query}", createdAt: now, updatedAt: now, useCount: 0, lastUsedAt: nil, iconName: .github, customIconData: nil),
            QuicklinkRecord(id: "default-maps", keyword: "maps", name: "Maps", urlTemplate: "https://www.google.com/maps/search/?api=1&query={query}", createdAt: now, updatedAt: now, useCount: 0, lastUsedAt: nil, iconName: .maps, customIconData: nil),
            QuicklinkRecord(id: "default-yt", keyword: "yt", name: "YouTube", urlTemplate: "https://www.youtube.com/results?search_query={query}", createdAt: now, updatedAt: now, useCount: 0, lastUsedAt: nil, iconName: .youtube, customIconData: nil)
        ]
    }()

    static func normalizedKeyword(_ value: String) -> String? {
        let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty, keyword.count <= maxKeywordCharacters else { return nil }
        guard keyword.allSatisfy({ !$0.isWhitespace && !$0.isNewline }) else { return nil }
        return keyword
    }

    static func cleanedName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxNameCharacters else { return nil }
        return name
    }

    static func cleanedURLTemplate(_ value: String) -> String? {
        let template = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty, template.count <= maxTemplateCharacters else { return nil }
        guard URL(string: template.replacingOccurrences(of: "{query}", with: "test"))?.scheme != nil else { return nil }
        return template
    }

    static func id(for keyword: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in keyword.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "quicklink-\(String(hash, radix: 16))"
    }

    func result(for argument: String, score: Double) -> SearchResult? {
        guard let url = expandedURL(argument) else { return nil }
        let hasArgument = !argument.isEmpty
        return SearchResult(
            id: "quicklink:\(keyword):\(argument)",
            kind: .quicklink,
            title: hasArgument ? "\(name): \(argument)" : name,
            subtitle: hasArgument ? "\(keyword) \(argument)" : "Type \(keyword) query",
            score: score,
            icon: resultIcon,
            action: .openURL(url)
        )
    }

    private func expandedURL(_ argument: String) -> URL? {
        let encoded = argument.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? argument
        return URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: encoded))
    }

    private static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#%")
        return allowed
    }()
}

private struct QuicklinkQuery {
    let keyword: String
    let argument: String
    let hasArgument: Bool

    init(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(where: \.isWhitespace) else {
            keyword = trimmed.lowercased()
            argument = ""
            hasArgument = false
            return
        }

        keyword = String(trimmed[..<space]).lowercased()
        argument = trimmed[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        hasArgument = !argument.isEmpty
    }
}
