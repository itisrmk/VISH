import Foundation

struct SystemActionsSource: SearchSource {
    private let actions: [SystemActionRecord] = [
        .init(kind: .toggleDarkMode, title: "Toggle Dark Mode", subtitle: "Switch macOS appearance", keywords: "dark mode light appearance theme"),
        .init(kind: .lockScreen, title: "Lock Screen", subtitle: "Secure this Mac", keywords: "lock screen secure"),
        .init(kind: .sleep, title: "Sleep", subtitle: "Put this Mac to sleep", keywords: "sleep suspend"),
        .init(kind: .showHiddenFiles, title: "Show Hidden Files", subtitle: "Reveal dotfiles in Finder", keywords: "show hidden files dotfiles finder"),
        .init(kind: .hideHiddenFiles, title: "Hide Hidden Files", subtitle: "Hide dotfiles in Finder", keywords: "hide hidden files dotfiles finder"),
        .init(kind: .emptyTrash, title: "Empty Trash", subtitle: "Permanently remove Trash contents", keywords: "empty trash bin delete"),
        .init(kind: .ejectDisks, title: "Eject External Disks", subtitle: "Eject mounted removable volumes", keywords: "eject disks volumes external"),
        .init(kind: .logOut, title: "Log Out", subtitle: "Ask macOS to log out", keywords: "logout log out sign out"),
        .init(kind: .restart, title: "Restart", subtitle: "Ask macOS to restart", keywords: "restart reboot"),
        .init(kind: .shutDown, title: "Shut Down", subtitle: "Ask macOS to shut down", keywords: "shutdown shut down power off")
    ]

    func search(_ query: String) -> [SearchResult] {
        actions.compactMap { action in
            let haystack = action.searchText
            guard let score = FuzzyMatcher.score(query: query, candidate: haystack) else { return nil }
            return SearchResult(
                id: "system:\(action.kind.rawValue)",
                kind: .system,
                title: action.title,
                subtitle: action.subtitle,
                score: score,
                action: .system(action.kind)
            )
        }
    }
}

private struct SystemActionRecord: Sendable {
    let kind: SystemAction
    let title: String
    let subtitle: String
    let searchText: String

    init(kind: SystemAction, title: String, subtitle: String, keywords: String) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        searchText = "\(title) \(keywords)".lowercased()
    }
}
