import AppKit

@MainActor
final class LauncherController {
    private let panel = LauncherPanel()
    private let searchActor = SearchActor()
    private var appCatalogWatcher: AppCatalogWatcher?
    private var actionHistory = UserDefaults.standard.dictionary(forKey: "actions.history") as? [String: Int] ?? [:]
    private var aiRequestID = 0
    private var aiTask: Task<Void, Never>?
    private var fileBuffer: [URL] = []
    private var fileIndexWatcher: FileIndexWatcher?
    private var lockedActionResult: SearchResult?
    private var previewTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    var onOpenSettings: (() -> Void)?

    init() {
        panel.onQueryChange = { [weak self] query in self?.search(query) }
        panel.onActionQueryChange = { [weak self] query in self?.updateInlineActions(query: query) }
        panel.onMoveSelection = { [weak self] delta in self?.panel.moveSelection(by: delta) }
        panel.onActivateSelection = { [weak self] in self?.activateSelection() }
        panel.onActivateAction = { [weak self] in self?.activateInlineAction() }
        panel.onShowActions = { [weak self] in self?.enterActionMode() }
        panel.onSelectionChange = { [weak self] result in self?.schedulePreview(for: result) }
        panel.onQuickLookSelection = { [weak self] in self?.quickLookSelection() }
        panel.onShowDetails = { [weak self] in self?.showDetails() }
        panel.onToggleBuffer = { [weak self] in self?.toggleBufferForSelection() }
        panel.onOpenSettings = { [weak self] in
            self?.hide()
            self?.onOpenSettings?()
        }
        panel.onCancel = { [weak self] in self?.hide() }
        ResultActionExecutor.onAskAI = { [weak self] prompt in
            self?.startAI(prompt)
        }
        panel.prewarm()

        let searchActor = searchActor
        Task.detached(priority: .utility) {
            await searchActor.refreshApps()
        }
        appCatalogWatcher = AppCatalogWatcher(paths: AppSource.catalogRoots) {
            Task.detached(priority: .utility) {
                await searchActor.refreshApps()
            }
        }
        fileIndexWatcher = FileIndexWatcher()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        setIndexingInteractive(true)
        panel.show()
    }

    private func hide() {
        searchTask?.cancel()
        searchTask = nil
        previewTask?.cancel()
        previewTask = nil
        lockedActionResult = nil
        cancelAI()
        setIndexingInteractive(false)
        panel.hide()
    }

    private func search(_ query: String) {
        searchTask?.cancel()
        previewTask?.cancel()
        previewTask = nil
        panel.setPreview(nil, result: nil)
        cancelAI()
        lockedActionResult = nil
        panel.showResultsMode()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            panel.setResults([])
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(8))
            guard !Task.isCancelled else { return }
            PerformanceProbe.beginSearch()
            let results = await searchActor.search(query, includeSlowFiles: false)
            let isCancelled = Task.isCancelled
            PerformanceProbe.endSearch(resultCount: isCancelled ? 0 : results.count)
            guard !isCancelled else { return }
            panel.setResults(results)

