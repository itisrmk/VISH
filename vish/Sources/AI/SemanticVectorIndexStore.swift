import Foundation

struct SemanticVectorIndexProgress: Sendable {
    let phase: String
    let totalCount: Int
    let embeddedCount: Int
    let skippedCount: Int
    let isRunning: Bool
    let isFinished: Bool
    let model: String

    static let idle = SemanticVectorIndexProgress(
        phase: "Semantic index idle",
        totalCount: 0,
        embeddedCount: 0,
        skippedCount: 0,
        isRunning: false,
        isFinished: false,
        model: ""
    )
}

actor SemanticVectorIndexStore {
    static let shared = SemanticVectorIndexStore()

    private let indexURL: URL
    private var records: [String: SemanticVectorRecord]?
    private var progress = SemanticVectorIndexProgress.idle

    private init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        indexURL = base.appendingPathComponent("vish", isDirectory: true).appendingPathComponent("file-vectors.plist")
    }

    func currentProgress() -> SemanticVectorIndexProgress {
        progress
    }

    func indexedCount() -> Int {
        load().count
    }

    func invalidate(_ events: [FileIndexEvent]) {
        guard !events.isEmpty else { return }
        var snapshot = load()
        var changed = false
        for event in events {
            let prefix = event.path.hasSuffix("/") ? event.path : "\(event.path)/"
            let count = snapshot.count
            snapshot = snapshot.filter { item in
                item.key != event.path && !item.key.hasPrefix(prefix)
            }
            changed = changed || snapshot.count != count
        }
        guard changed else { return }
        records = snapshot
        try? StorageCodec.save(Array(snapshot.values), to: indexURL)
    }

    func search(
        _ query: SemanticFileQuery,
        seeds: [SearchResult],
        limit: Int
    ) async -> [SearchResult] {
        guard LauncherPreferences.localAIEnabled, !query.original.isEmpty else { return [] }
        do {
            guard let model = try await LocalAIClient.selectedIndexEmbeddingModel() else { return [] }
            let queryVector = try await normalizedEmbedding(for: query.original, model: model)
            return vectorResults(queryVector: queryVector, query: query, model: model, limit: limit)
        } catch {
            return []
        }
    }

    func rebuild(includeFullDisk: Bool) async -> SemanticVectorIndexProgress {
        guard LauncherPreferences.localAIEnabled else {
            progress = SemanticVectorIndexProgress(
                phase: "Local AI is off",
                totalCount: 0,
                embeddedCount: 0,
                skippedCount: 0,
                isRunning: false,
                isFinished: false,
                model: ""
            )
            return progress
        }

        do {
            guard let model = try await LocalAIClient.selectedIndexEmbeddingModel() else {
                progress = SemanticVectorIndexProgress(
                    phase: "Fast embedding model needed",
                    totalCount: 0,
                    embeddedCount: 0,
                    skippedCount: 0,
                    isRunning: false,
                    isFinished: false,
                    model: LocalAIClient.recommendedEmbeddingModel
                )
                return progress
            }
            let candidates = await FileIndexStore.shared.vectorCandidates(includeFullDisk: includeFullDisk)
            let candidatePaths = Set(candidates.map(\.path))
            var snapshot = load().filter { candidatePaths.contains($0.key) }
            var inputs: [String] = []
            var pending: [PendingVector] = []
            var embedded = 0
            var skipped = 0

            inputs.reserveCapacity(Self.backgroundBatchSize)
            pending.reserveCapacity(Self.backgroundBatchSize)
            progress = SemanticVectorIndexProgress(
                phase: "Indexing semantics",
                totalCount: candidates.count,
                embeddedCount: 0,
                skippedCount: 0,
                isRunning: true,
                isFinished: false,
                model: model
            )

            for (offset, candidate) in candidates.enumerated() {
                try Task.checkCancellation()
                try await pauseForUserInteraction()

                let url = URL(fileURLWithPath: candidate.path)
                guard FileManager.default.fileExists(atPath: candidate.path),
                      let modifiedAt = candidate.modifiedAt ?? fileDate(url)?.timeIntervalSince1970
                else {
                    skipped += 1
                    updateProgress(total: candidates.count, embedded: embedded, skipped: skipped, model: model)
                    continue
                }

                if let record = snapshot[candidate.path],
                   record.model == model,
                   record.modifiedAt == modifiedAt {
                    skipped += 1
                    if offset.isMultiple(of: 64) {
                        updateProgress(total: candidates.count, embedded: embedded, skipped: skipped, model: model)
                    }
                    continue
                }

                let text = await Self.embeddingText(for: candidate, url: url)
                inputs.append(text)
                pending.append(PendingVector(title: candidate.title, path: candidate.path, modifiedAt: modifiedAt))

                if inputs.count >= Self.backgroundBatchSize {
                    embedded += try await storeEmbeddings(inputs: inputs, pending: pending, model: model, snapshot: &snapshot)
                    inputs.removeAll(keepingCapacity: true)
                    pending.removeAll(keepingCapacity: true)
                    updateProgress(total: candidates.count, embedded: embedded, skipped: skipped, model: model)
                    if embedded.isMultiple(of: Self.saveEveryEmbeddings) {
                        records = snapshot
                        try? StorageCodec.save(Array(snapshot.values), to: indexURL)
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
            }

            if !inputs.isEmpty {
                embedded += try await storeEmbeddings(inputs: inputs, pending: pending, model: model, snapshot: &snapshot)
            }

            records = snapshot
            try? StorageCodec.save(Array(snapshot.values), to: indexURL)
            progress = SemanticVectorIndexProgress(
                phase: "Semantic index ready",
                totalCount: candidates.count,
                embeddedCount: embedded,
                skippedCount: skipped,
                isRunning: false,
                isFinished: true,
                model: model
            )
        } catch is CancellationError {
            progress = SemanticVectorIndexProgress(
                phase: "Semantic indexing cancelled",
                totalCount: progress.totalCount,
                embeddedCount: progress.embeddedCount,
                skippedCount: progress.skippedCount,
                isRunning: false,
                isFinished: false,
                model: progress.model
            )
        } catch {
            progress = SemanticVectorIndexProgress(
                phase: "Semantic indexing unavailable",
                totalCount: progress.totalCount,
                embeddedCount: progress.embeddedCount,
                skippedCount: progress.skippedCount,
                isRunning: false,
                isFinished: false,
                model: progress.model
            )
        }

        return progress
    }

    private func storeEmbeddings(
        inputs: [String],
        pending: [PendingVector],
        model: String,
        snapshot: inout [String: SemanticVectorRecord]
    ) async throws -> Int {
        let vectors = try await LocalAIClient.embeddings(for: inputs, model: model, keepAlive: "2m")
        var stored = 0
        for (pending, vector) in zip(pending, vectors) {
            guard let normalized = Self.normalized(vector), !normalized.isEmpty else { continue }
            snapshot[pending.path] = SemanticVectorRecord(
                path: pending.path,
                title: pending.title,
                modifiedAt: pending.modifiedAt,
                model: model,
                dimensions: normalized.count,
                vectorData: Self.data(from: normalized)
            )
            stored += 1
        }
        return stored
    }

    private func vectorResults(
        queryVector: [Float],
        query: SemanticFileQuery,
        model: String,
        limit: Int
    ) -> [SearchResult] {
        let keepLimit = max(limit * 4, limit)
        var ranked: [(SearchResult, Float)] = []
        ranked.reserveCapacity(keepLimit)

        for record in load().values {
            guard record.model == model, record.dimensions == queryVector.count else { continue }
            let url = URL(fileURLWithPath: record.path)
            guard accepts(url, modifiedAt: record.modifiedAt, query: query) else { continue }

            let similarity = Self.dot(queryVector, record.vectorData, dimensions: record.dimensions)
            guard similarity >= Self.minimumSimilarity else { continue }
            ranked.append((SearchResult(
                id: "file:\(record.path)",
                kind: .file,
                title: record.title,
                subtitle: "Semantic match - \(record.path)",
                score: 0.54 + Double(min(max(similarity, 0), 1)) * 0.40,
                action: .openFile(url)
            ), similarity))

            if ranked.count > keepLimit * 2 {
                ranked.sort { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 > $1.1 }
                ranked.removeSubrange(keepLimit...)
            }
        }

        ranked.sort { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 > $1.1 }

        var results: [SearchResult] = []
        results.reserveCapacity(limit)
        let fileManager = FileManager.default
        for (result, _) in ranked {
            guard case .openFile(let url) = result.action,
                  fileManager.fileExists(atPath: url.path)
            else { continue }
            results.append(result)
            if results.count == limit { break }
        }
        return results
    }

    private func normalizedEmbedding(for text: String, model: String) async throws -> [Float] {
        let values = try await LocalAIClient.embeddings(for: [text], model: model, keepAlive: "2m").first ?? []
        return Self.normalized(values) ?? []
    }

    private func load() -> [String: SemanticVectorRecord] {
        if let records { return records }
        let loaded = StorageCodec.load([SemanticVectorRecord].self, from: indexURL, default: [])
        let mapped = Dictionary(uniqueKeysWithValues: loaded.map { ($0.path, $0) })
        records = mapped
        return mapped
    }

    private static func embeddingText(for candidate: FileVectorCandidate, url: URL) async -> String {
        await Task.detached(priority: .utility) {
            var parts = [
                "File: \(candidate.title)",
                "Folder: \(url.deletingLastPathComponent().lastPathComponent)",
                "Path: \(candidate.path)"
            ]
            switch FilePreviewReader.preview(
                for: url,
                byteLimit: Self.previewByteLimit,
                maxCharacters: Self.previewMaxCharacters,
                pdfPageLimit: Self.previewPDFPageLimit
            ) {
            case .available(let text):
                parts.append("Preview:\n\(text)")
            case .unavailable:
                break
            }
            return parts.joined(separator: "\n")
        }.value
    }

    private func updateProgress(total: Int, embedded: Int, skipped: Int, model: String) {
        progress = SemanticVectorIndexProgress(
            phase: "Indexing semantics",
            totalCount: total,
            embeddedCount: embedded,
            skippedCount: skipped,
            isRunning: true,
            isFinished: false,
            model: model
        )
    }

    private func pauseForUserInteraction() async throws {
        while await FileIndexStore.shared.isInteractiveActivityActive() {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(220))
        }
    }

    private func accepts(_ url: URL, modifiedAt: TimeInterval, query: SemanticFileQuery) -> Bool {
        if let required = query.requiredPathExtension,
           url.pathExtension.localizedCaseInsensitiveCompare(required) != .orderedSame {
            return false
        }
        if let interval = query.dateInterval {
            let modified = Date(timeIntervalSince1970: modifiedAt)
            guard modified >= interval.start, modified < interval.end else { return false }
        }
        return true
    }

    private static func normalized(_ vector: [Float]) -> [Float]? {
        var normSquared: Float = 0
        for value in vector {
            normSquared += value * value
        }
        guard normSquared > 0 else { return nil }
        let norm = sqrt(normSquared)
        return vector.map { $0 / norm }
    }

    private static func dot(_ lhs: [Float], _ rhs: Data, dimensions: Int) -> Float {
        guard lhs.count == dimensions, rhs.count == dimensions * MemoryLayout<Float>.stride else {
            return -.greatestFiniteMagnitude
        }
        return rhs.withUnsafeBytes { buffer in
            let values = buffer.bindMemory(to: Float.self)
            guard values.count == dimensions else { return -.greatestFiniteMagnitude }
            var output: Float = 0
            for index in 0..<dimensions {
                output += lhs[index] * values[index]
            }
            return output
        }
    }

    private static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func fileDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate
    }

    private static let backgroundBatchSize = 16
    private static let saveEveryEmbeddings = 256
    private static let previewByteLimit = 4_096
    private static let previewMaxCharacters = 1_200
    private static let previewPDFPageLimit = 1
    private static let minimumSimilarity: Float = 0.20
}

private struct PendingVector: Sendable {
    let title: String
    let path: String
    let modifiedAt: TimeInterval
}

private struct SemanticVectorRecord: Codable, Sendable {
    let path: String
    let title: String
    let modifiedAt: TimeInterval
    let model: String
    let dimensions: Int
    let vectorData: Data
}
