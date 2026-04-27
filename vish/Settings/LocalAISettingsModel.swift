import Foundation

@MainActor
final class LocalAISettingsModel: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var isInstallingChatModel = false
    @Published private(set) var isInstallingEmbeddingModel = false
    @Published private(set) var installingModel = ""
    @Published private(set) var status = "Not checked"
    @Published private(set) var version = ""
    @Published private(set) var models: [String] = []
    @Published private(set) var availableCapacityBytes: Int64 = 0

    private var task: Task<Void, Never>?

    var symbolName: String {
        if isChecking { return "arrow.triangle.2.circlepath" }
        return models.isEmpty ? "bolt.slash" : "bolt.circle"
    }

    func modelChoices(current: String) -> [LocalAIModelChoice] {
        let installedIDs = Set(models.map(Self.canonical))
        let capacity = availableCapacityBytes == 0 ? Self.availableCapacityBytes() : availableCapacityBytes
        var choices = Self.curatedChatModels(ollamaVersion: version).map {
            if installedIDs.contains($0.id) || Self.hasEnoughSpace(for: $0.id, availableCapacityBytes: capacity) {
                return $0
            }
            return $0.withSubtitle(Self.notEnoughDiskSubtitle(for: $0.id))
        }
        let known = Set(choices.map(\.id))
        let installed = models
            .filter(LocalAIClient.isLikelyChatModel)
            .filter { !known.contains(Self.canonical($0)) }
            .map { LocalAIModelChoice(id: $0, title: $0, subtitle: "Installed") }
        choices.append(contentsOf: installed)

        let currentID = Self.canonical(current)
        if !currentID.isEmpty,
           LocalAIClient.isLikelyChatModel(currentID),
           (Self.supportsQwen35(version) || !currentID.hasPrefix("qwen3.5:")),
           !choices.contains(where: { $0.id == currentID }) {
            let subtitle = installedIDs.contains(currentID) || Self.hasEnoughSpace(for: currentID, availableCapacityBytes: capacity)
                ? "Custom"
                : Self.notEnoughDiskSubtitle(for: currentID)
            choices.insert(LocalAIModelChoice(id: currentID, title: currentID, subtitle: subtitle), at: 0)
        }
        return choices
    }

    func embeddingModelChoices(current: String) -> [String] {
        var choices = models.filter(LocalAIClient.isLikelyEmbeddingModel)
        if !current.isEmpty, !choices.contains(current) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    var hasEmbeddingModel: Bool {
        models.contains(where: LocalAIClient.isLikelyEmbeddingModel)
    }

    func isModelInstalled(_ model: String) -> Bool {
        let id = Self.canonical(model)
        guard !id.isEmpty else { return true }
        return models.contains { Self.canonical($0) == id }
    }

    func shouldInstallChatModel(_ model: String) -> Bool {
        let id = Self.canonical(model)
        let capacity = availableCapacityBytes == 0 ? Self.availableCapacityBytes() : availableCapacityBytes
        return !id.isEmpty
            && !isModelInstalled(id)
            && Self.hasEnoughSpace(for: id, availableCapacityBytes: capacity)
    }

    func isChatModelDiskBlocked(_ model: String) -> Bool {
        let id = Self.canonical(model)
        let capacity = availableCapacityBytes == 0 ? Self.availableCapacityBytes() : availableCapacityBytes
        return !id.isEmpty
            && !isModelInstalled(id)
            && !Self.hasEnoughSpace(for: id, availableCapacityBytes: capacity)
    }

    func refresh(baseURL: String) {
        task?.cancel()
        isChecking = true
        isInstallingChatModel = false
        isInstallingEmbeddingModel = false
        installingModel = ""
        status = "Checking Ollama..."
        version = ""

        task = Task {
            do {
                let snapshot = try await Self.fetch(baseURL: baseURL)
                guard !Task.isCancelled else { return }
                version = snapshot.version
                models = snapshot.models
                availableCapacityBytes = snapshot.availableCapacityBytes
                Self.migrateUnsupportedChatSelection(
                    version: snapshot.version,
                    models: snapshot.models
                )
                status = snapshot.models.isEmpty
                    ? "Ollama reachable. Install a model."
                    : "\(snapshot.models.count) local model\(snapshot.models.count == 1 ? "" : "s") ready."
            } catch {
                guard !Task.isCancelled else { return }
                version = ""
                models = []
                status = "Ollama not reachable."
            }
            isChecking = false
        }
    }

    func installChatModel(baseURL: String, model: String) {
        let target = Self.canonical(model)
        guard !target.isEmpty else { return }
        let capacity = availableCapacityBytes == 0 ? Self.availableCapacityBytes() : availableCapacityBytes
        guard Self.hasEnoughSpace(for: target, availableCapacityBytes: capacity) else {
            status = Self.notEnoughDiskMessage(for: target)
            return
        }
        task?.cancel()
        isInstallingChatModel = true
        isInstallingEmbeddingModel = false
        isChecking = false
        installingModel = target
        status = "Installing \(target)..."

        task = Task {
            do {
                try await Self.pull(baseURL: baseURL, model: target)
                LauncherPreferences.localAIModel = target
                let snapshot = try await Self.fetch(baseURL: baseURL)
                guard !Task.isCancelled else { return }
                version = snapshot.version
                models = snapshot.models
                availableCapacityBytes = snapshot.availableCapacityBytes
                Self.migrateUnsupportedChatSelection(
                    version: snapshot.version,
                    models: snapshot.models
                )
                status = "\(target) ready."
            } catch {
                guard !Task.isCancelled else { return }
                status = Self.installErrorMessage(error, model: target)
            }
            isInstallingChatModel = false
            installingModel = ""
        }
    }

    func installRecommendedEmbeddingModel(baseURL: String) {
        let target = LocalAIClient.recommendedEmbeddingModel
        let capacity = availableCapacityBytes == 0 ? Self.availableCapacityBytes() : availableCapacityBytes
        guard Self.hasEnoughSpace(for: target, availableCapacityBytes: capacity) else {
            status = Self.notEnoughDiskMessage(for: target)
            return
        }
        task?.cancel()
        isInstallingChatModel = false
        isInstallingEmbeddingModel = true
        isChecking = false
        installingModel = target
        status = "Installing \(target)..."

        task = Task {
            do {
                try await Self.pull(baseURL: baseURL, model: target)
                LauncherPreferences.localAIEmbeddingModel = target
                let snapshot = try await Self.fetch(baseURL: baseURL)
                guard !Task.isCancelled else { return }
                version = snapshot.version
                models = snapshot.models
                availableCapacityBytes = snapshot.availableCapacityBytes
                Self.migrateUnsupportedChatSelection(
                    version: snapshot.version,
                    models: snapshot.models
                )
                status = "Fast embedding model ready."
            } catch {
                guard !Task.isCancelled else { return }
                status = Self.installErrorMessage(error, model: LocalAIClient.recommendedEmbeddingModel)
            }
            isInstallingEmbeddingModel = false
            installingModel = ""
        }
    }

    private nonisolated static func fetch(baseURL: String) async throws -> Snapshot {
        let base = normalizedBaseURL(baseURL)
        async let version: VersionResponse = request("\(base)/api/version")
        async let tags: TagsResponse = request("\(base)/api/tags")
        return try await Snapshot(
            version: version.version ?? "unknown",
            models: tags.models.map(\.name).sorted(),
            availableCapacityBytes: availableCapacityBytes()
        )
    }

    private nonisolated static func request<T: Decodable>(_ string: String) async throws -> T {
        guard let url = URL(string: string) else { throw LocalAISettingsError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalAISettingsError.badResponse(message ?? "Ollama request failed.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private nonisolated static func pull(baseURL: String, model: String) async throws {
        guard let url = URL(string: "\(normalizedBaseURL(baseURL))/api/pull") else {
            throw LocalAISettingsError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 900
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequest(model: model, stream: false))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalAISettingsError.badResponse(message ?? "Ollama pull failed.")
        }
        _ = try JSONDecoder().decode(PullResponse.self, from: data)
    }

    private nonisolated static func normalizedBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/api") {
            trimmed.removeLast(4)
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.isEmpty ? LauncherPreferences.defaultLocalAIBaseURL : trimmed
    }

    private nonisolated static func canonical(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(":latest") ? String(trimmed.dropLast(7)) : trimmed
    }

    private nonisolated static func curatedChatModels(ollamaVersion: String) -> [LocalAIModelChoice] {
        var choices: [LocalAIModelChoice]
        if supportsQwen35(ollamaVersion) {
            choices = [
                LocalAIModelChoice(id: "qwen3.5:4b", title: "Qwen 3.5 4B", subtitle: "Recommended", minimumFreeBytes: 5 * gib),
                LocalAIModelChoice(id: "qwen3.5:9b", title: "Qwen 3.5 9B", subtitle: "Quality", minimumFreeBytes: 10 * gib),
                LocalAIModelChoice(id: "llama3.2:3b", title: "Llama 3.2 3B", subtitle: "Fast", minimumFreeBytes: 3 * gib)
            ]
        } else {
            choices = [
                LocalAIModelChoice(id: "qwen3:4b", title: "Qwen 3 4B", subtitle: "Recommended", minimumFreeBytes: 4 * gib),
                LocalAIModelChoice(id: "qwen3:8b", title: "Qwen 3 8B", subtitle: "Quality", minimumFreeBytes: 8 * gib),
                LocalAIModelChoice(id: "llama3.2:3b", title: "Llama 3.2 3B", subtitle: "Fast", minimumFreeBytes: 3 * gib)
            ]
        }

        if supportsQwen35(ollamaVersion),
           ProcessInfo.processInfo.physicalMemory >= 32 * 1_024 * 1_024 * 1_024 {
            choices.append(LocalAIModelChoice(
                id: "qwen3.5:35b-a3b-coding-nvfp4",
                title: "Qwen 3.5 35B MLX",
                subtitle: "Large",
                minimumFreeBytes: 40 * gib
            ))
        }
        return choices
    }

    private nonisolated static var gib: Int64 {
        1_024 * 1_024 * 1_024
    }

    private nonisolated static func minimumFreeBytes(for model: String) -> Int64 {
        switch canonical(model) {
        case "qwen3:4b":
            return 4 * gib
        case "qwen3:8b":
            return 8 * gib
        case "qwen3.5:4b":
            return 5 * gib
        case "qwen3.5:9b":
            return 10 * gib
        case "qwen3.5:35b-a3b-coding-nvfp4":
            return 40 * gib
        case "llama3.2:3b":
            return 3 * gib
        case LocalAIClient.recommendedEmbeddingModel:
            return 2 * gib
        default:
            return 0
        }
    }

    private nonisolated static func hasEnoughSpace(for model: String, availableCapacityBytes: Int64) -> Bool {
        let required = minimumFreeBytes(for: model)
        return required == 0 || availableCapacityBytes == 0 || availableCapacityBytes >= required
    }

    private nonisolated static func supportsQwen35(_ version: String) -> Bool {
        compareVersion(version, atLeast: "0.19.0")
    }

    private nonisolated static func compareVersion(_ version: String, atLeast minimum: String) -> Bool {
        let lhs = version.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = minimum.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return true
    }

    private nonisolated static func installErrorMessage(_ error: Error, model: String) -> String {
        if case LocalAISettingsError.badResponse(let message) = error {
            if message.localizedCaseInsensitiveContains("newer version of Ollama") {
                return "Update Ollama to install \(model)."
            }
            if message.localizedCaseInsensitiveContains("no space left") {
                return notEnoughDiskMessage(for: model)
            }
        }
        return "Could not install \(model)."
    }

    private nonisolated static func migrateUnsupportedChatSelection(
        version: String,
        models: [String]
    ) {
        let current = canonical(LauncherPreferences.localAIModel)
        guard !current.isEmpty else { return }

        let installedIDs = Set(models.map(canonical))
        if !supportsQwen35(version), current.hasPrefix("qwen3.5:") {
            LauncherPreferences.localAIModel = fallbackChatModel(in: installedIDs)
            return
        }
    }

    private nonisolated static func fallbackChatModel(in installedIDs: Set<String>) -> String {
        for model in ["qwen3:4b", "llama3.2:3b"] where installedIDs.contains(model) {
            return model
        }
        return ""
    }

    private nonisolated static func notEnoughDiskMessage(for model: String) -> String {
        let gb = Int(ceil(Double(minimumFreeBytes(for: model)) / Double(gib)))
        return gb > 0 ? "Free \(gb) GB to install \(model)." : "Free disk space to install \(model)."
    }

    private nonisolated static func notEnoughDiskSubtitle(for model: String) -> String {
        let gb = Int(ceil(Double(minimumFreeBytes(for: model)) / Double(gib)))
        return gb > 0 ? "Needs \(gb) GB free" : "Needs free space"
    }

    private nonisolated static func availableCapacityBytes() -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else {
            return 0
        }
        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return 0
    }
}

struct LocalAIModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let minimumFreeBytes: Int64

    init(id: String, title: String, subtitle: String, minimumFreeBytes: Int64 = 0) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.minimumFreeBytes = minimumFreeBytes
    }

    var menuTitle: String {
        "\(title) - \(subtitle)"
    }

    func withSubtitle(_ subtitle: String) -> LocalAIModelChoice {
        LocalAIModelChoice(id: id, title: title, subtitle: subtitle, minimumFreeBytes: minimumFreeBytes)
    }
}

private struct Snapshot: Sendable {
    let version: String
    let models: [String]
    let availableCapacityBytes: Int64
}

private struct VersionResponse: Decodable {
    let version: String?
}

private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
    }
}

private struct PullRequest: Encodable {
    let model: String
    let stream: Bool
}

private struct PullResponse: Decodable {
    let status: String?
}

private enum LocalAISettingsError: Error {
    case invalidURL
    case badResponse(String)
}
