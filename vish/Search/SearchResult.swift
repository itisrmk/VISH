import Foundation

struct SearchResult: Identifiable, Sendable {
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String
    let score: Double
    let icon: ResultIcon?
    let action: ResultAction

    init(
        id: String,
        kind: SearchResultKind,
        title: String,
        subtitle: String,
        score: Double,
        icon: ResultIcon? = nil,
        action: ResultAction
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.score = score
        self.icon = icon
        self.action = action
    }
}

enum SearchResultKind: String, Codable, Sendable {
    case ai = "AI"
    case app = "App"
    case calculator = "Calc"
    case clipboard = "Clip"
    case file = "File"
    case quicklink = "Quick"
    case snippet = "Snippet"
    case system = "Action"
    case url = "URL"
    case web = "Web"
}

enum ResultAction: Sendable {
    case askAI(String)
    case copy(String)
    case openFile(URL)
    case openApplication(URL)
    case openURL(URL)
    case pasteClipboard(String)
    case pasteSnippet(String)
    case revealFile(URL)
    case system(SystemAction)
}

enum ResultIcon: Equatable, Sendable {
    case imageData(Data)
    case quicklink(QuicklinkIconKind)
    case symbol(String)
}

enum QuicklinkIconKind: String, Codable, CaseIterable, Sendable {
    case github
    case maps
    case youtube

    static func defaultIcon(keyword: String, urlTemplate: String) -> QuicklinkIconKind? {
        let normalized = keyword.lowercased()
        let lowerTemplate = urlTemplate.lowercased()
        if normalized == "yt" || normalized == "youtube" || lowerTemplate.contains("youtube.com") || lowerTemplate.contains("youtu.be") {
            return .youtube
        }
        if normalized == "gh" || normalized == "github" || lowerTemplate.contains("github.com") {
            return .github
        }
        if normalized == "maps" || lowerTemplate.contains("google.com/maps") || lowerTemplate.contains("maps.apple.com") {
            return .maps
        }
        return nil
    }
}

enum SystemAction: String, Sendable {
    case emptyTrash
    case ejectDisks
    case hideHiddenFiles
    case lockScreen
    case logOut
    case restart
    case showHiddenFiles
    case shutDown
    case sleep
    case toggleDarkMode
}
