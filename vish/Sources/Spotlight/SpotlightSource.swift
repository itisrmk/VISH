import Foundation
@preconcurrency import CoreServices
import os

actor FileSearchActor {
    private let fileIndexStore = FileIndexStore.shared

    func search(_ request: FileSearchRequest, limit: Int) async -> [SearchResult] {
        guard request.query.count >= 2 else { return [] }
        if request.mode == .name {
            let cachedResults = await fileIndexStore.search(request, limit: limit)
            if !cachedResults.isEmpty { return cachedResults }
        }

        let runner = await SpotlightQueryRunner(request: request, limit: min(limit, 20))
        let spotlightResults = await withTaskCancellationHandler {
            await runner.start()
        } onCancel: {
            Task { @MainActor in
                runner.cancel()
            }
        }
        return spotlightResults
    }
}

struct FileSearchRequest: Sendable {
    enum Mode: Sendable {
        case name
        case content
        case tags
    }

    enum Activation: Sendable {
        case open
        case reveal
    }

    let query: String
    let mode: Mode
    let activation: Activation
    let typeFilter: FileTypeFilter
    let includeFullDisk: Bool
}

struct FileIndexProgress: Sendable {
    let scannedCount: Int
    let indexedCount: Int
    let rootPath: String
    let isFinished: Bool
}

struct FileIndexEvent: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags
}

struct FileVectorCandidate: Sendable {
    let path: String
    let title: String
    let modifiedAt: TimeInterval?
}

private final class FileIndexWatcherCallbackBox: @unchecked Sendable {
    let watcherAddress: UInt

    init(watcher: FileIndexWatcher) {
        watcherAddress = UInt(bitPattern: Unmanaged.passUnretained(watcher).toOpaque())
    }
}

enum FileTypeFilter: Sendable {
    case common
    case all
    case image
    case document
    case code
    case pdf

    var contentTypes: [String]? {
        switch self {
        case .all:
            return nil
        case .common:
            return ["public.content", "public.folder", "public.text", "public.image", "public.source-code", "com.adobe.pdf"]
        case .image:
            return ["public.image"]
        case .document:
            return ["public.content", "public.text", "com.adobe.pdf"]
        case .code:
            return ["public.source-code", "public.script", "public.shell-script"]
        case .pdf:
            return ["com.adobe.pdf"]
        }
    }
}

@MainActor
private final class SpotlightQueryRunner: NSObject {
    private let limit: Int
    private let query: NSMetadataQuery
    private let request: FileSearchRequest
    private var signpostID: OSSignpostID?
    private var continuation: CheckedContinuation<[SearchResult], Never>?

