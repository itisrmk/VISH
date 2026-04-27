import Foundation

struct SemanticFileQuery: Sendable {
    let original: String
    let searchText: String
    let tokens: [String]
    let expandedTokens: [String]
    let typeFilter: FileTypeFilter
    let requiredPathExtension: String?
    let dateInterval: DateInterval?
    let dateLabel: String?

    static func parseTrigger(_ rawQuery: String) -> SemanticFileQuery? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let commands = [
            "ai find",
            "ai search",
            "ai locate",
            "ai show me",
            "? find",
            "? search"
        ]

        for command in commands {
            guard lower == command || lower.hasPrefix("\(command) ") else { continue }
            let body = String(trimmed.dropFirst(command.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return parse(body) ?? fallback(body) ?? emptyCommand(command)
        }

        return nil
    }

    private static func parse(_ body: String) -> SemanticFileQuery? {
        let date = extractDate(from: body)
        let lower = date.remaining.lowercased()
        let rawTokens = tokenize(lower)
        let type = extractType(from: rawTokens)
        let tokens = rawTokens.filter { !type.consumedTokens.contains($0) && !stopWords.contains($0) }
        let expanded = expand(tokens)
        guard !tokens.isEmpty || date.interval != nil else { return nil }

        return SemanticFileQuery(
            original: body,
            searchText: tokens.joined(separator: " "),
            tokens: tokens,
            expandedTokens: expanded,
            typeFilter: type.filter,
            requiredPathExtension: type.requiredPathExtension,
            dateInterval: date.interval,
            dateLabel: date.label
        )
    }

    private static func fallback(_ body: String) -> SemanticFileQuery? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let token = trimmed.lowercased()
        return SemanticFileQuery(
            original: trimmed,
            searchText: trimmed,
            tokens: [token],
            expandedTokens: [token],
            typeFilter: .common,
            requiredPathExtension: nil,
            dateInterval: nil,
            dateLabel: nil
        )
    }

    private static func emptyCommand(_ command: String) -> SemanticFileQuery {
        SemanticFileQuery(
            original: command,
            searchText: "",
            tokens: [],
            expandedTokens: [],
            typeFilter: .common,
            requiredPathExtension: nil,
            dateInterval: nil,
            dateLabel: nil
        )
    }

    private static func extractType(from tokens: [String]) -> (
        filter: FileTypeFilter,
        requiredPathExtension: String?,
        consumedTokens: Set<String>
    ) {
        let tokenSet = Set(tokens)
        if !tokenSet.isDisjoint(with: ["pdf", "pdfs"]) {
            return (.pdf, "pdf", ["pdf", "pdfs"])
        }
        if !tokenSet.isDisjoint(with: ["image", "images", "photo", "photos", "picture", "pictures"]) {
            return (.image, nil, ["image", "images", "photo", "photos", "picture", "pictures"])
        }
        if !tokenSet.isDisjoint(with: ["code", "script", "scripts", "source"]) {
            return (.code, nil, ["code", "script", "scripts", "source"])
        }
        if !tokenSet.isDisjoint(with: ["doc", "docs", "document", "documents", "file", "files"]) {
            return (.document, nil, ["doc", "docs", "document", "documents", "file", "files"])
        }
        return (.common, nil, [])
    }

    private static func extractDate(from value: String) -> (interval: DateInterval?, label: String?, remaining: String) {
        let calendar = Calendar.current
        let now = Date()
        var lower = value.lowercased()

        if let relative = relativeCountInterval(in: lower, calendar: calendar, now: now) {
            lower = relative.remaining
            return (relative.interval, relative.label, lower)
        }

        let phrases: [(String, String, () -> DateInterval?)] = [
            ("last month", "last month", { previous(.month, calendar: calendar, now: now) }),
            ("this month", "this month", { calendar.dateInterval(of: .month, for: now) }),
            ("last week", "last week", { previous(.weekOfYear, calendar: calendar, now: now) }),
            ("this week", "this week", { calendar.dateInterval(of: .weekOfYear, for: now) }),
            ("yesterday", "yesterday", {
                guard let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return nil }
                return DateInterval(start: start, end: calendar.startOfDay(for: now))
            }),
            ("today", "today", {
                guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
                return DateInterval(start: calendar.startOfDay(for: now), end: end)
            })
        ]