            let supplemental = await searchActor.supplementalFileResults(for: query, currentResults: results)
            guard !Task.isCancelled, !supplemental.isEmpty else { return }
            guard supplemental.map(\.id) != results.map(\.id) else { return }
            panel.setResults(supplemental)
        }
    }

    private func schedulePreview(for result: SearchResult?) {
        previewTask?.cancel()
        guard let result, !panel.query.isEmpty else {
            panel.setPreview(nil, result: nil)
            return
        }

        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            let preview = await Task.detached(priority: .utility) {
                ResultPreviewProvider.preview(for: result)
            }.value
            guard !Task.isCancelled else { return }
            self?.panel.setPreview(preview, result: result)
        }
    }

    private func setIndexingInteractive(_ active: Bool) {
        Task.detached(priority: .utility) {
            await FileIndexStore.shared.setInteractiveActivity(active)
        }
    }

    private func activateSelection() {
        guard !panel.isShowingAIResponse else { return }
        if panel.isShowingActions {
            activateInlineAction()
            return
        }

        guard let result = panel.activateSelection() else {
            let query = panel.query
            guard !query.isEmpty else { return }
            hide()
            ResultActionExecutor.searchWeb(query)
            return
        }

        if case .askAI(let prompt) = result.action {
            recordActivation(result)
            ResultActionExecutor.perform(.askAI(prompt))
            return
        }

        hide()
        recordActivation(result)
        ResultActionExecutor.perform(result.action)
    }

    private func enterActionMode() {
        guard let result = panel.activateSelection() else { return }
        searchTask?.cancel()
        cancelAI()
        lockedActionResult = result
        panel.showActionMode(result: result, actions: inlineActions(for: result, query: ""))
    }

    private func updateInlineActions(query: String) {
        guard let result = lockedActionResult else { return }
        panel.setInlineActions(inlineActions(for: result, query: query))
    }

    private func activateInlineAction() {
        guard let action = panel.activateInlineAction() else { return }
        if let result = lockedActionResult {
            recordActionChoice(action.id, result: result)
        }
        action.run()
    }

    private func inlineActions(for result: SearchResult, query: String) -> [InlineActionItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var actions = baseInlineActions(for: result)
        if !trimmed.isEmpty, result.kind != .ai {
            actions.insert(InlineActionItem(
                id: "ai.custom",
                title: "Ask AI: \(trimmed)",
                subtitle: "Use \(result.title) as context",
                badge: "AI",
                symbolName: "sparkles"
            ) { [weak self] in
                self?.recordActivation(result)
                self?.startAI(question: trimmed, result: result)
            }, at: 0)
        }

        guard !trimmed.isEmpty else { return rankedActions(actions, for: result) }
        return actions.filter { item in
            item.id == "ai.custom"
                || item.title.localizedCaseInsensitiveContains(trimmed)
                || item.subtitle.localizedCaseInsensitiveContains(trimmed)
                || item.badge.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func baseInlineActions(for result: SearchResult) -> [InlineActionItem] {
        var actions: [InlineActionItem] = []
        let primaryTitle = switch result.kind {
        case .ai:
            "Ask"
        case .clipboard, .snippet:
            "Paste"
        case .app, .calculator, .file, .quicklink, .system, .url, .web:
            "Open"
        }

        actions.append(InlineActionItem(
            id: "primary",
            title: primaryTitle,
            subtitle: result.title,
            badge: "Return",
            symbolName: "return"
        ) { [weak self] in
            self?.recordActivation(result)
            if case .askAI = result.action {
                ResultActionExecutor.perform(result.action)
                return
            }
            self?.hide()
            ResultActionExecutor.perform(result.action)
        })
        actions.append(InlineActionItem(
            id: "details",
            title: "Show Details",
            subtitle: "Preview metadata and readable content",
            badge: "⌘I",
            symbolName: "info.circle"
        ) { [weak self] in
            self?.showDetails(for: result)
        })
        actions.append(contentsOf: aiInlineActions(for: result))

        let localURL = ResultActionExecutor.localURL(for: result.action)
        let urlString = ResultActionExecutor.urlString(for: result.action)
        let openWithURL = localURL ?? urlString.flatMap(URL.init(string:))

        if let localURL {
            actions.append(InlineActionItem(
                id: "quicklook",
                title: "Quick Look",
                subtitle: localURL.lastPathComponent,
                badge: "⌘Y",
                symbolName: "eye"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.quickLook(localURL)
            })
            actions.append(bufferInlineAction(for: result, url: localURL))
            actions.append(InlineActionItem(
                id: "reveal",
                title: "Reveal in Finder",
                subtitle: localURL.deletingLastPathComponent().path,
                badge: "File",
                symbolName: "folder"
            ) { [weak self] in
                self?.hide()
                self?.recordActivation(result)
                ResultActionExecutor.reveal(result.action)
            })
            actions.append(InlineActionItem(
                id: "copy-path",
                title: "Copy Path",
                subtitle: localURL.path,
                badge: "Copy",
                symbolName: "doc.on.doc"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.copy(localURL.path)
            })
        }

        if let openWithURL, result.kind != .app {
            actions.append(contentsOf: openWithInlineActions(for: openWithURL))
        }

        if let urlString {
            actions.append(InlineActionItem(
                id: "copy-url",
                title: "Copy URL",
                subtitle: urlString,
                badge: "Copy",
                symbolName: "link"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.copy(urlString)
            })
        }

        if let value = ResultActionExecutor.textPayload(for: result) {
            if localURL == nil, urlString == nil {
                actions.append(InlineActionItem(
                    id: "copy-text",
                    title: "Copy Text",
                    subtitle: shortSubtitle(value),
                    badge: "Copy",
                    symbolName: "doc.on.doc"
                ) { [weak self] in
                    self?.hide()
                    ResultActionExecutor.copy(value)
                })
            }
            if result.kind == .clipboard {
                actions.append(contentsOf: clipboardInlineActions(for: result, value: value))
            }
            actions.append(InlineActionItem(
                id: "save-snippet",
                title: "Save as Snippet",
                subtitle: "Create a reusable text expansion",
                badge: "Snippet",
                symbolName: "text.quote"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.saveAsSnippet(text: value, suggestedName: self?.snippetName(for: result) ?? result.title)
            })
        }

        if let query = ResultActionExecutor.webSearchQuery(for: result) {
            actions.append(InlineActionItem(
                id: "search-web",
                title: "Search Web",
                subtitle: query,
                badge: "Web",
                symbolName: "magnifyingglass"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.searchWeb(query)
            })
        }

        actions.append(InlineActionItem(
            id: "copy-name",
            title: "Copy Name",
            subtitle: result.title,
            badge: "Copy",
            symbolName: "textformat"
        ) { [weak self] in
            self?.hide()
            ResultActionExecutor.copy(result.title)
        })
        actions.append(contentsOf: bufferBatchActions())
        return actions
    }

    private func clipboardInlineActions(for result: SearchResult, value: String) -> [InlineActionItem] {
        guard let id = clipboardID(for: result) else { return [] }
        return [
            InlineActionItem(
                id: "clipboard.edit-paste",
                title: "Edit & Paste",
                subtitle: "Adjust text before pasting",
                badge: "Clip",
                symbolName: "pencil"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.editAndPasteClipboard(value)
            },
            InlineActionItem(
                id: "clipboard.pin",
                title: "Pin / Unpin",
                subtitle: "Keep or release this clipboard item",
                badge: "Pin",
                symbolName: "pin"
            ) { [weak self] in
                Task.detached(priority: .utility) {
                    await ClipboardHistoryStore.shared.togglePinned(id: id)
                }
                self?.updateInlineActions(query: self?.panel.query ?? "")
            },
            InlineActionItem(
                id: "clipboard.delete",
                title: "Delete Clipboard Item",
                subtitle: "Remove from history",
                badge: "Delete",
                symbolName: "trash"
            ) { [weak self] in
                Task.detached(priority: .utility) {
                    await ClipboardHistoryStore.shared.delete(id: id)
                }
                self?.hide()
            }
        ]
    }

    private func aiInlineActions(for result: SearchResult) -> [InlineActionItem] {
        AIContextBuilder.actions(for: result).map { action in
            InlineActionItem(
                id: "ai.\(action.rawValue)",
                title: action.menuTitle,
                subtitle: "Use selected item as context",
                badge: "AI",
                symbolName: "sparkles"
            ) { [weak self] in
                self?.recordActivation(result)
                self?.startAI(action, result: result)
            }
        }
    }

    private func openWithInlineActions(for url: URL) -> [InlineActionItem] {
        ResultActionExecutor.applications(toOpen: url).map { app in
            InlineActionItem(
                id: "open-with.\(app.url.path)",
                title: "Open with \(app.name)",
                subtitle: app.url.path,
                badge: "App",
                symbolName: "app"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.open(url, withApplicationAt: app.url)
            }
        }
    }

    private func bufferInlineAction(for result: SearchResult, url: URL) -> InlineActionItem {
        let contains = fileBuffer.contains(url)
        return InlineActionItem(
            id: contains ? "buffer.remove" : "buffer.add",
            title: contains ? "Remove from File Buffer" : "Add to File Buffer",
            subtitle: contains ? "\(fileBuffer.count) item(s) buffered" : url.lastPathComponent,
            badge: "⌘B",
            symbolName: contains ? "tray.and.arrow.up" : "tray.and.arrow.down"
        ) { [weak self] in
            self?.toggleBuffer(url)
            self?.updateInlineActions(query: self?.panel.query ?? "")
        }
    }

    private func bufferBatchActions() -> [InlineActionItem] {
        guard !fileBuffer.isEmpty else { return [] }
        let count = fileBuffer.count
        let paths = fileBuffer.map(\.path).joined(separator: "\n")
        return [
            InlineActionItem(
                id: "buffer.copy-paths",
                title: "Copy Buffered Paths",
                subtitle: "\(count) file(s)",
                badge: "Buffer",
                symbolName: "doc.on.doc"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.copy(paths)
            },
            InlineActionItem(
                id: "buffer.reveal",
                title: "Reveal Buffered Files",
                subtitle: "\(count) file(s)",
                badge: "Buffer",
                symbolName: "folder"
            ) { [weak self] in
                self?.hide()
                ResultActionExecutor.reveal(self?.fileBuffer ?? [])
            },
            InlineActionItem(
                id: "buffer.ask-ai",
                title: "Ask AI About Buffer",
                subtitle: "Use file names and tiny previews",
                badge: "AI",
                symbolName: "sparkles"
            ) { [weak self] in
                self?.startAIForBuffer()
            },
            InlineActionItem(
                id: "buffer.clear",
                title: "Clear File Buffer",
                subtitle: "\(count) file(s)",
                badge: "Buffer",
                symbolName: "xmark"
            ) { [weak self] in
                self?.fileBuffer.removeAll()
                self?.updateInlineActions(query: self?.panel.query ?? "")
            }
        ]
    }

    private func recordActivation(_ result: SearchResult) {
        Task.detached(priority: .utility) { [searchActor] in
            await searchActor.recordActivation(result)
        }
    }

    private func recordActionChoice(_ actionID: String, result: SearchResult) {
        guard actionID != "primary" else { return }
        let key = "\(result.kind.rawValue).\(actionID)"
        actionHistory[key, default: 0] += 1
        UserDefaults.standard.set(actionHistory, forKey: "actions.history")
    }

    private func rankedActions(_ actions: [InlineActionItem], for result: SearchResult) -> [InlineActionItem] {
        guard actions.count > 2 else { return actions }
        let priority = actions.prefix(1)
        let rest = actions.dropFirst().sorted { left, right in
            let leftScore = actionHistory["\(result.kind.rawValue).\(left.id)", default: 0]
            let rightScore = actionHistory["\(result.kind.rawValue).\(right.id)", default: 0]
            if leftScore == rightScore { return false }
            return leftScore > rightScore
        }
        return Array(priority) + rest
    }

    private func quickLookSelection() {
        guard let url = activeResult().flatMap({ ResultActionExecutor.localURL(for: $0.action) }) else { return }
        hide()
        ResultActionExecutor.quickLook(url)
    }

    private func showDetails() {
        guard let result = activeResult() else { return }
        showDetails(for: result)
    }

    private func showDetails(for result: SearchResult) {
        previewTask?.cancel()
        searchTask?.cancel()
        let loading = ResultPreviewProvider.loading(for: result)
        panel.showDetail(loading, result: result)
        previewTask = Task { [weak self] in
            let preview = await Task.detached(priority: .utility) {
                ResultPreviewProvider.preview(for: result)
            }.value
            guard !Task.isCancelled else { return }
            self?.panel.showDetail(preview, result: result)
        }
    }

    private func toggleBufferForSelection() {
        guard let url = activeResult().flatMap({ ResultActionExecutor.localURL(for: $0.action) }) else { return }
        toggleBuffer(url)
        if let result = lockedActionResult {
            panel.setInlineActions(inlineActions(for: result, query: panel.query))
        }
    }

    private func toggleBuffer(_ url: URL) {
        if let index = fileBuffer.firstIndex(of: url) {
            fileBuffer.remove(at: index)
        } else {
            fileBuffer.append(url)
        }
    }

    private func activeResult() -> SearchResult? {
        lockedActionResult ?? panel.selectedResult()
    }

    private func startAI(_ prompt: String) {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LauncherPreferences.localAIEnabled else {
            panel.showAIMessage("Enable Local AI in Settings > AI.", status: "Off")
            return
        }
        guard !value.isEmpty else {
            panel.showAIMessage("Type a question after ai or ?.", status: "Waiting")
            return
        }

        searchTask?.cancel()
        aiTask?.cancel()
        aiRequestID += 1
        let requestID = aiRequestID
        panel.beginAIResponse()

        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await LocalAIClient.streamAnswer(prompt: value) { [weak self] chunk in
                    guard let self, self.aiRequestID == requestID else { return }
                    self.panel.appendAIResponse(chunk)
                }
                guard aiRequestID == requestID, !Task.isCancelled else { return }
                panel.finishAIResponse(status: "Done")
            } catch is CancellationError {
                guard aiRequestID == requestID else { return }
                panel.finishAIResponse(status: "Cancelled")
            } catch {
                guard aiRequestID == requestID else { return }
                panel.showAIMessage(
                    "Check Settings > AI. Ollama must be running and a local model must be installed.",
                    status: "Unavailable"
                )
            }
        }
    }

    private func startAI(_ action: AIContextAction, result: SearchResult) {
        guard LauncherPreferences.localAIEnabled else {
            panel.showAIMessage("Enable Local AI in Settings > AI.", status: "Off")
            return
        }

        searchTask?.cancel()
        aiTask?.cancel()
        aiRequestID += 1
        let requestID = aiRequestID
        panel.beginAIResponse(title: action.title, status: "Reading")

        aiTask = Task { [weak self] in
            guard let self else { return }
            let prompt = await AIContextBuilder.prompt(for: result, action: action)
            guard aiRequestID == requestID, !Task.isCancelled else { return }
            panel.finishAIResponse(status: "Thinking")

            do {
                try await LocalAIClient.streamAnswer(prompt: prompt) { [weak self] chunk in
                    guard let self, self.aiRequestID == requestID else { return }
                    self.panel.appendAIResponse(chunk)
                }
                guard aiRequestID == requestID, !Task.isCancelled else { return }
                panel.finishAIResponse(status: "Done")
            } catch is CancellationError {
                guard aiRequestID == requestID else { return }
                panel.finishAIResponse(status: "Cancelled")
            } catch {
                guard aiRequestID == requestID else { return }
                panel.showAIMessage(
                    "Check Settings > AI. Ollama must be running and a local model must be installed.",
                    status: "Unavailable"
                )
            }
        }
    }

    private func startAI(question: String, result: SearchResult) {
        guard LauncherPreferences.localAIEnabled else {
            panel.showAIMessage("Enable Local AI in Settings > AI.", status: "Off")
            return
        }

        searchTask?.cancel()
        aiTask?.cancel()
        aiRequestID += 1
        let requestID = aiRequestID
        panel.beginAIResponse(title: "Ask AI", status: "Reading")

        aiTask = Task { [weak self] in
            guard let self else { return }
            let prompt = await AIContextBuilder.prompt(for: result, question: question)
            guard aiRequestID == requestID, !Task.isCancelled else { return }
            panel.finishAIResponse(status: "Thinking")

            do {
                try await LocalAIClient.streamAnswer(prompt: prompt) { [weak self] chunk in
                    guard let self, self.aiRequestID == requestID else { return }
                    self.panel.appendAIResponse(chunk)
                }
                guard aiRequestID == requestID, !Task.isCancelled else { return }
                panel.finishAIResponse(status: "Done")
            } catch is CancellationError {
                guard aiRequestID == requestID else { return }
                panel.finishAIResponse(status: "Cancelled")
            } catch {
                guard aiRequestID == requestID else { return }
                panel.showAIMessage(
                    "Check Settings > AI. Ollama must be running and a local model must be installed.",
                    status: "Unavailable"
                )
            }
        }
    }

    private func startAIForBuffer() {
        guard LauncherPreferences.localAIEnabled else {
            panel.showAIMessage("Enable Local AI in Settings > AI.", status: "Off")
            return
        }
        let urls = fileBuffer
        guard !urls.isEmpty else { return }

        searchTask?.cancel()
        aiTask?.cancel()
        aiRequestID += 1
        let requestID = aiRequestID
        panel.beginAIResponse(title: "File Buffer AI", status: "Reading")

        aiTask = Task { [weak self] in
            guard let self else { return }
            let prompt = await Task.detached(priority: .utility) {
                Self.bufferPrompt(for: urls)
            }.value
            guard aiRequestID == requestID, !Task.isCancelled else { return }
            panel.finishAIResponse(status: "Thinking")

            do {
                try await LocalAIClient.streamAnswer(prompt: prompt) { [weak self] chunk in
                    guard let self, self.aiRequestID == requestID else { return }
                    self.panel.appendAIResponse(chunk)
                }
                guard aiRequestID == requestID, !Task.isCancelled else { return }
                panel.finishAIResponse(status: "Done")
            } catch is CancellationError {
                guard aiRequestID == requestID else { return }
                panel.finishAIResponse(status: "Cancelled")
            } catch {
                guard aiRequestID == requestID else { return }
                panel.showAIMessage(
                    "Check Settings > AI. Ollama must be running and a local model must be installed.",
                    status: "Unavailable"
                )
            }
        }
    }

    private nonisolated static func bufferPrompt(for urls: [URL]) -> String {
        let previews = urls.prefix(12).map { url -> String in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .localizedTypeDescriptionKey, .fileSizeKey])
            let kind = values?.localizedTypeDescription ?? (values?.isDirectory == true ? "Folder" : "File")
            let preview: String
            if values?.isDirectory == true {
                preview = "Folder"
            } else {
                switch FilePreviewReader.preview(for: url, byteLimit: 2_048, maxCharacters: 600, pdfPageLimit: 1) {
                case .available(let text):
                    preview = text
                case .unavailable(let reason):
                    preview = "Preview unavailable: \(reason)"
                }
            }
            return """
            - \(url.lastPathComponent)
              path: \(url.path)
              kind: \(kind)
              preview: \(preview)
            """
        }.joined(separator: "\n")

        return """
        You are VISH local AI. The user selected these files in the launcher buffer. Help with a concise, practical answer using only the provided metadata and tiny previews unless you explicitly say more context is needed.

        Files:
        \(previews)
        """
    }

    private func cancelAI() {
        aiRequestID += 1
        aiTask?.cancel()
        aiTask = nil
    }

    private func snippetName(for result: SearchResult) -> String {
        if let url = ResultActionExecutor.localURL(for: result.action) {
            return url.deletingPathExtension().lastPathComponent
        }
        if let urlString = ResultActionExecutor.urlString(for: result.action),
           let host = URL(string: urlString)?.host {
            return host
        }
        return result.title
    }

    private func clipboardID(for result: SearchResult) -> String? {
        guard result.kind == .clipboard, result.id.hasPrefix("clipboard:") else { return nil }
        return String(result.id.dropFirst("clipboard:".count))
    }

    private func shortSubtitle(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(96))
    }
}