    init(request: FileSearchRequest, limit: Int) {
        self.limit = limit
        self.request = request
        query = NSMetadataQuery()
        super.init()

        query.predicate = Self.predicate(for: request)
        query.searchScopes = request.includeFullDisk ? [NSMetadataQueryLocalComputerScope] : [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemDisplayNameKey, ascending: true)]
        query.notificationBatchingInterval = 0.03
    }

    func start() async -> [SearchResult] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            signpostID = PerformanceProbe.beginSpotlightQuery()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(finish),
                name: .NSMetadataQueryDidUpdate,
                object: query
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(finish),
                name: .NSMetadataQueryDidFinishGathering,
                object: query
            )

            guard query.start() else {
                finish()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.finish()
            }
        }
    }

    @objc private func finish() {
        guard let continuation else { return }

        let results = results()
        self.continuation = nil
        query.disableUpdates()
        query.stop()
        NotificationCenter.default.removeObserver(self)
        endSignpost(resultCount: results.count)
        continuation.resume(returning: results)
    }

    func cancel() {
        guard let continuation else { return }

        self.continuation = nil
        query.disableUpdates()
        query.stop()
        NotificationCenter.default.removeObserver(self)
        endSignpost(resultCount: 0)
        continuation.resume(returning: [])
    }

    private func endSignpost(resultCount: Int) {
        guard let signpostID else { return }
        PerformanceProbe.endSpotlightQuery(signpostID, resultCount: resultCount)
        self.signpostID = nil
    }

    private func results() -> [SearchResult] {
        guard query.resultCount > 0 else { return [] }

        var results: [SearchResult] = []
        results.reserveCapacity(limit)

        for index in 0..<query.resultCount where results.count < limit {
            guard
                let item = query.result(at: index) as? NSMetadataItem,
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                isAllowed(path)
            else { continue }

            let url = URL(fileURLWithPath: path)
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                ?? item.value(forAttribute: NSMetadataItemFSNameKey) as? String
                ?? url.lastPathComponent
            let action: ResultAction = request.activation == .reveal ? .revealFile(url) : .openFile(url)
            results.append(SearchResult(
                id: "file:\(path)",
                kind: .file,
                title: name,
                subtitle: subtitle(for: path),
                score: 0.6,
                action: action
            ))
        }

        return results
    }

    private func subtitle(for path: String) -> String {
        switch request.activation {
        case .open:
            switch request.mode {
            case .content:
                return "Open file containing text - \(path)"
            case .name:
                return path
            case .tags:
                return "Open tagged file - \(path)"
            }
        case .reveal:
            return "Reveal in Finder - \(path)"
        }
    }

    private static func predicate(for request: FileSearchRequest) -> NSPredicate {
        let searchKey: String
        switch request.mode {
        case .content:
            searchKey = NSMetadataItemTextContentKey
        case .name:
            searchKey = NSMetadataItemFSNameKey
        case .tags:
            searchKey = "kMDItemUserTags"
        }
        let textPredicate = NSPredicate(format: "%K CONTAINS[cd] %@", searchKey, request.query)

        guard let contentTypes = request.typeFilter.contentTypes else {
            return textPredicate
        }

        let typePredicates = contentTypes.map {
            NSPredicate(format: "ANY %K == %@", NSMetadataItemContentTypeTreeKey, $0)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            textPredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        ])
    }

    private func isAllowed(_ path: String) -> Bool {
        let hidden = path.split(separator: "/").contains { $0.hasPrefix(".") }
        guard !hidden else { return false }
        guard !LauncherPreferences.isFileSearchPathExcluded(path) else { return false }
        guard !request.includeFullDisk else { return true }

        let excludedPrefixes = [
            "/System/",
            "/Library/",
            "/private/",
            "/usr/",
            "/bin/",
            "/sbin/"
        ]
        return !excludedPrefixes.contains { path.hasPrefix($0) }
    }
}

