import AppKit
import Sparkle

@MainActor
final class UpdateController: NSObject {
    static let shared = UpdateController()

    private let updaterController: SPUStandardUpdaterController?

    var isConfigured: Bool {
        updaterController != nil
    }

    private override init() {
        updaterController = Self.hasSparkleConfiguration
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        super.init()
    }

    func checkForUpdates() {
        guard let updaterController else {
            showMissingConfiguration()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    private static var hasSparkleConfiguration: Bool {
        configuredString("SUFeedURL") != nil && configuredString("SUPublicEDKey") != nil
    }

    private static func configuredString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    private func showMissingConfiguration() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Updates are not configured"
        alert.informativeText = "Release builds need VISH_SPARKLE_FEED_URL and VISH_SPARKLE_PUBLIC_ED_KEY."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
