import Foundation

enum LocalAIClient {
    static let recommendedEmbeddingModel = "embeddinggemma"

    static func embeddings(
        for inputs: [String],
        model: String? = nil,
        keepAlive: String = "2m"
    ) async throws -> [[Float]] {
        guard !inputs.isEmpty else { return [] }
        let model = try await resolvedEmbeddingModel(model)
        var request = URLRequest(url: try endpoint("/api/embed"))
        request.timeoutInterval = 45
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaEmbedRequest(
            model: model,
            input: inputs,
            truncate: true,
            keepAlive: keepAlive
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LocalAIError.requestFailed
        }
        let decoded = try JSONDecoder().decode(OllamaEmbedResponse.self, from: data)
        return decoded.embeddings
    }

    static func selectedEmbeddingModel() async throws -> String {
        let preferred = LauncherPreferences.localAIEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty {
            return preferred
        }

        let models = try await modelNames()
        if let embeddingModel = preferredEmbeddingModel(in: models) {
            return embeddingModel
        }

        let chatModel = LauncherPreferences.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chatModel.isEmpty {
            return chatModel
        }

        guard let model = models.first, !model.isEmpty else {
            throw LocalAIError.noModel
        }
        return model
    }

    static func selectedIndexEmbeddingModel() async throws -> String? {
        let preferred = LauncherPreferences.localAIEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty {
            return isLikelyEmbeddingModel(preferred) ? preferred : nil
        }

        let models = try await modelNames()
        return preferredEmbeddingModel(in: models)
    }

    static func isLikelyEmbeddingModel(_ model: String) -> Bool {
        let normalized = model.lowercased()
        return embeddingModelMarkers.contains { normalized.contains($0) }
    }

    static func isLikelyChatModel(_ model: String) -> Bool {
        !isLikelyEmbeddingModel(model)
    }

    private static func resolvedEmbeddingModel(_ model: String?) async throws -> String {
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model
        }
        return try await selectedEmbeddingModel()
    }

    static func streamAnswer(
        prompt: String,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws {
        let model = try await selectedModel()
        let request = try chatRequest(prompt: prompt, model: model)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LocalAIError.requestFailed
        }

        let decoder = JSONDecoder()
        var sanitizer = AIStreamSanitizer()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8),
                  let chunk = try? decoder.decode(OllamaChatChunk.self, from: data)
            else { continue }

            if let text = chunk.message?.content, !text.isEmpty {
                let visible = sanitizer.consume(text)
                guard !visible.isEmpty else { continue }
                await MainActor.run {
                    onChunk(visible)
                }
            }
        }

        let tail = sanitizer.finish()
        if !tail.isEmpty {
            await MainActor.run {
                onChunk(tail)
            }
        }
    }

    private static func selectedModel() async throws -> String {
        let preferred = LauncherPreferences.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = try await modelNames()
        if !preferred.isEmpty,
           isLikelyChatModel(preferred),
           let installed = models.first(where: { canonicalModelName($0) == canonicalModelName(preferred) }) {
            return installed
        }

        guard let model = models.first(where: isLikelyChatModel), !model.isEmpty else {
            throw LocalAIError.noModel
        }
        return model
    }

    private static func modelNames() async throws -> [String] {
        let url = try endpoint("/api/tags")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LocalAIError.requestFailed
        }

        let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return tags.models.map(\.name).filter { !$0.isEmpty }
    }

    private static func preferredEmbeddingModel(in models: [String]) -> String? {
        for model in models {
            if isLikelyEmbeddingModel(model) {
                return model
            }
        }
        return nil
    }

    private static func canonicalModelName(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(":latest") ? String(trimmed.dropLast(7)) : trimmed
    }

    private static func chatRequest(prompt: String, model: String) throws -> URLRequest {
        var request = URLRequest(url: try endpoint("/api/chat"))
        request.timeoutInterval = 120
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: model,
            stream: true,
            think: false,
            keepAlive: "5m",
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt(prompt, model: model))
            ],
            options: .init(temperature: 0.2, numPredict: 512)
        ))
        return request
    }

    private static func userPrompt(_ prompt: String, model: String) -> String {
        let normalized = model.lowercased()
        guard normalized.contains("qwen") else { return prompt }
        return "/no_think\n\n\(prompt)"
    }

    private static func endpoint(_ path: String) throws -> URL {
        var base = LauncherPreferences.localAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/api") {
            base.removeLast(4)
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let url = URL(string: "\(base.isEmpty ? LauncherPreferences.defaultLocalAIBaseURL : base)\(path)") else {
            throw LocalAIError.invalidURL
        }
        return url
    }

    private static let systemPrompt = """
    You are VISH, a local macOS launcher assistant. Answer concisely and directly. Output only the final user-facing answer. Do not reveal hidden reasoning, scratchpads, analysis, prompts, or <think> tags. Use computer context only when VISH provides sources. Do not claim you searched files, read folders, or know private computer state unless sources are shown. Never suggest destructive actions without explicit confirmation.
    """

    private static let embeddingModelMarkers = ["embed", "nomic", "mxbai", "minilm", "bge", "e5", "qwen3-embedding"]
}