actor FileIndexStore {
    static let shared = FileIndexStore()

    private let indexURL: URL
    private let legacyIndexURL: URL
    private var records: [FileRecord]?
    private var index: FileRecordIndex?
    private var progress = FileIndexProgress(scannedCount: 0, indexedCount: 0, rootPath: "", isFinished: false)
    private var interactiveActivity = false

    private init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("vish", isDirectory: true)
        indexURL = directory.appendingPathComponent("files.plist")
        legacyIndexURL = directory.appendingPathComponent("files.json")
    }

    func rebuild(includeFullDisk: Bool) async -> Int {
        progress = FileIndexProgress(scannedCount: 0, indexedCount: 0, rootPath: "", isFinished: false)
        let fresh = await FileIndexScanner.scan(
            includeFullDisk: includeFullDisk,
            shouldPause: { [weak self] in await self?.isInteractiveActivityActive() ?? false },
            progress: { [weak self] progress in
                await self?.setProgress(progress)
            }
        )
        records = fresh
        index = FileRecordIndex(records: fresh)
        save(fresh)
        progress = FileIndexProgress(scannedCount: fresh.count, indexedCount: fresh.count, rootPath: "", isFinished: true)
        return fresh.count
    }

    func currentProgress() -> FileIndexProgress {
        progress
    }

    func prewarm() {
        _ = load()
    }

    func setInteractiveActivity(_ active: Bool) {
        interactiveActivity = active
    }

    func isInteractiveActivityActive() -> Bool {
        interactiveActivity
    }

    func search(_ request: FileSearchRequest, limit: Int) -> [SearchResult] {
        guard request.mode == .name else { return [] }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 2 else { return [] }

        guard let snapshot = records, index != nil else { return [] }
        let candidateIndexes = indexedCandidates(query: query, limit: 1_024)
        var results: [SearchResult] = []
        results.reserveCapacity(limit * 2)

        for recordIndex in candidateIndexes {
            let record = snapshot[recordIndex]
            guard request.typeFilter.accepts(record.kind) else { continue }
            guard !LauncherPreferences.isFileSearchPathExcluded(record.path) else { continue }
            guard request.includeFullDisk || Self.isUserScopePath(record.path) else { continue }
            let score: Double?
            if record.searchName.hasPrefix(query) {
                score = 0.72
            } else if record.tokenPrefixesContain(query) {
                score = 0.68
            } else if record.searchName.contains(query) {
                score = 0.64
            } else {
                score = FuzzyMatcher.score(query: query, candidate: record.searchName).map { $0 * 0.52 }
            }

            guard let score, score > 0.28 else { continue }
            let url = URL(fileURLWithPath: record.path)
            let action: ResultAction = request.activation == .reveal ? .revealFile(url) : .openFile(url)
            results.append(SearchResult(
                id: "file:\(record.path)",
                kind: .file,
                title: record.name,
                subtitle: request.activation == .reveal ? "Reveal in Finder - \(record.path)" : record.path,
                score: score,
                action: action
            ))
        }

        results.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.title < rhs.title : lhs.score > rhs.score
        }
        return Array(results.prefix(limit))
    }

    func semanticCandidates(
        queryTokens: [String],
        typeFilter: FileTypeFilter,
        requiredPathExtension: String?,
        includeFullDisk: Bool,
        dateInterval: DateInterval?,
        limit: Int
    ) -> [SearchResult] {
        let snapshot = records ?? load()
        guard !snapshot.isEmpty else { return [] }
        let tokens = queryTokens.map { $0.lowercased() }
        let indexed = tokens.isEmpty ? [] : indexedCandidates(query: tokens.joined(separator: " "), limit: 2_048)
        let sourceRecords = tokens.isEmpty ? snapshot : indexed.map { snapshot[$0] }
        let canLazyReadDates = dateInterval != nil && sourceRecords.count <= 4_096
        var candidates: [(record: FileRecord, score: Double)] = []
        candidates.reserveCapacity(min(limit * 2, 256))

        for record in sourceRecords {
            guard typeFilter.accepts(record.kind) else { continue }
            guard !LauncherPreferences.isFileSearchPathExcluded(record.path) else { continue }
            guard includeFullDisk || Self.isUserScopePath(record.path) else { continue }
            if let requiredPathExtension {
                guard record.name.lowercased().hasSuffix(".\(requiredPathExtension.lowercased())") else { continue }
            }
            if let dateInterval {
                let modifiedAt = record.modifiedAt ?? (canLazyReadDates ? Self.fileModifiedAt(path: record.path) : nil)
                guard let modifiedAt else { continue }
                let modified = Date(timeIntervalSince1970: modifiedAt)
                guard modified >= dateInterval.start, modified < dateInterval.end else { continue }
            }

            var score = 0.24
            let haystack = "\(record.searchName) \(record.path.lowercased())"
            for token in tokens where haystack.contains(token) {
                score += record.searchName.contains(token) ? 0.08 : 0.03
            }
            if let modifiedAt = record.modifiedAt {
                let age = max(0, Date().timeIntervalSince1970 - modifiedAt)
                score += max(0, min(0.08, 0.08 - age / 31_536_000 * 0.02))
            }
            candidates.append((record, min(score, 0.52)))
        }

        return candidates
            .sorted {
                $0.score == $1.score
                    ? ($0.record.modifiedAt ?? 0) > ($1.record.modifiedAt ?? 0)
                    : $0.score > $1.score
            }
            .prefix(limit)
            .map { item in
                let url = URL(fileURLWithPath: item.record.path)
                return SearchResult(
                    id: "file:\(item.record.path)",
                    kind: .file,
                    title: item.record.name,
                    subtitle: item.record.path,
                    score: item.score,
                    action: .openFile(url)
                )
            }
    }

    func applyEvents(_ events: [FileIndexEvent], requiresFullRebuild: Bool, includeFullDisk: Bool) async {
        guard !events.isEmpty else { return }
        if requiresFullRebuild || events.count > 512 {
            _ = await rebuild(includeFullDisk: includeFullDisk)
            return
        }

        guard var snapshot = records, index != nil else { return }
        var changed = false

        for event in events {
            let path = event.path
            let removed = event.flags.has(kFSEventStreamEventFlagItemRemoved)
                || event.flags.has(kFSEventStreamEventFlagItemRenamed)
                || !FileManager.default.fileExists(atPath: path)

            if removed {
                let prefix = path.hasSuffix("/") ? path : "\(path)/"
                let count = snapshot.count
                snapshot.removeAll { $0.path == path || $0.path.hasPrefix(prefix) }
                changed = changed || snapshot.count != count
            }

            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard !LauncherPreferences.isFileSearchPathExcluded(path) else { continue }
            let fresh = FileIndexScanner.records(forChangedPath: path)
            guard !fresh.isEmpty else { continue }
            if fresh.count > FileIndexScanner.changedPathRecordLimit {
                _ = await rebuild(includeFullDisk: includeFullDisk)
                return
            }
            let paths = Set(fresh.map(\.path))
            snapshot.removeAll { paths.contains($0.path) }
            snapshot.append(contentsOf: fresh)
            changed = true
        }

        guard changed else { return }
        snapshot.sort { $0.searchName < $1.searchName }
        records = snapshot
        index = FileRecordIndex(records: snapshot)
        progress = FileIndexProgress(scannedCount: snapshot.count, indexedCount: snapshot.count, rootPath: "", isFinished: true)
        save(snapshot)
        await SemanticVectorIndexStore.shared.invalidate(events)
    }

    func vectorCandidates(includeFullDisk: Bool) -> [FileVectorCandidate] {
        let snapshot = records ?? load()
        return snapshot.compactMap { record in
            guard Self.isVectorIndexable(record) else { return nil }
            guard !LauncherPreferences.isFileSearchPathExcluded(record.path) else { return nil }
            guard includeFullDisk || Self.isUserScopePath(record.path) else { return nil }
            return FileVectorCandidate(path: record.path, title: record.name, modifiedAt: record.modifiedAt)
        }
        .sorted {
            let lhsDate = $0.modifiedAt ?? 0
            let rhsDate = $1.modifiedAt ?? 0
            return lhsDate == rhsDate ? $0.path < $1.path : lhsDate > rhsDate
        }
    }

    private func load() -> [FileRecord] {
        if let records {
            if index == nil {
                index = FileRecordIndex(records: records)
            }
            return records
        }
        let loaded = StorageCodec.load(
            [FileRecord].self,
            from: indexURL,
            legacyJSONURL: legacyIndexURL,
            default: []
        )
        records = loaded
        index = FileRecordIndex(records: loaded)
        return loaded
    }

    private func indexedCandidates(query: String, limit: Int) -> [Int] {
        guard let index else { return [] }
        let candidates = index.candidates(for: query, limit: limit)
        guard !candidates.isEmpty else { return [] }
        return candidates
    }

    private func save(_ records: [FileRecord]) {
        try? StorageCodec.save(records, to: indexURL)
    }

    func applyCurrentExclusions() async {
        var snapshot = records ?? load()
        let oldCount = snapshot.count
        snapshot.removeAll { LauncherPreferences.isFileSearchPathExcluded($0.path) }
        guard snapshot.count != oldCount else { return }
        records = snapshot
        index = FileRecordIndex(records: snapshot)
        progress = FileIndexProgress(scannedCount: snapshot.count, indexedCount: snapshot.count, rootPath: "", isFinished: true)
        save(snapshot)
        await SemanticVectorIndexStore.shared.pruneExcludedPaths()
    }

    private func setProgress(_ progress: FileIndexProgress) {
        self.progress = progress
    }

    private static func isUserScopePath(_ path: String) -> Bool {
        guard !LauncherPreferences.isFileSearchPathExcluded(path) else { return false }
        let excludedPrefixes = [
            "/System/",
            "/Library/",
            "/private/",
            "/usr/",
            "/bin/",
            "/sbin/"
        ]
        return !excludedPrefixes.contains { path.hasPrefix($0) }
    }

    private static func fileModifiedAt(path: String) -> TimeInterval? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return (values?.contentModificationDate ?? values?.creationDate)?.timeIntervalSince1970
    }

    private static func isVectorIndexable(_ record: FileRecord) -> Bool {
        guard record.kind == .document || record.kind == .code else { return false }
        let ext = URL(fileURLWithPath: record.path).pathExtension.lowercased()
        let allowed = [
            "pdf", "txt", "rtf", "md", "csv", "doc", "docx", "pages", "ppt", "pptx",
            "swift", "js", "ts", "tsx", "jsx", "py", "rs", "go", "java", "c", "cc",
            "cpp", "h", "hpp", "sh", "zsh", "json", "yaml", "yml", "toml"
        ]
        return allowed.contains(ext)
    }
}

