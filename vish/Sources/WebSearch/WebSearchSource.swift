import Foundation

struct WebSearchSource: SearchSource {
    func search(_ query: String) -> [SearchResult] {
        let provider = LauncherPreferences.webSearchProvider
        guard let url = provider.url(for: query) else { return [] }

        return [SearchResult(
            id: "web:\(query)",
            kind: .web,
            title: "Search \(provider.displayName) for \"\(query)\"",
            subtitle: "Web search",
            score: 0.1,
            action: .openURL(url)
        )]
    }
}

enum WebSearchProvider: String, CaseIterable, Identifiable, Sendable {
    case google
    case duckDuckGo
    case kagi
    case bing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google:
            return "Google"
        case .duckDuckGo:
            return "DuckDuckGo"
        case .kagi:
            return "Kagi"
        case .bing:
            return "Bing"
        }
    }

    func url(for query: String) -> URL? {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private var baseURL: String {
        switch self {
        case .google:
            return "https://www.google.com/search"
        case .duckDuckGo:
            return "https://duckduckgo.com/"
        case .kagi:
            return "https://kagi.com/search"
        case .bing:
            return "https://www.bing.com/search"
        }
    }
}
