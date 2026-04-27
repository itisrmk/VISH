import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var launcher: LauncherController?
    private let showSettings: () -> Void
    private let showOnboarding: () -> Void

    init(launcher: LauncherController, showSettings: @escaping () -> Void, showOnboarding: @escaping () -> Void) {
        self.launcher = launcher
        self.showSettings = showSettings
        self.showOnboarding = showOnboarding
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.title = "v"
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show vish", action: #selector(toggleLauncher), keyEquivalent: "")
        menu.items[0].target = self
        menu.addItem(withTitle: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.items[1].target = self
        menu.addItem(withTitle: "Getting Started...", action: #selector(openOnboarding), keyEquivalent: "")
        menu.items[2].target = self
        menu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.items[3].target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit vish", action: #selector(quit), keyEquivalent: "q")
        menu.items[5].target = self
        return menu
    }

    @objc private func toggleLauncher() {
        launcher?.toggle()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openOnboarding() {
        showOnboarding()
    }

    @objc private func checkForUpdates() {
        UpdateController.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