private struct FileRecordIndex {
    private let prefixIndex: [String: [Int]]
    private let trigramIndex: [String: [Int]]

    init(records: [FileRecord]) {
        var prefixes: [String: [Int]] = [:]
        var trigrams: [String: [Int]] = [:]

        for (offset, record) in records.enumerated() {
            for token in record.tokens {
                for prefix in Self.prefixes(for: token) {
                    prefixes[prefix, default: []].append(offset)
                }
            }

            for trigram in Self.trigrams(for: record.searchName) {
                trigrams[trigram, default: []].append(offset)
            }
        }

        prefixIndex = prefixes
        trigramIndex = trigrams
    }

    func candidates(for query: String, limit: Int) -> [Int] {
        let tokens = FileRecord.tokens(in: query)
        guard !tokens.isEmpty else { return [] }

        var seen = Set<Int>()
        var candidates: [Int] = []
        candidates.reserveCapacity(limit)

        for token in tokens {
            append(prefixIndex[Self.indexKey(for: token)], to: &candidates, seen: &seen, limit: limit)
        }

        if candidates.count < limit / 2, query.count >= 3 {
            for trigram in Self.trigrams(for: query) {
                append(trigramIndex[trigram], to: &candidates, seen: &seen, limit: limit)
                if candidates.count >= limit { break }
            }
        }

        return candidates
    }

