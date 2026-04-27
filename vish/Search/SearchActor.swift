import Foundation

actor SearchActor {
    private var appSource = AppSource(apps: [])
    private let calculatorSource = CalculatorSource()
    private let clipboardSource = ClipboardHistorySource()
    private let fileSearchActor = FileSearchActor()
    private let indexStore = IndexStore.shared
    private let quicklinkSource = QuicklinkSource()
    private let snippetSource = SnippetSource()
    private let systemActionsSource = SystemActionsSource()
    private let urlSource = URLSource()
    private let webSearchSource = WebSearchSource()

    func refreshApps() async {
        let cached = await indexStore.loadApps()
        if !cached.isEmpty {
            appSource = AppSource(apps: cached)
        }

        let fresh = AppSource.loadCatalog()
        guard fresh != cached else { return }
        appSource = AppSource(apps: fresh)
        await indexStore.saveApps(fresh)
    }

    func recordActivation(_ result: SearchResult) async {
        if result.kind == .quicklink {
            await QuicklinkStore.shared.recordActivation(resultID: result.id)
        }
        await indexStore.recordActivation(result)
    }

    func search(_ rawQuery: String, limit: Int = 8, includeSlowFiles: Bool = true) async -> [SearchResult] {
        let intent = SearchIntent(rawQuery)
        switch intent {
        case .ai(let query):
            return aiResults(for: query)
        case .clipboard(let query):
            return await clipboardSource.search(query, limit: limit)
        case .default(let query):
            return await defaultResults(for: query, limit: limit, includeSlowFiles: includeSlowFiles)
        case .files(let request):
            let results = await fileSearchActor.search(request, limit: limit)
            return await indexStore.ranked(results, limit: limit)
        case .semanticFiles(let query):
            let results = await SemanticFileFinder.search(query, fileSearchActor: fileSearchActor, limit: limit)
            return await indexStore.ranked(results, limit: limit)
        case .snippets(let query):
            return await snippetSource.search(query, limit: limit)
        }
    }

    func supplementalFileResults(
        for rawQuery: String,
        currentResults: [SearchResult],
        limit: Int = 8
    ) async -> [SearchResult] {
        guard case .default(let query) = SearchIntent(rawQuery) else { return [] }
        guard shouldSearchFiles(for: query, currentResults: currentResults) else { return [] }
        guard !Task.isCancelled else { return [] }

        let files = await fileSearchActor.search(.init(
            query: query,
            mode: .name,
            activation: .open,
            typeFilter: .common,
            includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled
        ), limit: limit)
        guard !Task.isCancelled, !files.isEmpty else { return [] }

        var merged = currentResults
        merged.append(contentsOf: await indexStore.ranked(files, limit: 4))
        merged = sorted(deduped(merged))
        return await indexStore.ranked(merged, limit: limit)
    }

    private func defaultResults(for query: String, limit: Int, includeSlowFiles: Bool) async -> [SearchResult] {
        let normalized = query.lowercased()
        guard !Task.isCancelled else { return [] }

        async let frecencyResults = indexStore.frecencyResults(matching: normalized, limit: 4)
        async let quicklinkResults = quicklinkSource.search(query, limit: 4)
        var results: [SearchResult] = []
        results.reserveCapacity(16)
        results.append(contentsOf: calculatorSource.search(query))
        results.append(contentsOf: systemActionsSource.search(normalized))
        results.append(contentsOf: appSource.search(normalized))
        results.append(contentsOf: await quicklinkResults)
        results.append(contentsOf: urlSource.search(query))
        results.append(contentsOf: await frecencyResults)
        guard !Task.isCancelled else { return [] }
        results = sorted(deduped(results))

        if includeSlowFiles, shouldSearchFiles(for: query, currentResults: results) {
            guard !Task.isCancelled else { return [] }
            let files = await fileSearchActor.search(.init(
                query: query,
                mode: .name,
                activation: .open,
                typeFilter: .common,
                includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled
            ), limit: limit)
            results.append(contentsOf: await indexStore.ranked(files, limit: 4))
            guard !Task.isCancelled else { return [] }
            results = sorted(deduped(results))
        }

        if results.allSatisfy({ $0.score <= 0.3 }) {
            results.append(contentsOf: webSearchSource.search(query))
        }

        return await indexStore.ranked(results, limit: limit)
    }

    private func shouldSearchFiles(for query: String, currentResults: [SearchResult]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, URLDetector.url(from: trimmed) == nil else { return false }
        return currentResults.first?.score ?? 0 < 0.65
    }

    private func aiResults(for query: String) -> [SearchResult] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LauncherPreferences.localAIEnabled else {
            return [SearchResult(
                id: "ai:disabled",
                kind: .ai,
                title: "Local AI is off",
                subtitle: "Enable it in Settings > AI.",
                score: 1,
                icon: .symbol("sparkle.magnifyingglass"),
                action: .copy("Enable Local AI in Settings > AI.")
            )]
        }

        guard !value.isEmpty else {
            return [SearchResult(
                id: "ai:empty",
                kind: .ai,
                title: "Ask local AI",
                subtitle: "Type a question after ai or ?",
                score: 1,
                icon: .symbol("sparkle.magnifyingglass"),
                action: .askAI("")
            )]
        }

        return [SearchResult(
            id: "ai:\(value)",
            kind: .ai,
            title: "Ask local AI: \(value)",
            subtitle: "Ollama local model",
            score: 1,
            icon: .symbol("sparkle.magnifyingglass"),
            action: .askAI(value)
        )]
    }

    private func deduped(_ results: [SearchResult]) -> [SearchResult] {
        var seen = Set<String>()
        var deduped: [SearchResult] = []
        deduped.reserveCapacity(results.count)

        for result in results where seen.insert("\(result.kind.rawValue):\(result.id)").inserted {
            deduped.append(result)
        }

        return deduped
    }

    private func sorted(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.title < rhs.title : lhs.score > rhs.score
        }
    }
}