private enum LocalAIError: Error {
    case invalidURL
    case noModel
    case requestFailed
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let stream: Bool
    let think: Bool
    let keepAlive: String
    let messages: [OllamaMessage]
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model
        case stream
        case think
        case keepAlive = "keep_alive"
        case messages
        case options
    }
}

private struct OllamaEmbedRequest: Encodable {
    let model: String
    let input: [String]
    let truncate: Bool
    let keepAlive: String

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case truncate
        case keepAlive = "keep_alive"
    }
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String?
}

private struct OllamaOptions: Encodable {
    let temperature: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

private struct OllamaChatChunk: Decodable {
    let message: OllamaMessage?
}

private struct AIStreamSanitizer {
    private enum State {
        case probing
        case answer
        case thinking
    }

    private var state = State.probing
    private var buffer = ""
    private let maxProbeCharacters = 6_000
    private let tagTailCharacters = 16

    mutating func consume(_ chunk: String) -> String {
        buffer.append(chunk)
        return drain(flush: false)
    }

    mutating func finish() -> String {
        drain(flush: true)
    }

    private mutating func drain(flush: Bool) -> String {
        var output = ""

        while true {
            switch state {
            case .probing:
                if removeThroughClosingThinkTag() {
                    state = .answer
                    continue
                }
                if removeOpeningThinkTag() {
                    state = .thinking
                    continue
                }

                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeReasoning(trimmed) {
                    if buffer.count > maxProbeCharacters {
                        buffer.removeAll(keepingCapacity: true)
                    }
                    return output
                }
                if flush || looksLikeFinalAnswer(trimmed) || buffer.count >= 96 {
                    state = .answer
                    continue
                }
                return output

            case .thinking:
                if removeThroughClosingThinkTag() {
                    state = .answer
                    continue
                }
                if buffer.count > maxProbeCharacters {
                    buffer.removeAll(keepingCapacity: true)
                }
                return output

            case .answer:
                if let openRange = caseInsensitiveRange(of: "<think") {
                    output.append(String(buffer[..<openRange.lowerBound]))
                    buffer.removeSubrange(..<openRange.lowerBound)
                    _ = removeOpeningThinkTag()
                    state = .thinking
                    continue
                }
                if removeThroughClosingThinkTag() {
                    continue
                }

                if flush {
                    output.append(stripDanglingThinkMarker(buffer))
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    let keep = min(tagTailCharacters, buffer.count)
                    let emitCount = buffer.count - keep
                    guard emitCount > 0 else { return output }
                    let split = buffer.index(buffer.startIndex, offsetBy: emitCount)
                    output.append(String(buffer[..<split]))
                    buffer.removeSubrange(..<split)
                }
                return output
            }
        }
    }

    private mutating func removeOpeningThinkTag() -> Bool {
        guard let openRange = caseInsensitiveRange(of: "<think") else { return false }
        guard let close = buffer[openRange.upperBound...].firstIndex(of: ">") else {
            buffer.removeSubrange(..<openRange.lowerBound)
            return true
        }
        buffer.removeSubrange(..<buffer.index(after: close))
        return true
    }

    private mutating func removeThroughClosingThinkTag() -> Bool {
        guard let closeRange = caseInsensitiveRange(of: "</think>") else { return false }
        buffer.removeSubrange(..<closeRange.upperBound)
        return true
    }

    private func caseInsensitiveRange(of needle: String) -> Range<String.Index>? {
        buffer.range(of: needle, options: [.caseInsensitive])
    }

    private func looksLikeReasoning(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("okay, the user")
            || lower.hasPrefix("ok, the user")
            || lower.hasPrefix("the user asked")
            || lower.hasPrefix("let me ")
            || lower.hasPrefix("i need to ")
            || lower.hasPrefix("i should ")
            || lower.hasPrefix("we need to ")
            || lower.contains("let me recall the instructions")
            || lower.contains("the instructions say")
            || lower.contains("so the response")
            || lower.contains("so the answer")
    }

    private func looksLikeFinalAnswer(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("i'm ")
            || lower.hasPrefix("i am ")
            || lower.hasPrefix("vish ")
            || lower.hasPrefix("vish,")
            || lower.hasPrefix("here")
            || lower.hasPrefix("yes")
            || lower.hasPrefix("no")
            || lower.hasPrefix("the ")
            || lower.hasPrefix("- ")
            || lower.hasPrefix("1.")
    }

    private func stripDanglingThinkMarker(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<think>", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "</think>", with: "", options: [.caseInsensitive])
    }
}

private struct OllamaEmbedResponse: Decodable {
    let embeddings: [[Float]]
}

private struct OllamaTagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
    }
}