    private func append(_ values: [Int]?, to candidates: inout [Int], seen: inout Set<Int>, limit: Int) {
        guard let values else { return }
        for value in values {
            guard candidates.count < limit else { return }
            if seen.insert(value).inserted {
                candidates.append(value)
            }
        }
    }

    private static func prefixes(for token: String) -> [String] {
        guard token.count >= 2 else { return [] }
        let capped = String(token.prefix(6))
        var output: [String] = []
        output.reserveCapacity(max(0, capped.count - 1))

        var end = capped.index(capped.startIndex, offsetBy: 2)
        while true {
            output.append(String(capped[..<end]))
            guard end < capped.endIndex else { break }
            capped.formIndex(after: &end)
        }

        return output
    }

    private static func trigrams(for value: String) -> Set<String> {
        guard value.count >= 3 else { return [] }
        var output = Set<String>()
        var start = value.startIndex

        while let end = value.index(start, offsetBy: 3, limitedBy: value.endIndex) {
            output.insert(String(value[start..<end]))
            guard end < value.endIndex else { break }
            value.formIndex(after: &start)
        }

        return output
    }

    private static func indexKey(for token: String) -> String {
        guard token.count > 6 else { return token }
        return String(token.prefix(6))
    }
}

private enum FileIndexScanner {
    private static let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isHiddenKey, .isPackageKey]
    static let changedPathRecordLimit = 2_048

    static func scan(
        includeFullDisk: Bool,
        shouldPause: (@Sendable () async -> Bool)? = nil,
        progress: (@Sendable (FileIndexProgress) async -> Void)? = nil
    ) async -> [FileRecord] {
        await Task.detached(priority: .utility) {
            await scanSync(includeFullDisk: includeFullDisk, shouldPause: shouldPause, progress: progress)
        }.value
    }

    private static func scanSync(
        includeFullDisk: Bool,
        shouldPause: (@Sendable () async -> Bool)?,
        progress: (@Sendable (FileIndexProgress) async -> Void)?
    ) async -> [FileRecord] {
        let fileManager = FileManager.default
        var seen = Set<String>()
        var records: [FileRecord] = []
        var scannedCount = 0
        var lastProgressNanos = DispatchTime.now().uptimeNanoseconds
        records.reserveCapacity(64_000)

        for root in roots(includeFullDisk: includeFullDisk) {
            guard !LauncherPreferences.isFileSearchPathExcluded(root.path) else { continue }
            await progress?(FileIndexProgress(
                scannedCount: scannedCount,
                indexedCount: records.count,
                rootPath: root.path,
                isFinished: false
            ))

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard !Task.isCancelled else { return records }
                scannedCount += 1
                if scannedCount.isMultiple(of: 200) {
                    guard await pauseIfNeeded(shouldPause) else { return records }
                }
                let values = try? url.resourceValues(forKeys: keys)

                if values?.isDirectory == true {
                    if shouldSkipDirectory(url) || LauncherPreferences.isFileSearchPathExcluded(url.path) {
                        enumerator.skipDescendants()
                        continue
                    }
                    if values?.isPackage == true {
                        enumerator.skipDescendants()
                    }
                }

                guard let record = FileRecord(url: url, values: values), seen.insert(record.path).inserted else { continue }
                records.append(record)
                let now = DispatchTime.now().uptimeNanoseconds
                if now - lastProgressNanos >= 250_000_000 {
                    lastProgressNanos = now
                    await progress?(FileIndexProgress(
                        scannedCount: scannedCount,
                        indexedCount: records.count,
                        rootPath: root.path,
                        isFinished: false
                    ))
                }
            }
        }

        records.sort { $0.searchName < $1.searchName }
        await progress?(FileIndexProgress(
            scannedCount: scannedCount,
            indexedCount: records.count,
            rootPath: "",
            isFinished: true
        ))
        return records
    }

    private static func pauseIfNeeded(_ shouldPause: (@Sendable () async -> Bool)?) async -> Bool {
        while await shouldPause?() == true {
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return !Task.isCancelled
    }

    static func records(forChangedPath path: String) -> [FileRecord] {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: keys)
        guard !LauncherPreferences.isFileSearchPathExcluded(url.path) else { return [] }
        guard values?.isHidden != true, !url.lastPathComponent.hasPrefix(".") else { return [] }
        guard let root = FileRecord(url: url, values: values) else { return [] }
        guard values?.isDirectory == true, values?.isPackage != true, !shouldSkipDirectory(url) else {
            return [root]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [root] }

        var records = [root]
        while let child = enumerator.nextObject() as? URL {
            let childValues = try? child.resourceValues(forKeys: keys)
            if childValues?.isDirectory == true {
                if shouldSkipDirectory(child) || LauncherPreferences.isFileSearchPathExcluded(child.path) {
                    enumerator.skipDescendants()
                    continue
                }
                if childValues?.isPackage == true {
                    enumerator.skipDescendants()
                }
            }

            guard let record = FileRecord(url: child, values: childValues) else { continue }
            records.append(record)
            if records.count > changedPathRecordLimit { break }
        }

        return records
    }

    fileprivate static func roots(includeFullDisk: Bool) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [URL]
        if includeFullDisk {
            roots = [
                home,
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: "/System/Applications", isDirectory: true),
                URL(fileURLWithPath: "/Users/Shared", isDirectory: true),
                URL(fileURLWithPath: "/Volumes", isDirectory: true)
            ]
        } else {
            roots = ["Desktop", "Documents", "Downloads", "Applications", "Pictures", "Movies", "Music"]
                .map { home.appendingPathComponent($0, isDirectory: true) }
        }
        return roots.filter { !LauncherPreferences.isFileSearchPathExcluded($0.path) }
    }

    private static func shouldSkipDirectory(_ url: URL) -> Bool {
        let path = url.path
        let name = url.lastPathComponent
        let skippedNames = [".git", ".Trash", "Caches", "DerivedData", "node_modules", "Pods", "target", ".build", "__pycache__"]
        return skippedNames.contains(name)
            || path.contains("/Library/Caches/")
            || path.contains("/Library/Developer/Xcode/DerivedData/")
            || path.contains("/Library/Application Support/Code/Cache")
    }
}

