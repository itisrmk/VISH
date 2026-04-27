import Foundation

enum AIContextAction: String, Sendable {
    case ask
    case summarize
    case explain

    var menuTitle: String {
        switch self {
        case .ask:
            return "Ask AI"
        case .summarize:
            return "Summarize"
        case .explain:
            return "Explain"
        }
    }

    var title: String {
        switch self {
        case .ask:
            return "Ask AI"
        case .summarize:
            return "Summarize"
        case .explain:
            return "Explain"
        }
    }

    var instruction: String {
        switch self {
        case .ask:
            return "Give a concise, useful overview of the selected item and suggest the safest next actions."
        case .summarize:
            return "Summarize the selected item in short bullets. If only metadata is available, say that."
        case .explain:
            return "Explain what the selected item is, why it may matter, and how the user can use it."
        }
    }
}

enum AIContextBuilder {
    static func actions(for result: SearchResult) -> [AIContextAction] {
        switch result.kind {
        case .app, .clipboard, .file, .quicklink, .snippet, .url, .web:
            return [.ask, .summarize, .explain]
        case .ai, .calculator, .system:
            return []
        }
    }

    static func prompt(for result: SearchResult, action: AIContextAction) async -> String {
        let context = await context(for: result)
        return """
        \(action.instruction)

        Rules:
        - Use only the selected-result context below.
        - Do not claim you opened the app, fetched the URL, or searched the computer.
        - If content is unavailable, answer from metadata only and say so.
        - Keep the answer compact.
        - End with: Sources: \(context.sourceLabel)

        Selected result:
        Kind: \(result.kind.rawValue)
        Title: \(result.title)
        Subtitle: \(result.subtitle)

        Context:
        \(context.body)
        """
    }

    static func prompt(for result: SearchResult, question: String) async -> String {
        let context = await context(for: result)
        return """
        Answer the user's question using only the selected-result context below.

        User question:
        \(question)

        Rules:
        - Use only the selected-result context below.
        - Do not claim you opened the app, fetched the URL, or searched the computer.
        - If content is unavailable, answer from metadata only and say so.
        - Keep the answer compact.
        - End with: Sources: \(context.sourceLabel)

        Selected result:
        Kind: \(result.kind.rawValue)
        Title: \(result.title)
        Subtitle: \(result.subtitle)

        Context:
        \(context.body)
        """
    }

    private static func context(for result: SearchResult) async -> AIContext {
        switch result.action {
        case .openApplication(let url):
            return appContext(url: url, result: result)
        case .openFile(let url), .revealFile(let url):
            return fileContext(url: url, result: result)
        case .openURL(let url):
            return urlContext(url: url, result: result)
        case .pasteClipboard(let text):
            return textContext(text, source: "Clipboard item", result: result)
        case .pasteSnippet(let id):
            if let snippet = await SnippetStore.shared.record(id: id) {
                return textContext(
                    "Trigger: \(snippet.trigger)\nExpansion:\n\(snippet.expansion)",
                    source: "Snippet \(snippet.trigger)",
                    result: result
                )
            }
            return metadataContext(result, source: "Snippet")
        case .copy(let value):
            return textContext(value, source: result.kind.rawValue, result: result)
        case .askAI, .system:
            return metadataContext(result, source: result.kind.rawValue)
        }
    }

    private static func appContext(url: URL, result: SearchResult) -> AIContext {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let lines = [
            "Application name: \(result.title)",
            "Bundle ID: \(bundle?.bundleIdentifier ?? "Unknown")",
            "Path: \(url.path)",
            "Version: \(info["CFBundleShortVersionString"] as? String ?? "Unknown")",
            "Executable: \(info["CFBundleExecutable"] as? String ?? "Unknown")"
        ]
        return AIContext(sourceLabel: url.path, body: lines.joined(separator: "\n"))
    }

    private static func fileContext(url: URL, result: SearchResult) -> AIContext {
        var lines = [
            "File name: \(url.lastPathComponent)",
            "Path: \(url.path)"
        ]

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isDirectoryKey]) {
            if let size = values.fileSize {
                lines.append("Size: \(size) bytes")
            }
            if let contentType = values.contentType?.identifier {
                lines.append("Type: \(contentType)")
            }
            if values.isDirectory == true {
                lines.append("Preview: Directory contents are not read for AI context.")
                return AIContext(sourceLabel: url.path, body: lines.joined(separator: "\n"))
            }
        }

        switch FilePreviewReader.preview(for: url, byteLimit: previewByteLimit, maxCharacters: maxTextCharacters) {
        case .available(let text):
            lines.append("Text preview, capped at \(previewByteLimit) bytes:")
            lines.append(text)
        case .unavailable(let reason):
            lines.append("Preview unavailable: \(reason)")
        }
        return AIContext(sourceLabel: url.path, body: lines.joined(separator: "\n"))
    }

    private static func urlContext(url: URL, result: SearchResult) -> AIContext {
        let lines = [
            "URL: \(url.absoluteString)",
            "Host: \(url.host ?? "Unknown")",
            "Title: \(result.title)",
            "Note: Web page content was not fetched."
        ]
        return AIContext(sourceLabel: url.absoluteString, body: lines.joined(separator: "\n"))
    }

    private static func textContext(_ value: String, source: String, result: SearchResult) -> AIContext {
        let text = clipped(value.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: maxTextCharacters)
        let body = [
            "Source: \(source)",
            "Title: \(result.title)",
            "Text:",
            text.isEmpty ? "(No text available.)" : text
        ].joined(separator: "\n")
        return AIContext(sourceLabel: source, body: body)
    }

    private static func metadataContext(_ result: SearchResult, source: String) -> AIContext {
        AIContext(sourceLabel: source, body: "Title: \(result.title)\nSubtitle: \(result.subtitle)")
    }

    private static func clipped(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return "\(value.prefix(maxCharacters))\n...[truncated]"
    }

    private static let previewByteLimit = 16_384
    private static let maxTextCharacters = 12_000
}

private struct AIContext: Sendable {
    let sourceLabel: String
    let body: String
}
