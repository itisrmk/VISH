import AppKit
import ApplicationServices

@MainActor
final class PrivacyDashboardModel: ObservableObject {
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var fullDiskVisible = false
    @Published private(set) var clipboardStats = ClipboardHistoryStats.empty
    @Published private(set) var dataSizeText = "0 KB"
    @Published private(set) var dataPath = ""
    @Published private(set) var refreshedAt = Date()

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
        fullDiskVisible = Self.protectedFoldersVisible()
        refreshedAt = Date()

        Task.detached(priority: .utility) {
            let clipboardStats = await ClipboardHistoryStore.shared.stats()
            let dataURL = Self.appSupportDirectory()
            let byteSize = Self.directorySize(dataURL)
            let dataSizeText = ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
            await MainActor.run {
                self.clipboardStats = clipboardStats
                self.dataPath = dataURL.path
                self.dataSizeText = dataSizeText
            }
        }
    }

    func revealDataFolder() {
        let url = Self.appSupportDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private nonisolated static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("vish", isDirectory: true)
    }

    private nonisolated static func protectedFoldersVisible() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "Library/Mail",
            "Library/Messages",
            "Library/Safari"
        ]
        return candidates.contains { relativePath in
            FileManager.default.isReadableFile(atPath: home.appendingPathComponent(relativePath).path)
        }
    }

    private nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