private struct FileRecord: Codable, Sendable {
    let path: String
    let name: String
    let searchName: String
    let tokens: [String]
    let kind: FileRecordKind
    let modifiedAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case path
        case name
        case searchName
        case kind
        case modifiedAt
    }

    init?(url: URL, values: URLResourceValues?) {
        let name = url.lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("."), values?.isHidden != true else { return nil }
        path = url.path
        self.name = name
        searchName = name.lowercased()
        tokens = Self.tokens(in: searchName)
        kind = FileRecordKind(url: url, isDirectory: values?.isDirectory == true)
        modifiedAt = values?.contentModificationDate?.timeIntervalSince1970
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        searchName = try container.decode(String.self, forKey: .searchName)
        tokens = Self.tokens(in: searchName)
        kind = try container.decode(FileRecordKind.self, forKey: .kind)
        modifiedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .modifiedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(searchName, forKey: .searchName)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
    }

    static func tokens(in value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    func tokenPrefixesContain(_ query: String) -> Bool {
        tokens.contains { $0.hasPrefix(query) }
    }
}

private enum FileRecordKind: String, Codable, Sendable {
    case folder
    case image
    case document
    case code
    case other

    init(url: URL, isDirectory: Bool) {
        guard !isDirectory else {
            self = .folder
            return
        }

        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "svg":
            self = .image
        case "pdf", "doc", "docx", "pages", "txt", "rtf", "md", "csv", "xls", "xlsx", "ppt", "pptx", "key", "numbers":
            self = .document
        case "swift", "js", "ts", "tsx", "jsx", "py", "rs", "go", "java", "c", "cc", "cpp", "h", "hpp", "sh", "zsh", "json", "yaml", "yml", "toml":
            self = .code
        default:
            self = .other
        }
    }
}