private enum SearchIntent {
    case ai(String)
    case clipboard(String)
    case `default`(String)
    case files(FileSearchRequest)
    case semanticFiles(SemanticFileQuery)
    case snippets(String)

    init(_ rawQuery: String) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        func file(
            _ query: String,
            mode: FileSearchRequest.Mode = .name,
            activation: FileSearchRequest.Activation = .open,
            typeFilter: FileTypeFilter = .common
        ) -> FileSearchRequest {
            FileSearchRequest(
                query: query,
                mode: mode,
                activation: activation,
                typeFilter: typeFilter,
                includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled
            )
        }

        if rawQuery.hasPrefix(" ") {
            self = .files(file(trimmed))
            return
        }

        if rawQuery.hasPrefix("'") {
            let query = rawQuery.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            self = query.isEmpty ? .default(trimmed) : .files(file(query))
            return
        }

        if let query = SemanticFileQuery.parseTrigger(rawQuery) {
            self = .semanticFiles(query)
            return
        }

        if let query = Self.aiValue(rawQuery: rawQuery, trimmed: trimmed, lower: lower) {
            self = .ai(query)
            return
        }

        if rawQuery.hasPrefix(";") {
            self = .snippets(rawQuery.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines))
            return
        }

        if let query = Self.value(after: "open ", in: trimmed, lower: lower) {
            self = .files(file(query))
            return
        }

        if let query = Self.clipboardValue(trimmed: trimmed, lower: lower) {
            self = .clipboard(query)
            return
        }

        if let query = Self.value(after: "find ", in: trimmed, lower: lower) {
            self = .files(file(query, activation: .reveal))
            return
        }

        if let query = Self.value(after: "in ", in: trimmed, lower: lower) {
            self = .files(file(query, mode: .content, typeFilter: .all))
            return
        }

        if let query = Self.value(after: "tags ", in: trimmed, lower: lower) {
            self = .files(file(query, mode: .tags, typeFilter: .all))
            return
        }

        if let query = Self.value(after: "all:", in: trimmed, lower: lower) {
            self = .files(file(query, typeFilter: .all))
            return
        }

        if let kind = Self.kindValue(trimmed: trimmed, lower: lower) {
            self = .files(file(kind.query, typeFilter: kind.filter))
            return
        }

        self = .default(trimmed)
    }

    private static func value(after prefix: String, in query: String, lower: String) -> String? {
        guard lower.hasPrefix(prefix) else { return nil }
        let value = query.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func clipboardValue(trimmed: String, lower: String) -> String? {
        if lower == "clip" || lower == "clipboard" {
            return ""
        }

        for prefix in ["clip ", "clipboard "] where lower.hasPrefix(prefix) {
            return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func aiValue(rawQuery: String, trimmed: String, lower: String) -> String? {
        if lower == "ai" || lower == "?" {
            return ""
        }
        if lower.hasPrefix("ai ") {
            return trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if rawQuery.hasPrefix("?") {
            return rawQuery.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func kindValue(trimmed: String, lower: String) -> (query: String, filter: FileTypeFilter)? {
        let filters: [(String, FileTypeFilter)] = [
            ("kind:image ", .image),
            ("kind:doc ", .document),
            ("kind:code ", .code)
        ]

        for (prefix, filter) in filters where lower.hasPrefix(prefix) {
            let query = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
            return (query, filter)
        }

        return nil
    }
}
