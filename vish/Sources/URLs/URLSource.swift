import Foundation

struct URLSource: SearchSource {
    func search(_ query: String) -> [SearchResult] {
        guard let url = URLDetector.url(from: query) else { return [] }
        return [SearchResult(
            id: "url:\(url.absoluteString)",
            kind: .url,
            title: "Open \(url.absoluteString)",
            subtitle: "Default browser",
            score: 0.75,
            action: .openURL(url)
        )]
    }
}

enum URLDetector {
    static func url(from query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        if let scheme = URLComponents(string: trimmed)?.scheme, !scheme.isEmpty {
            return URL(string: trimmed)
        }

        guard looksLikeHost(trimmed) else { return nil }
        return URL(string: "https://\(trimmed)")
    }

    private static func looksLikeHost(_ value: String) -> Bool {
        if value.hasPrefix("localhost:") { return true }
        if value.split(separator: ".").count == 4, value.allSatisfy({ $0.isNumber || $0 == "." }) { return true }
        return value.contains(".") && !value.hasPrefix(".") && !value.hasSuffix(".")
    }
}
