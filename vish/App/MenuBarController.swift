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
        statusItem = NSStatusBar.system.statusItem(withLength: 24)
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.imagePosition = .imageOnly
            button.toolTip = "VISH"
            button.setAccessibilityLabel("VISH")
        }
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

private enum MenuBarIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let ring = NSBezierPath(ovalIn: NSRect(x: 3.0, y: 3.0, width: 12.0, height: 12.0))
        ring.lineWidth = 1.8
        ring.stroke()

        let core = NSBezierPath(ovalIn: NSRect(x: 7.35, y: 7.35, width: 3.3, height: 3.3))
        core.fill()

        let cut = NSBezierPath()
        cut.lineCapStyle = .round
        cut.lineJoinStyle = .round
        cut.lineWidth = 1.9
        cut.move(to: NSPoint(x: 5.2, y: 12.6))
        cut.line(to: NSPoint(x: 8.9, y: 8.2))
        cut.line(to: NSPoint(x: 12.7, y: 12.6))
        cut.stroke()

        image.isTemplate = true
        return image
    }
}
