import AppKit
import ApplicationServices

@MainActor
enum ResultActionExecutor {
    static var onAskAI: ((String) -> Void)?

    static func perform(_ action: ResultAction) {
        switch action {
        case .askAI(let prompt):
            askAI(prompt)
        case .copy(let value):
            copy(value)
        case .openFile(let url):
            NSWorkspace.shared.open(url)
        case .openApplication(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .pasteClipboard(let value):
            pasteClipboard(value)
        case .pasteSnippet(let id):
            pasteSnippet(id)
        case .revealFile(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .system(let action):
            run(action)
        }
    }

    static func reveal(_ action: ResultAction) {
        guard let url = localURL(for: action) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func quickLook(_ url: URL) {
        runProcess("/usr/bin/qlmanage", ["-p", url.path])
    }

    static func open(_ url: URL, withApplicationAt appURL: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    static func applications(toOpen url: URL, limit: Int = 8) -> [(name: String, url: URL)] {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        var seen = Set<String>()
        let unique = apps.compactMap { appURL -> (name: String, url: URL)? in
            let key = appURL.path
            guard seen.insert(key).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
            return (name, appURL)
        }
        return Array(unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.prefix(limit))
    }

    static func searchWeb(_ query: String) {
        guard let url = LauncherPreferences.webSearchProvider.url(for: query) else { return }
        NSWorkspace.shared.open(url)
    }

    static func localURL(for action: ResultAction) -> URL? {
        switch action {
        case .openApplication(let url), .openFile(let url), .revealFile(let url):
            return url
        case .askAI, .copy, .openURL, .pasteClipboard, .pasteSnippet, .system:
            return nil
        }
    }

    static func textPayload(for result: SearchResult) -> String? {
        switch result.action {
        case .askAI(let prompt):
            return nonEmpty(prompt)
        case .copy(let value), .pasteClipboard(let value):
            return nonEmpty(value)
        case .openApplication(let url), .openFile(let url), .revealFile(let url):
            return nonEmpty(url.path)
        case .openURL(let url):
            return nonEmpty(url.absoluteString)
        case .pasteSnippet, .system:
            return nil
        }
    }

    static func webSearchQuery(for result: SearchResult) -> String? {
        switch result.action {
        case .askAI(let prompt):
            return nonEmpty(prompt)
        case .openURL(let url):
            return nonEmpty(url.host ?? url.absoluteString)
        case .openApplication(let url), .openFile(let url), .revealFile(let url):
            return nonEmpty(url.deletingPathExtension().lastPathComponent)
        case .copy(let value), .pasteClipboard(let value):
            return nonEmpty(value)
        case .pasteSnippet, .system:
            return nonEmpty(result.title)
        }
    }

    static func saveAsSnippet(text: String, suggestedName: String) {
        let expansion = text.replacingOccurrences(of: "\u{0000}", with: "")
        guard SnippetRecord.cleanedExpansion(expansion) != nil else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Save as Snippet"
        alert.informativeText = "Choose a trigger. vish will avoid overwriting an existing snippet."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        field.stringValue = snippetTrigger(from: suggestedName)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trigger = field.stringValue
        Task.detached(priority: .utility) {
            await SnippetStore.shared.saveUnique(trigger: trigger, expansion: expansion)
        }
    }

    static func urlString(for action: ResultAction) -> String? {
        guard case .openURL(let url) = action else { return nil }
        return url.absoluteString
    }

    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func askAI(_ prompt: String) {
        guard LauncherPreferences.localAIEnabled else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Local AI is off"
            alert.informativeText = "Enable Local AI in Settings > AI."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        onAskAI?(prompt)
    }

    private static func pasteClipboard(_ value: String) {
        copy(value)
        guard AXIsProcessTrusted() else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private static func pasteSnippet(_ id: String) {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        Task { @MainActor in
            guard let value = await SnippetStore.shared.expandedText(id: id, clipboard: clipboard) else { return }
            pasteClipboard(value)
        }
    }

    private static func run(_ action: SystemAction) {
        switch action {
        case .emptyTrash:
            guard confirm("Empty Trash?", "This permanently removes the current Trash contents.") else { return }
            runAppleScript("tell application \"Finder\" to empty trash")
        case .ejectDisks:
            runAppleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)")
        case .hideHiddenFiles:
            setFinderHiddenFiles(false)
        case .lockScreen:
            runProcess("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
        case .logOut:
            guard confirm("Log Out?", "This asks macOS to log out of the current user session.") else { return }
            runAppleScript("tell application \"System Events\" to log out")
        case .restart:
            guard confirm("Restart Mac?", "This asks macOS to restart this Mac.") else { return }
            runAppleScript("tell application \"System Events\" to restart")
        case .showHiddenFiles:
            setFinderHiddenFiles(true)
        case .shutDown:
            guard confirm("Shut Down Mac?", "This asks macOS to shut down this Mac.") else { return }
            runAppleScript("tell application \"System Events\" to shut down")
        case .sleep:
            runProcess("/usr/bin/pmset", ["sleepnow"])
        case .toggleDarkMode:
            runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        }
    }

    private static func setFinderHiddenFiles(_ visible: Bool) {
        runProcess("/usr/bin/defaults", [
            "write",
            "com.apple.finder",
            "AppleShowAllFiles",
            visible ? "true" : "false"
        ])
        runProcess("/usr/bin/killall", ["Finder"])
    }

    private static func runAppleScript(_ source: String) {
        runProcess("/usr/bin/osascript", ["-e", source])
    }

    private static func runProcess(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func snippetTrigger(from value: String) -> String {
        let seed = value
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .prefix(3)
            .joined(separator: "-")
        return ";\(seed.isEmpty ? "snippet" : String(seed.prefix(24)))"
    }

    private static func confirm(_ title: String, _ message: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
