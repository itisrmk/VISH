import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var settingsController: SettingsController?
    private var launcherController: LauncherController?
    private var hotkeyController: HotkeyController?
    private var clipboardMonitor: ClipboardHistoryMonitor?
    private var updateController: UpdateController?
    private var onboardingController: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launcher = LauncherController()
        launcher.onOpenSettings = { [weak self] in
            self?.showSettings()
        }

        launcherController = launcher
        clipboardMonitor = ClipboardHistoryMonitor()
        updateController = UpdateController.shared
        hotkeyController = HotkeyController(launcher: launcher)
        menuBarController = MenuBarController(
            launcher: launcher,
            showSettings: { [weak self] in self?.showSettings() },
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )
        PerformanceProbe.markColdLaunchReady()

        if !LauncherPreferences.onboardingCompleted {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboarding(markCompleteOnClose: true)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showSettings() {
        let settings = settingsController ?? SettingsController()
        settingsController = settings
        settings.show()
    }

    private func showOnboarding(markCompleteOnClose: Bool = false) {
        let onboarding = onboardingController ?? OnboardingController()
        onboardingController = onboarding
        onboarding.show(markCompleteOnClose: markCompleteOnClose)
    }
}

@MainActor
enum PerformanceProbe {
    private static let log = OSLog(subsystem: "com.vish.app", category: "Performance")
    private static var processStartNanos = DispatchTime.now().uptimeNanoseconds
    private static var hotkeyToFrame: OSSignpostID?
    private static var keystrokeToRender: OSSignpostID?
    private static var search: OSSignpostID?

    static func markProcessStart() {
        processStartNanos = DispatchTime.now().uptimeNanoseconds
    }

    static func markColdLaunchReady() {
        let now = DispatchTime.now().uptimeNanoseconds
        let ms = Double(now >= processStartNanos ? now - processStartNanos : 0) / 1_000_000
        os_signpost(.event, log: log, name: "ColdLaunchReady", "%{public}.2f ms", ms)
    }

    static func beginHotkeyToFrame() {
        endHotkeyToFrame()
        let id = OSSignpostID(log: log)
        hotkeyToFrame = id
        os_signpost(.begin, log: log, name: "HotkeyToFrame", signpostID: id)
    }

    static func endHotkeyToFrame() {
        guard let id = hotkeyToFrame else { return }
        os_signpost(.end, log: log, name: "HotkeyToFrame", signpostID: id)
        hotkeyToFrame = nil
    }

    static func beginKeystrokeToRender() {
        endKeystrokeToRender()
        let id = OSSignpostID(log: log)
        keystrokeToRender = id
        os_signpost(.begin, log: log, name: "KeystrokeToRender", signpostID: id)
    }

    static func endKeystrokeToRender() {
        guard let id = keystrokeToRender else { return }
        os_signpost(.end, log: log, name: "KeystrokeToRender", signpostID: id)
        keystrokeToRender = nil
    }

    static func beginSearch() {
        endSearch(resultCount: 0)
        let id = OSSignpostID(log: log)
        search = id
        os_signpost(.begin, log: log, name: "Search", signpostID: id)
    }

    static func endSearch(resultCount: Int) {
        guard let id = search else { return }
        os_signpost(.end, log: log, name: "Search", signpostID: id, "%{public}d results", resultCount)
        search = nil
    }

    static func beginSpotlightQuery() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "SpotlightQuery", signpostID: id)
        return id
    }

    static func endSpotlightQuery(_ id: OSSignpostID, resultCount: Int) {
        os_signpost(.end, log: log, name: "SpotlightQuery", signpostID: id, "%{public}d results", resultCount)
    }
}
