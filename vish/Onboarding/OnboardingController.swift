import AppKit
import SwiftUI

@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private var delegate: WindowDelegate?

    func show(markCompleteOnClose: Bool = false) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView {
            LauncherPreferences.onboardingCompleted = true
            window.close()
        })
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to vish"
        let delegate = WindowDelegate {
            if markCompleteOnClose {
                LauncherPreferences.onboardingCompleted = true
            }
        }
        self.delegate = delegate
        window.delegate = delegate

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
