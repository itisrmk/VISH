import CoreGraphics
import Foundation

enum LauncherPreferences {
    static let roundedCornersKey = "launcher.roundedCorners"
    static let appearanceKey = "launcher.appearance"
    static let textSizeKey = "launcher.textSize"
    static let launcherScaleKey = "launcher.scale"
    static let launcherCustomPositionKey = "launcher.customPosition"
    static let launcherPositionXKey = "launcher.positionX"
    static let launcherPositionTopKey = "launcher.positionTop"
    static let fullDiskIndexingEnabledKey = "indexing.fullDiskEnabled"
    static let fullDiskWarmupCompletedKey = "indexing.fullDiskFileCatalogCompleted"
    static let fileIndexLastEventIDKey = "indexing.fileCatalogLastFSEventID"
    static let fileSearchExcludedFolderIDsKey = "indexing.excludedFolderIDs"
    static let fileSearchCustomExcludedPathsKey = "indexing.customExcludedPaths"
    static let webSearchProviderKey = "search.webProvider"
    static let clipboardHistoryEnabledKey = "clipboard.historyEnabled"
    static let clipboardRetentionDaysKey = "clipboard.retentionDays"
    static let clipboardDisabledAppIDsKey = "clipboard.disabledAppIDs"
    static let localAIEnabledKey = "ai.localEnabled"
    static let localAIBaseURLKey = "ai.ollamaBaseURL"
    static let localAIModelKey = "ai.model"
    static let localAIEmbeddingModelKey = "ai.embeddingModel"
    static let onboardingCompletedKey = "onboarding.completed"
    static let defaultLauncherScale = 1.0
    static let defaultLocalAIBaseURL = "http://localhost:11434"
    static let launcherScaleRange = 0.86...1.18

    static var roundedCorners: Bool {
        get {
            UserDefaults.standard.object(forKey: roundedCornersKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: roundedCornersKey)
        }
    }

