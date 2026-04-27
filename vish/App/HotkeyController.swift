@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    @MainActor
    static let toggleLauncher = Self("toggleLauncher", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class HotkeyController {
    init(launcher: LauncherController) {
        KeyboardShortcuts.onKeyDown(for: .toggleLauncher) { [weak launcher] in
            Task { @MainActor in
                PerformanceProbe.beginHotkeyToFrame()
                launcher?.toggle()
            }
        }
    }
}
