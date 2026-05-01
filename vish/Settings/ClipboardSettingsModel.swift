import AppKit

@MainActor
final class ClipboardSettingsModel: ObservableObject {
    @Published private(set) var items: [ClipboardHistorySummary] = []
    @Published private(set) var stats = ClipboardHistoryStats.empty
    @Published private(set) var ignoredApps: [ClipboardIgnoredApp] = []
    @Published var selectedID: String?
    @Published var editText = ""

    var selectedItem: ClipboardHistorySummary? {
        items.first { $0.id == selectedID }
    }

    var canEdit: Bool {
        selectedID != nil && !editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refresh() {
        refreshIgnoredApps()
        Task {
            let summaries = await ClipboardHistoryStore.shared.summaries()
            let currentStats = await ClipboardHistoryStore.shared.stats()
            items = summaries
            stats = currentStats
            if let selectedID, let item = summaries.first(where: { $0.id == selectedID }) {
                editText = item.text
            } else {
                selectedID = summaries.first?.id
                editText = summaries.first?.text ?? ""
            }
        }
    }

    func select(_ item: ClipboardHistorySummary) {
        selectedID = item.id
        editText = item.text
    }

    func saveEdit() {
        guard let selectedID, canEdit else { return }
        let text = editText
        Task {
            await ClipboardHistoryStore.shared.update(id: selectedID, text: text)
            refresh()
        }
    }

    func togglePinned(_ item: ClipboardHistorySummary) {
        Task {
            await ClipboardHistoryStore.shared.setPinned(id: item.id, pinned: !item.pinned)
            refresh()
        }
    }

    func delete(_ item: ClipboardHistorySummary) {
        Task {
            await ClipboardHistoryStore.shared.delete(id: item.id)
            refresh()
        }
    }

    func clearAll() {
        Task {
            await ClipboardHistoryStore.shared.clear()
            refresh()
        }
    }

    func clearUnpinned() {
        Task {
            await ClipboardHistoryStore.shared.clearUnpinned()
            refresh()
        }
    }

    func ignoreSelectedSource() {
        guard let bundleID = selectedItem?.sourceBundleID else { return }
        var ids = LauncherPreferences.clipboardDisabledAppIDs
        guard !ids.contains(bundleID) else { return }
        ids.append(bundleID)
        LauncherPreferences.clipboardDisabledAppIDs = ids
        refreshIgnoredApps()
    }

    func removeIgnoredApp(_ app: ClipboardIgnoredApp) {
        LauncherPreferences.clipboardDisabledAppIDs = LauncherPreferences.clipboardDisabledAppIDs.filter { $0 != app.id }
        refreshIgnoredApps()
    }

    private func refreshIgnoredApps() {
        ignoredApps = LauncherPreferences.clipboardDisabledAppIDs.map { id in
            ClipboardIgnoredApp(id: id, name: Self.appName(bundleID: id))
        }
    }

    private static func appName(bundleID: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}

struct ClipboardIgnoredApp: Identifiable, Hashable {
    let id: String
    let name: String
}
