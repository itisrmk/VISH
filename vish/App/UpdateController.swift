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
            showManualUpdateFallback()
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

    private func showManualUpdateFallback() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Manual update required"
        alert.informativeText = "This build is not connected to the signed update feed. Open GitHub Releases to download the latest VISH build."
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "https://github.com/itisrmk/VISH/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }
}