        for (phrase, label, interval) in phrases where lower.contains(phrase) {
            lower = lower.replacingOccurrences(of: phrase, with: " ")
            return (interval(), label, lower)
        }
        return (nil, nil, value)
    }

    private static func relativeCountInterval(
        in value: String,
        calendar: Calendar,
        now: Date
    ) -> (interval: DateInterval, label: String, remaining: String)? {
        let pattern = #"\b(?:last|past)\s+(\d{1,3})\s+(day|days|week|weeks|month|months)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: nsRange),
              let countRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let count = Int(value[countRange])
        else { return nil }

        let unitText = String(value[unitRange])
        let component: Calendar.Component = unitText.hasPrefix("month") ? .month : unitText.hasPrefix("week") ? .weekOfYear : .day
        guard let start = calendar.date(byAdding: component, value: -count, to: now) else { return nil }
        let remaining = regex.stringByReplacingMatches(in: value, range: nsRange, withTemplate: " ")
        return (DateInterval(start: start, end: now), "past \(count) \(unitText)", remaining)
    }

    private static func previous(_ component: Calendar.Component, calendar: Calendar, now: Date) -> DateInterval? {
        guard let current = calendar.dateInterval(of: component, for: now),
              let start = calendar.date(byAdding: component, value: -1, to: current.start)
        else { return nil }
        return DateInterval(start: start, end: current.start)
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func expand(_ tokens: [String]) -> [String] {
        var output = tokens
        let set = Set(tokens)
        if !set.isDisjoint(with: ["tax", "taxes"]) {
            output.append(contentsOf: ["tax", "taxes", "irs", "income", "return", "refund", "1099", "w2"])
        }
        var seen = Set<String>()
        return output.filter { seen.insert($0).inserted }
    }

    private static let stopWords: Set<String> = [
        "about", "after", "all", "and", "any", "are", "called", "for", "from", "has", "have",
        "into", "last", "like", "me", "month", "named", "of", "on", "or", "please", "show",
        "that", "the", "this", "to", "week", "with"
    ]
}

enum SemanticFileFinder {
    static func search(_ query: SemanticFileQuery, fileSearchActor: FileSearchActor, limit: Int) async -> [SearchResult] {
        guard !query.searchText.isEmpty || query.dateInterval != nil else {
            return promptResults()
        }

        async let broadResults = FileIndexStore.shared.semanticCandidates(
            queryTokens: query.expandedTokens,
            typeFilter: query.typeFilter,
            requiredPathExtension: query.requiredPathExtension,
            includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled,
            dateInterval: query.dateInterval,
            limit: 96
        )
        async let nameResults: [SearchResult] = query.searchText.count >= 2
            ? fileSearchActor.search(fileRequest(query, mode: .name), limit: 32)
            : []
        async let contentResults: [SearchResult] = query.searchText.count >= 2
            ? fileSearchActor.search(fileRequest(query, mode: .content), limit: 32)
            : []

        var candidates: [String: RankedFileCandidate] = [:]
        merge(await nameResults, weight: 1.0, into: &candidates, query: query)
        merge(await contentResults, weight: 1.25, into: &candidates, query: query)
        merge(await broadResults, weight: 0.70, into: &candidates, query: query)

        let vectorSeeds = Array(candidates.values)
            .sorted { $0.rankScore == $1.rankScore ? $0.result.title < $1.result.title : $0.rankScore > $1.rankScore }
            .prefix(48)
            .map(\.result)
        let vectorResults = await SemanticVectorIndexStore.shared.search(query, seeds: Array(vectorSeeds), limit: 48)
        merge(vectorResults, weight: 2.4, into: &candidates, query: query)

        let shortlist = Array(candidates.values)
            .sorted { $0.rankScore == $1.rankScore ? $0.result.title < $1.result.title : $0.rankScore > $1.rankScore }
            .prefix(32)
        guard !shortlist.isEmpty else { return emptyStateResults(query) }

        let ranked = await rerankWithPreviews(Array(shortlist), query: query)
        return Array(ranked.prefix(limit))
    }

    private static func fileRequest(_ query: SemanticFileQuery, mode: FileSearchRequest.Mode) -> FileSearchRequest {
        FileSearchRequest(
            query: query.searchText,
            mode: mode,
            activation: .open,
            typeFilter: query.typeFilter,
            includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled
        )
    }

    private static func emptyStateResults(_ query: SemanticFileQuery) -> [SearchResult] {
        let title = LauncherPreferences.localAIEnabled ? "No indexed semantic matches" : "Local AI is off"
        let subtitle = LauncherPreferences.localAIEnabled
            ? "Run Settings > Files > Warm to build the vector index."
            : "Enable Settings > AI, then run Settings > Files > Warm."
        return [SearchResult(
            id: "semantic-empty:\(query.original)",
            kind: .ai,
            title: title,
            subtitle: subtitle,
            score: 0.4,
            icon: .symbol("doc.text.magnifyingglass"),
            action: .copy(subtitle)
        )]
    }

    private static func promptResults() -> [SearchResult] {
        [SearchResult(
            id: "semantic-prompt",
            kind: .ai,
            title: "Find files with AI",
            subtitle: "Type what to find, e.g. ai find paper from last month",
            score: 1,
            icon: .symbol("doc.text.magnifyingglass"),
            action: .copy("Type what to find after ai find.")
        )]
    }