    static var appearance: LauncherAppearance {
        get {
            LauncherAppearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey)
        }
    }

    static var textSize: LauncherTextSize {
        get {
            LauncherTextSize(rawValue: UserDefaults.standard.string(forKey: textSizeKey) ?? "") ?? .regular
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: textSizeKey)
        }
    }

    static var launcherScale: Double {
        get {
            normalizedLauncherScale(UserDefaults.standard.object(forKey: launcherScaleKey) as? Double ?? defaultLauncherScale)
        }
        set {
            UserDefaults.standard.set(normalizedLauncherScale(newValue), forKey: launcherScaleKey)
        }
    }

    static var launcherTopLeft: CGPoint? {
        get {
            guard UserDefaults.standard.object(forKey: launcherCustomPositionKey) as? Bool == true else { return nil }
            return CGPoint(
                x: UserDefaults.standard.double(forKey: launcherPositionXKey),
                y: UserDefaults.standard.double(forKey: launcherPositionTopKey)
            )
        }
        set {
            guard let value = newValue else {
                UserDefaults.standard.removeObject(forKey: launcherCustomPositionKey)
                UserDefaults.standard.removeObject(forKey: launcherPositionXKey)
                UserDefaults.standard.removeObject(forKey: launcherPositionTopKey)
                return
            }

            UserDefaults.standard.set(true, forKey: launcherCustomPositionKey)
            UserDefaults.standard.set(Double(value.x), forKey: launcherPositionXKey)
            UserDefaults.standard.set(Double(value.y), forKey: launcherPositionTopKey)
        }
    }

    static func normalizedLauncherScale(_ value: Double) -> Double {
        min(max(value, launcherScaleRange.lowerBound), launcherScaleRange.upperBound)
    }

    static func clearLauncherPosition() {
        launcherTopLeft = nil
    }

    static var fullDiskIndexingEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: fullDiskIndexingEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: fullDiskIndexingEnabledKey)
        }
    }

    static var fullDiskWarmupCompleted: Bool {
        get {
            UserDefaults.standard.object(forKey: fullDiskWarmupCompletedKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: fullDiskWarmupCompletedKey)
        }
    }

    static var fileIndexLastEventID: UInt64 {
        get {
            UInt64(UserDefaults.standard.object(forKey: fileIndexLastEventIDKey) as? Int64 ?? 0)
        }
        set {
            UserDefaults.standard.set(Int64(newValue), forKey: fileIndexLastEventIDKey)
        }
    }

    static var fileSearchExcludedFolderIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: fileSearchExcludedFolderIDsKey) ?? []
        }
        set {
            UserDefaults.standard.set(normalizedStrings(newValue), forKey: fileSearchExcludedFolderIDsKey)
        }
    }

    static var fileSearchCustomExcludedPaths: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: fileSearchCustomExcludedPathsKey) ?? []
        }
        set {
            UserDefaults.standard.set(normalizedPaths(newValue), forKey: fileSearchCustomExcludedPathsKey)
        }
    }

    static var fileSearchExcludedPaths: [String] {
        let defaultPaths = FileSearchFolderOption.defaultOptions
            .filter { fileSearchExcludedFolderIDs.contains($0.id) }
            .map(\.path)
        return normalizedPaths(defaultPaths + fileSearchCustomExcludedPaths)
    }

    static func isFileSearchPathExcluded(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return fileSearchExcludedPaths.contains { excluded in
            normalized == excluded || normalized.hasPrefix("\(excluded)/")
        }
    }

    static var webSearchProvider: WebSearchProvider {
        get {
            WebSearchProvider(rawValue: UserDefaults.standard.string(forKey: webSearchProviderKey) ?? "") ?? .google
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: webSearchProviderKey)
        }
    }

    private static func normalizedStrings(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted()
    }

    private static func normalizedPaths(_ values: [String]) -> [String] {
        Array(Set(values.map(normalizedPath).filter { !$0.isEmpty }))
            .sorted()
    }

    private static func normalizedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    static var clipboardHistoryEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: clipboardHistoryEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: clipboardHistoryEnabledKey)
        }
    }

    static var clipboardRetentionDays: Int {
        get {
            let value = UserDefaults.standard.object(forKey: clipboardRetentionDaysKey) as? Int
                ?? ClipboardRetentionOption.default.rawValue
            return ClipboardRetentionOption(rawValue: value)?.rawValue ?? ClipboardRetentionOption.default.rawValue
        }
        set {
            let normalized = ClipboardRetentionOption(rawValue: newValue)?.rawValue ?? ClipboardRetentionOption.default.rawValue
            UserDefaults.standard.set(normalized, forKey: clipboardRetentionDaysKey)
        }
    }

    static var clipboardDisabledAppIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: clipboardDisabledAppIDsKey) ?? []
        }
        set {
            let values = Array(Set(newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
                .sorted()
            UserDefaults.standard.set(values, forKey: clipboardDisabledAppIDsKey)
        }
    }

    static var localAIEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: localAIEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: localAIEnabledKey)
        }
    }

    static var localAIBaseURL: String {
        get {
            UserDefaults.standard.string(forKey: localAIBaseURLKey) ?? defaultLocalAIBaseURL
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? defaultLocalAIBaseURL : trimmed, forKey: localAIBaseURLKey)
        }
    }

    static var localAIModel: String {
        get {
            UserDefaults.standard.string(forKey: localAIModelKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: localAIModelKey)
        }
    }

    static var localAIEmbeddingModel: String {
        get {
            UserDefaults.standard.string(forKey: localAIEmbeddingModelKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: localAIEmbeddingModelKey)
        }
    }

    static var onboardingCompleted: Bool {
        get {
            UserDefaults.standard.object(forKey: onboardingCompletedKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: onboardingCompletedKey)
        }
    }
}

struct FileSearchFolderOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let path: String

    static var defaultOptions: [FileSearchFolderOption] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            option("desktop", "Desktop", "desktopcomputer", home.appendingPathComponent("Desktop", isDirectory: true)),
            option("documents", "Documents", "doc.text", home.appendingPathComponent("Documents", isDirectory: true)),
            option("downloads", "Downloads", "arrow.down.circle", home.appendingPathComponent("Downloads", isDirectory: true)),
            option("pictures", "Pictures", "photo", home.appendingPathComponent("Pictures", isDirectory: true)),
            option("movies", "Movies", "film", home.appendingPathComponent("Movies", isDirectory: true)),
            option("music", "Music", "music.note", home.appendingPathComponent("Music", isDirectory: true)),
            option("home-applications", "User Apps", "app", home.appendingPathComponent("Applications", isDirectory: true)),
            option("shared", "Shared", "person.2", URL(fileURLWithPath: "/Users/Shared", isDirectory: true)),
            option("volumes", "External Volumes", "externaldrive", URL(fileURLWithPath: "/Volumes", isDirectory: true))
        ]
    }

    private static func option(_ id: String, _ title: String, _ symbol: String, _ url: URL) -> FileSearchFolderOption {
        FileSearchFolderOption(id: id, title: title, symbol: symbol, path: url.standardizedFileURL.path)
    }
}

enum ClipboardRetentionOption: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30
    case threeMonths = 90
    case forever = 0

    static let `default` = ClipboardRetentionOption.oneMonth

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneDay: "1 day"
        case .oneWeek: "7 days"
        case .oneMonth: "30 days"
        case .threeMonths: "90 days"
        case .forever: "Forever"
        }
    }
}

enum LauncherAppearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }
}

enum LauncherTextSize: String, CaseIterable, Identifiable {
    case regular
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular:
            return "Regular"
        case .large:
            return "Large"
        }
    }
}