private extension FileTypeFilter {
    func accepts(_ kind: FileRecordKind) -> Bool {
        switch self {
        case .all:
            return true
        case .common:
            return kind != .other
        case .image:
            return kind == .image
        case .document:
            return kind == .document
        case .code:
            return kind == .code
        case .pdf:
            return kind == .document
        }
    }
}

@MainActor
final class FileIndexWatcher {
    private struct WatcherSettings: Equatable {
        let fullDiskIndexingEnabled: Bool
        let fullDiskWarmupCompleted: Bool
        let excludedPathSignature: String

        static var current: Self {
            WatcherSettings(
                fullDiskIndexingEnabled: LauncherPreferences.fullDiskIndexingEnabled,
                fullDiskWarmupCompleted: LauncherPreferences.fullDiskWarmupCompleted,
                excludedPathSignature: LauncherPreferences.fileSearchExcludedPaths.joined(separator: "\n")
            )
        }
    }

    private enum Timing {
        static let fsLatency: CFTimeInterval = 2
        static let debounce: TimeInterval = 2
        static let startupDelay: Duration = .seconds(30)
        static let restartDelay: Duration = .seconds(2)
    }

    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var pendingEvents: [FileIndexEvent] = []
    private var requiresFullRebuild = false
    private var startTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var watcherSettings = WatcherSettings.current
    private lazy var callbackBox = FileIndexWatcherCallbackBox(watcher: self)

    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncWatcherSettings()
            }
        }
        scheduleStart(delay: Timing.startupDelay)
    }

    private func syncWatcherSettings() {
        let settings = WatcherSettings.current
        guard settings != watcherSettings else { return }

        watcherSettings = settings
        scheduleStart(delay: Timing.restartDelay)
    }

    private func scheduleStart(delay: Duration) {
        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            guard LauncherPreferences.fullDiskWarmupCompleted else {
                self.stop()
                return
            }

            await FileIndexStore.shared.prewarm()
            self.restart()
        }
    }

    private func restart() {
        stop()
        let paths = FileIndexScanner.roots(includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled)
            .map(\.path)
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackBox).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let since = LauncherPreferences.fileIndexLastEventID == 0
            ? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
            : FSEventStreamEventId(LauncherPreferences.fileIndexLastEventID)

        stream = FSEventStreamCreate(
            nil,
            fileIndexWatcherCallback,
            &context,
            paths as CFArray,
            since,
            Timing.fsLatency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    private func stop() {
        pending?.cancel()
        pending = nil
        pendingEvents.removeAll(keepingCapacity: true)
        requiresFullRebuild = false

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    fileprivate func receive(_ events: [FileIndexEvent], needsFullRebuild: Bool, lastEventID: FSEventStreamEventId) {
        if lastEventID > 0 {
            LauncherPreferences.fileIndexLastEventID = UInt64(lastEventID)
        }
        pendingEvents.append(contentsOf: events)
        requiresFullRebuild = requiresFullRebuild || needsFullRebuild
        pending?.cancel()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flush()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.debounce, execute: work)
    }

    private func flush() {
        let events = pendingEvents
        let rebuild = requiresFullRebuild
        pendingEvents.removeAll(keepingCapacity: true)
        requiresFullRebuild = false
        guard !events.isEmpty else { return }

        Task.detached(priority: .utility) {
            await FileIndexStore.shared.applyEvents(
                events,
                requiresFullRebuild: rebuild,
                includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled
            )
        }
    }
}