    private static func merge(
        _ results: [SearchResult],
        weight: Double,
        into candidates: inout [String: RankedFileCandidate],
        query: SemanticFileQuery
    ) {
        for (offset, result) in results.enumerated() {
            guard let url = fileURL(for: result), accepts(url, query: query) else { continue }
            let path = url.path
            var candidate = candidates[path] ?? RankedFileCandidate(result: normalizedResult(result, url: url), rankScore: 0)
            if result.subtitle.hasPrefix("Semantic match") {
                candidate.result = normalizedResult(result, url: url)
            }
            candidate.rankScore += weight / Double(60 + offset + 1)
            candidates[path] = candidate
        }
    }

    private static func rerankWithPreviews(_ candidates: [RankedFileCandidate], query: SemanticFileQuery) async -> [SearchResult] {
        await Task.detached(priority: .userInitiated) {
            candidates.enumerated().map { offset, candidate in
                guard let url = fileURL(for: candidate.result) else { return candidate.result }
                let preview: TinyFilePreview = offset < previewReadLimit ? FilePreviewReader.preview(for: url) : .unavailable("preview skipped")
                let previewScore = score(preview: preview, query: query)
                let metadata = metadataScore(url: url, title: candidate.result.title, query: query)
                let score = min(0.99, 0.36 + min(candidate.rankScore * 8, 0.28) + metadata + previewScore)
                return SearchResult(
                    id: candidate.result.id,
                    kind: .file,
                    title: candidate.result.title,
                    subtitle: subtitle(for: candidate.result.subtitle, previewScore: previewScore, dateLabel: query.dateLabel),
                    score: score,
                    icon: candidate.result.icon,
                    action: candidate.result.action
                )
            }
            .sorted { $0.score == $1.score ? $0.title < $1.title : $0.score > $1.score }
        }.value
    }

    private static func normalizedResult(_ result: SearchResult, url: URL) -> SearchResult {
        SearchResult(
            id: "file:\(url.path)",
            kind: .file,
            title: result.title,
            subtitle: result.subtitle.hasPrefix("Semantic match") ? result.subtitle : url.path,
            score: result.score,
            icon: result.icon,
            action: .openFile(url)
        )
    }

    private static func subtitle(for base: String, previewScore: Double, dateLabel: String?) -> String {
        let label: String
        let detail: String
        if base.hasPrefix("Semantic match") {
            label = previewScore > 0 ? "Semantic + preview match" : "Semantic match"
            detail = base.replacingOccurrences(of: "Semantic match - ", with: "")
        } else {
            label = previewScore > 0 ? "Preview match" : "File match"
            detail = base
        }
        if let dateLabel {
            return "\(label), \(dateLabel) - \(detail)"
        }
        return "\(label) - \(detail)"
    }

    private static func accepts(_ url: URL, query: SemanticFileQuery) -> Bool {
        if let required = query.requiredPathExtension,
           url.pathExtension.localizedCaseInsensitiveCompare(required) != .orderedSame {
            return false
        }
        if let interval = query.dateInterval {
            guard let date = fileDate(url), date >= interval.start, date < interval.end else { return false }
        }
        return true
    }

    private static func fileDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate
    }

    private static func score(preview: TinyFilePreview, query: SemanticFileQuery) -> Double {
        guard case .available(let text) = preview else { return 0 }
        let lower = text.lowercased()
        var score = 0.0
        if !query.searchText.isEmpty, lower.contains(query.searchText) {
            score += 0.18
        }
        for token in query.expandedTokens where lower.contains(token) {
            score += 0.055
        }
        return min(score, 0.36)
    }

    private static func metadataScore(url: URL, title: String, query: SemanticFileQuery) -> Double {
        let haystack = "\(title) \(url.deletingLastPathComponent().lastPathComponent)".lowercased()
        var score = query.requiredPathExtension == nil ? 0 : 0.05
        if query.dateInterval != nil { score += 0.05 }
        for token in query.expandedTokens where haystack.contains(token) {
            score += 0.04
        }
        if !query.searchText.isEmpty, let fuzzy = FuzzyMatcher.score(query: query.searchText, candidate: haystack) {
            score += min(fuzzy * 0.12, 0.12)
        }
        return min(score, 0.24)
    }

    private static func fileURL(for result: SearchResult) -> URL? {
        switch result.action {
        case .openFile(let url), .revealFile(let url):
            return url
        case .askAI, .copy, .openApplication, .openURL, .pasteClipboard, .pasteSnippet, .system:
            return nil
        }
    }

    private static let previewReadLimit = 12
}

private struct RankedFileCandidate {
    var result: SearchResult
    var rankScore: Double
}
