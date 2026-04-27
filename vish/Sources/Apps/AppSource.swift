import Foundation

struct AppSource: SearchSource {
    static let catalogRoots = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
        "/Applications/Utilities",
        "/System/Applications/Utilities"
    ]

    private let apps: [AppRecord]
    private let candidates: AppCandidateIndex

    init(apps: [AppRecord]) {
        self.apps = apps
        candidates = AppCandidateIndex(apps: apps)
    }

    static func loadCatalog(fileManager: FileManager = .default) -> [AppRecord] {
        var seen = Set<String>()
        var records: [AppRecord] = []
        records.reserveCapacity(256)

        for root in catalogRoots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let urls = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard let record = AppRecord(url: url), seen.insert(record.id).inserted else { continue }
                records.append(record)
            }
        }

        records.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return records
    }

    func search(_ query: String) -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []
        let candidateIndexes = candidates.matches(for: query, appCount: apps.count, limit: 384)
        results.reserveCapacity(min(candidateIndexes.count, 16))

        for index in candidateIndexes {
            let app = apps[index]
            guard let score = FuzzyMatcher.score(query: query, candidate: app.searchName) else { continue }
            results.append(SearchResult(
                id: app.id,
                kind: .app,
                title: app.name,
                subtitle: "Open application",
                score: 0.95 * score,
                action: .openApplication(app.url)
            ))
        }

        results.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.title < rhs.title : lhs.score > rhs.score
        }
        return Array(results.prefix(16))
    }
}

struct AppRecord: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let searchName: String
    let tokens: [String]
    let url: URL

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case searchName
        case url
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? fallbackName

        self.id = bundle.bundleIdentifier ?? url.path
        self.name = name
        self.searchName = name.lowercased()
        tokens = Self.tokens(in: searchName)
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        searchName = try container.decode(String.self, forKey: .searchName)
        url = try container.decode(URL.self, forKey: .url)
        tokens = Self.tokens(in: searchName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(searchName, forKey: .searchName)
        try container.encode(url, forKey: .url)
    }

    static func tokens(in value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

private struct AppCandidateIndex {
    private let prefixIndex: [String: [Int]]
    private let acronymIndex: [String: [Int]]
    private let shortcutIndex: [String: [Int]]

    init(apps: [AppRecord]) {
        var prefixes: [String: [Int]] = [:]
        var acronyms: [String: [Int]] = [:]
        var shortcuts: [String: [Int]] = [:]

        for (offset, app) in apps.enumerated() {
            for token in app.tokens {
                for prefix in Self.prefixes(for: token) {
                    prefixes[prefix, default: []].append(offset)
                }
                for shortcut in Self.shortcuts(for: token) {
                    shortcuts[shortcut, default: []].append(offset)
                }
            }

            let acronym = app.tokens.compactMap(\.first).map(String.init).joined()
            for prefix in Self.prefixes(for: acronym) {
                acronyms[prefix, default: []].append(offset)
            }
        }

        prefixIndex = prefixes
        acronymIndex = acronyms
        shortcutIndex = shortcuts
    }

    func matches(for query: String, appCount: Int, limit: Int) -> [Int] {
        let tokens = AppRecord.tokens(in: query)
        guard !tokens.isEmpty else { return [] }

        var seen = Set<Int>()
        var output: [Int] = []
        output.reserveCapacity(min(limit, appCount))

        for token in tokens {
            append(prefixIndex[Self.key(token)], to: &output, seen: &seen, limit: limit)
            append(acronymIndex[Self.key(token)], to: &output, seen: &seen, limit: limit)
            if token.count == 2 {
                append(shortcutIndex[token], to: &output, seen: &seen, limit: limit)
            }
        }

        if output.isEmpty {
            output = Array(0..<appCount)
        }
        return output
    }

    private func append(_ values: [Int]?, to output: inout [Int], seen: inout Set<Int>, limit: Int) {
        guard let values else { return }
        for value in values {
            guard output.count < limit else { return }
            if seen.insert(value).inserted {
                output.append(value)
            }
        }
    }

    private static func prefixes(for token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        let capped = String(token.prefix(6))
        var output: [String] = []
        output.reserveCapacity(capped.count)

        var end = capped.startIndex
        while end < capped.endIndex {
            capped.formIndex(after: &end)
            output.append(String(capped[..<end]))
        }
        return output
    }

    private static func shortcuts(for token: String) -> [String] {
        guard let first = token.first, token.count > 2 else { return [] }
        return token.dropFirst().prefix(10).map { "\(first)\($0)" }
    }

    private static func key(_ token: String) -> String {
        token.count > 6 ? String(token.prefix(6)) : token
    }
}