private let fileIndexWatcherCallback: FSEventStreamCallback = { _, contextInfo, count, eventPaths, eventFlags, eventIDs in
    guard let contextInfo else { return }
    let callbackBox = Unmanaged<FileIndexWatcherCallbackBox>.fromOpaque(contextInfo).takeUnretainedValue()
    let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
    var events: [FileIndexEvent] = []
    events.reserveCapacity(count)
    var needsFullRebuild = false
    var lastID: FSEventStreamEventId = 0

    for index in 0..<count {
        let flags = eventFlags[index]
        lastID = eventIDs[index]
        if flags.has(kFSEventStreamEventFlagMustScanSubDirs)
            || flags.has(kFSEventStreamEventFlagRootChanged)
            || flags.has(kFSEventStreamEventFlagEventIdsWrapped) {
            needsFullRebuild = true
        }
        guard let path = paths[index] else { continue }
        events.append(FileIndexEvent(path: String(cString: path), flags: flags))
    }

    let watcherAddress = callbackBox.watcherAddress
    Task { @MainActor in
        guard let pointer = UnsafeMutableRawPointer(bitPattern: watcherAddress) else { return }
        let watcher = Unmanaged<FileIndexWatcher>.fromOpaque(pointer).takeUnretainedValue()
        watcher.receive(events, needsFullRebuild: needsFullRebuild, lastEventID: lastID)
    }
}

private extension FSEventStreamEventFlags {
    func has(_ flag: Int) -> Bool {
        self & FSEventStreamEventFlags(flag) != 0
    }
}
