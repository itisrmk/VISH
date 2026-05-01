import AppKit

@MainActor
final class FileScopeSettingsModel: ObservableObject {
    @Published private(set) var options = FileSearchFolderOption.defaultOptions
    @Published private(set) var excludedIDs = Set(LauncherPreferences.fileSearchExcludedFolderIDs)
    @Published private(set) var customExcludedPaths = LauncherPreferences.fileSearchCustomExcludedPaths

    var excludedCount: Int {
        excludedIDs.count + customExcludedPaths.count
    }

    func refresh() {
        options = FileSearchFolderOption.defaultOptions
        excludedIDs = Set(LauncherPreferences.fileSearchExcludedFolderIDs)
        customExcludedPaths = LauncherPreferences.fileSearchCustomExcludedPaths
    }

    func isIncluded(_ option: FileSearchFolderOption) -> Bool {
        !excludedIDs.contains(option.id)
    }

    func setIncluded(_ included: Bool, option: FileSearchFolderOption) {
        var ids = excludedIDs
        if included {
            ids.remove(option.id)
        } else {
            ids.insert(option.id)
        }
        persist(excludedIDs: ids, customPaths: customExcludedPaths)
    }

    func addCustomExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Exclude"
        panel.message = "Choose a folder VISH should ignore for file search and semantic indexing."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var paths = customExcludedPaths
        paths.append(url.standardizedFileURL.path)
        persist(excludedIDs: excludedIDs, customPaths: paths)
    }

    func removeCustomExclusion(_ path: String) {
        persist(excludedIDs: excludedIDs, customPaths: customExcludedPaths.filter { $0 != path })
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func persist(excludedIDs: Set<String>, customPaths: [String]) {
        LauncherPreferences.fileSearchExcludedFolderIDs = Array(excludedIDs)
        LauncherPreferences.fileSearchCustomExcludedPaths = customPaths
        LauncherPreferences.fullDiskWarmupCompleted = false
        refresh()
        Task.detached(priority: .utility) {
            await FileIndexStore.shared.applyCurrentExclusions()
        }
    }
}
