import AppKit
import ApplicationServices
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(LauncherPreferences.roundedCornersKey) private var roundedCorners = true
    @AppStorage(LauncherPreferences.appearanceKey) private var appearance = LauncherAppearance.system.rawValue
    @AppStorage(LauncherPreferences.textSizeKey) private var textSize = LauncherTextSize.regular.rawValue
    @AppStorage(LauncherPreferences.launcherScaleKey) private var launcherScale = LauncherPreferences.defaultLauncherScale
    @AppStorage(LauncherPreferences.fullDiskIndexingEnabledKey) private var fullDiskIndexingEnabled = false
    @AppStorage(LauncherPreferences.webSearchProviderKey) private var webSearchProvider = WebSearchProvider.google.rawValue
    @AppStorage(LauncherPreferences.clipboardHistoryEnabledKey) private var clipboardHistoryEnabled = false
    @AppStorage(LauncherPreferences.localAIEnabledKey) private var localAIEnabled = false
    @AppStorage(LauncherPreferences.localAIBaseURLKey) private var localAIBaseURL = LauncherPreferences.defaultLocalAIBaseURL
    @AppStorage(LauncherPreferences.localAIModelKey) private var localAIModel = ""
    @AppStorage(LauncherPreferences.localAIEmbeddingModelKey) private var localAIEmbeddingModel = ""
    @StateObject private var indexing = IndexingProgressModel()
    @StateObject private var localAI = LocalAISettingsModel()
    @StateObject private var quicklinks = QuicklinkSettingsModel()
    @StateObject private var snippets = SnippetSettingsModel()
    @State private var pane = SettingsPane.setup
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        ZStack {
            SettingsSkin.background
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 14)
                content
            }
            .padding(.horizontal, 14)
            .padding(.top, 42)
            .padding(.bottom, 14)
        }
        .frame(width: 680, height: 536)
        .tint(SettingsSkin.blue)
        .toggleStyle(GlassSwitchStyle())
        .onAppear {
            refreshReadiness()
            indexing.update(enabled: fullDiskIndexingEnabled)
            if fullDiskIndexingEnabled, !indexing.hasCompleted {
                indexing.start()
            }
        }
        .onChange(of: fullDiskIndexingEnabled) { _, enabled in
            indexing.update(enabled: enabled)
            if enabled {
                indexing.start()
            }
        }
        .onChange(of: localAIEnabled) { _, enabled in
            if enabled {
                localAI.refresh(baseURL: localAIBaseURL)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Circle()
                    .fill(SettingsSkin.logoGradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text("V")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                Text("VISH")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(SettingsSkin.logoGradient)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            VStack(spacing: 6) {
                ForEach(SettingsPane.allCases) { item in
                    paneButton(item)
                }
            }

            Spacer()
        }
        .frame(width: 160)
        .padding(10)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pane.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Group {
                switch pane {
                case .setup:
                    setupPane
                case .launcher:
                    launcherPane
                case .search:
                    searchPane
                case .files:
                    filesPane
                case .ai:
                    aiPane
                case .quicklinks:
                    quicklinksPane
                case .snippets:
                    snippetsPane
                case .about:
                    aboutPane
                case .help:
                    helpPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var setupPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                surface {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Make VISH ready, then leave it alone.")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Optional features stay trigger-based and off the launcher hot path.")
                                .font(.callout)
                                .foregroundStyle(SettingsSkin.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Refresh", action: refreshReadiness)
                            .buttonStyle(GlassButtonStyle())
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    setupCard(
                        "Launcher",
                        subtitle: "Hotkey, theme, size",
                        symbol: "command",
                        state: .ready,
                        action: "Tune"
                    ) { pane = .launcher }
                    setupCard(
                        "Files",
                        subtitle: filesSetupSubtitle,
                        symbol: "externaldrive",
                        state: filesSetupState,
                        action: filesSetupAction
                    ) { pane = .files }
                    setupCard(
                        "Clipboard",
                        subtitle: clipboardSetupSubtitle,
                        symbol: "doc.on.clipboard",
                        state: clipboardSetupState,
                        action: "Open"
                    ) { pane = .search }
                    setupCard(
                        "AI",
                        subtitle: aiSetupSubtitle,
                        symbol: "sparkle.magnifyingglass",
                        state: aiSetupState,
                        action: "Open"
                    ) { pane = .ai }
                }

                surface {
                    HStack(spacing: 10) {
                        metricChip("Launch", "≤120 ms")
                        metricChip("Hotkey", "≤16 ms")
                        metricChip("Render", "≤16 ms")
                        metricChip("Idle", "0% CPU")
                    }
                }
            }
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
    }

    private var launcherPane: some View {
        VStack(spacing: 14) {
            surface {
                controlRow("Hotkey") {
                    KeyboardShortcuts.Recorder("Toggle launcher", name: .toggleLauncher)
                        .frame(width: 210, alignment: .trailing)
                }
                divider
                controlRow("Theme") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(LauncherAppearance.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                divider
                controlRow("Type") {
                    Picker("Text size", selection: $textSize) {
                        ForEach(LauncherTextSize.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                divider
                controlRow("Size") {
                    HStack(spacing: 10) {
                        Slider(value: launcherScaleBinding, in: LauncherPreferences.launcherScaleRange)
                            .frame(width: 134)
                        Text(launcherScaleText)
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                            .foregroundStyle(SettingsSkin.muted)
                            .frame(width: 44, alignment: .trailing)
                        Button("Center", action: resetLauncherPosition)
                            .buttonStyle(GlassButtonStyle())
                    }
                }
                divider
                controlRow("Corners") {
                    Toggle("Rounded", isOn: $roundedCorners)
                        .labelsHidden()
                }
            }

            launcherPreview
        }
    }

    private var launcherPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SettingsSkin.blue)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Search")
                .font(.system(size: previewSearchFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
            Spacer()
            Text("⌥ Space")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(SettingsSkin.muted)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(SettingsSkin.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: roundedCorners ? 24 : 4, style: .continuous)
                .stroke(SettingsSkin.stroke, lineWidth: 1)
        }
    }

    private var launcherScaleBinding: Binding<Double> {
        Binding {
            LauncherPreferences.normalizedLauncherScale(launcherScale)
        } set: { value in
            launcherScale = LauncherPreferences.normalizedLauncherScale(value)
        }
    }

    private var launcherScaleText: String {
        "\(Int((LauncherPreferences.normalizedLauncherScale(launcherScale) * 100).rounded()))%"
    }

    private var previewSearchFontSize: CGFloat {
        let base: CGFloat = textSize == LauncherTextSize.large.rawValue ? 19 : 17
        return min(max(base * CGFloat(LauncherPreferences.normalizedLauncherScale(launcherScale)), 15), 23)
    }

    private var searchPane: some View {
        VStack(spacing: 14) {
            surface {
                controlRow("Web") {
                    Picker("Web provider", selection: $webSearchProvider) {
                        ForEach(WebSearchProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                divider
                controlRow("Clipboard") {
                    HStack(spacing: 12) {
                        Button("Access", action: openAccessibilitySettings)
                            .buttonStyle(GlassButtonStyle())
                        Button("Clear") {
                            Task {
                                await ClipboardHistoryStore.shared.clear()
                            }
                        }
                        .disabled(!clipboardHistoryEnabled)
                        .buttonStyle(GlassButtonStyle())
                        Toggle("Clipboard", isOn: $clipboardHistoryEnabled)
                            .labelsHidden()
                    }
                }
                divider
                tokenRow(["URL", "Math", "Quicklinks"])
            }
        }
    }

    private var filesPane: some View {
        VStack(spacing: 14) {
            surface {
                controlRow("Full disk") {
                    Toggle("Full disk", isOn: $fullDiskIndexingEnabled)
                        .labelsHidden()
                }
                divider
                HStack(spacing: 10) {
                    Button("Access", action: openFullDiskAccessSettings)
                        .buttonStyle(GlassButtonStyle())
                    Button("Reveal", action: revealApp)
                        .buttonStyle(GlassButtonStyle())
                    Spacer()
                    Button(indexing.hasCompleted ? "Recheck" : "Warm") {
                        indexing.start()
                    }
                    .disabled(indexing.isRunning || !fullDiskIndexingEnabled)
                    .buttonStyle(GlassButtonStyle())
                }
            }

            indexMeter
        }
    }

    private var aiPane: some View {
        VStack(spacing: 14) {
            surface {
                controlRow("Local AI") {
                    Toggle("Local AI", isOn: $localAIEnabled)
                        .labelsHidden()
                }
                divider
                controlRow("Ollama") {
                    HStack(spacing: 10) {
                        TextField("http://localhost:11434", text: $localAIBaseURL)
                            .textFieldStyle(.plain)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(width: 220, height: 32)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button(localAI.isChecking ? "Checking" : "Check") {
                            localAI.refresh(baseURL: localAIBaseURL)
                        }
                        .disabled(localAI.isChecking)
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                divider
                controlRow("Model") {
                    HStack(spacing: 10) {
                        let installable = localAI.shouldInstallChatModel(localAIModel)
                        let diskBlocked = localAI.isChatModelDiskBlocked(localAIModel)
                        let showInstallState = installable || diskBlocked || localAI.isInstallingChatModel
                        Picker("Model", selection: $localAIModel) {
                            Text("Auto").tag("")
                            ForEach(localAI.modelChoices(current: localAIModel)) { choice in
                                Text(choice.menuTitle).tag(choice.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: showInstallState ? 174 : 260)
                        .disabled(localAI.isInstallingChatModel)

                        if showInstallState {
                            Button(localAI.isInstallingChatModel ? "Installing" : diskBlocked ? "Need Space" : "Install") {
                                localAI.installChatModel(baseURL: localAIBaseURL, model: localAIModel)
                            }
                            .disabled(localAI.isInstallingChatModel || localAIModel.isEmpty || diskBlocked)
                            .buttonStyle(GlassButtonStyle())
                        }
                    }
                }
                divider
                controlRow("Embedding") {
                    HStack(spacing: 10) {
                        Picker("Embedding", selection: $localAIEmbeddingModel) {
                            Text("Auto").tag("")
                            ForEach(localAI.embeddingModelChoices(current: localAIEmbeddingModel), id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(width: localAI.hasEmbeddingModel ? 260 : 172)
                        .disabled(!localAI.hasEmbeddingModel)
                        if !localAI.hasEmbeddingModel || localAI.isInstallingEmbeddingModel {
                            Button(localAI.isInstallingEmbeddingModel ? "Installing" : "Install") {
                                localAI.installRecommendedEmbeddingModel(baseURL: localAIBaseURL)
                            }
                            .disabled(localAI.isInstallingEmbeddingModel)
                            .buttonStyle(GlassButtonStyle())
                        }
                    }
                }
                divider
                tokenRow(["ai question", "? question", "ai find"])
            }

            aiStatusCard
        }
        .onAppear {
            if localAIEnabled {
                localAI.refresh(baseURL: localAIBaseURL)
            }
        }
    }

    private var quicklinksPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                surface {
                    HStack(alignment: .top, spacing: 12) {
                        quicklinkLogoPicker
                        quicklinkField("Keyword", placeholder: "gh", text: $quicklinks.keyword, monospaced: true)
                            .frame(width: 112)
                        quicklinkField("Name", placeholder: "GitHub", text: $quicklinks.name)
                            .frame(maxWidth: .infinity)
                    }
                    divider
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("URL Template")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SettingsSkin.muted)
                                .textCase(.uppercase)
                            Spacer()
                            Button("Insert {query}", action: quicklinks.insertQueryToken)
                                .buttonStyle(GlassButtonStyle())
                        }
                        TextField("https://github.com/search?q={query}", text: $quicklinks.urlTemplate)
                            .textFieldStyle(.plain)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    divider
                    HStack(spacing: 10) {
                        Text("Presets")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SettingsSkin.muted)
                            .textCase(.uppercase)
                            .frame(width: 66, alignment: .leading)
                        ForEach(QuicklinkRecord.defaults) { item in
                            Button(item.keyword) {
                                quicklinks.useStarter(item)
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                        Spacer()
                    }
                    divider
                    HStack(spacing: 10) {
                        Button("New", action: quicklinks.new)
                            .buttonStyle(GlassButtonStyle())
                        Button("Delete", action: quicklinks.deleteSelected)
                            .disabled(quicklinks.selectedID == nil)
                            .buttonStyle(GlassButtonStyle())
                        Spacer()
                        Button("Save", action: quicklinks.save)
                            .disabled(!quicklinks.canSave)
                            .buttonStyle(GlassButtonStyle())
                    }
                }

                LazyVStack(spacing: 8) {
                    HStack {
                        Text("Saved")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SettingsSkin.muted)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(quicklinks.items) { item in
                        quicklinkButton(item)
                    }
                }
            }
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: quicklinks.load)
    }

    private var snippetsPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                surface {
                    controlRow("Trigger") {
                        TextField(";name", text: $snippets.trigger)
                            .textFieldStyle(.plain)
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(width: 220, height: 32)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    divider
                    snippetDiscoveryRows
                    divider
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expansion")
                            .font(.headline)
                            .foregroundStyle(.white)
                        TextEditor(text: $snippets.expansion)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 86)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    divider
                    HStack(spacing: 10) {
                        Button("New", action: snippets.new)
                            .buttonStyle(GlassButtonStyle())
                        Button("Delete", action: snippets.deleteSelected)
                            .disabled(snippets.selectedID == nil)
                            .buttonStyle(GlassButtonStyle())
                        Spacer()
                        Button("Save", action: snippets.save)
                            .disabled(!snippets.canSave)
                            .buttonStyle(GlassButtonStyle())
                    }
                }

                LazyVStack(spacing: 8) {
                    HStack {
                        Text("Saved")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SettingsSkin.muted)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(snippets.items) { item in
                        snippetButton(item)
                    }
                }
            }
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: snippets.load)
    }

    private var snippetDiscoveryRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Tokens")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 80, alignment: .leading)
                ForEach(SnippetRecord.tokens) { token in
                    Button {
                        snippets.insertToken(token)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.value)
                                .font(.system(.callout, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white)
                            Text(token.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SettingsSkin.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Text("Starters")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 80, alignment: .leading)
                ForEach(SnippetRecord.starters) { starter in
                    Button {
                        snippets.useStarter(starter)
                    } label: {
                        Text(starter.title)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var helpPane: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([
                    "app / url / math", "' file", "space file",
                    "open file", "find file", "in text",
                    "tags name", "kind:image", "all:",
                    "gh react", "yt swiftui", "maps coffee",
                    "; trigger", "{date}", "{time}",
                    "{clipboard}", ";date", ";clip",
                    "clip text", "clipboard", "ai question",
                    "? question", "↵ open", "⌘1...9",
                    "esc close", "⌘/"
                ], id: \.self) { command in
                    commandChip(command)
                }
            }
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
    }

    private var aboutPane: some View {
        VStack(spacing: 14) {
            surface {
                controlRow("Version") {
                    Text(appVersion)
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .foregroundStyle(SettingsSkin.muted)
                }
                divider
                controlRow("Updates") {
                    Button("Check", action: UpdateController.shared.checkForUpdates)
                        .buttonStyle(GlassButtonStyle())
                }
                divider
                tokenRow(["No telemetry", "No cloud AI", "Local AI"])
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    private var filesSetupState: SetupState {
        if !fullDiskIndexingEnabled { return .optional }
        if indexing.isRunning { return .working }
        return indexing.hasCompleted ? .ready : .action
    }

    private var filesSetupSubtitle: String {
        if !fullDiskIndexingEnabled { return "Home folders only" }
        if indexing.isRunning { return indexing.percentText }
        return indexing.hasCompleted ? "Full disk index ready" : "Grant access and warm"
    }

    private var filesSetupAction: String {
        fullDiskIndexingEnabled && !indexing.hasCompleted ? "Warm" : "Open"
    }

    private var clipboardSetupState: SetupState {
        guard clipboardHistoryEnabled else { return .optional }
        return accessibilityTrusted ? .ready : .action
    }

    private var clipboardSetupSubtitle: String {
        guard clipboardHistoryEnabled else { return "Off until enabled" }
        return accessibilityTrusted ? "History and paste ready" : "Paste needs Accessibility"
    }

    private var aiSetupState: SetupState {
        guard localAIEnabled else { return .optional }
        if localAI.isChecking || localAI.isInstallingChatModel || localAI.isInstallingEmbeddingModel { return .working }
        return localAI.models.isEmpty ? .action : .ready
    }

    private var aiSetupSubtitle: String {
        guard localAIEnabled else { return "Local, opt-in only" }
        if localAI.isChecking { return "Checking Ollama" }
        if localAI.isInstallingChatModel || localAI.isInstallingEmbeddingModel { return "Installing \(localAI.installingModel)" }
        return localAI.models.isEmpty ? "Install or start Ollama" : localAI.status
    }

    private var indexMeter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(indexing.phase, systemImage: indexing.symbolName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(indexing.percentText)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(SettingsSkin.blue)
            }

            ProgressView(value: indexing.progress)
                .progressViewStyle(.linear)
                .tint(SettingsSkin.blue)

            Text(fullDiskIndexingEnabled ? indexing.status : "Home folders only.")
                .font(.caption)
                .foregroundStyle(SettingsSkin.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(SettingsSkin.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SettingsSkin.stroke, lineWidth: 1)
        }
    }

    private var aiStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: localAI.symbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SettingsSkin.blue)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(localAI.status)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(localAI.version.isEmpty ? "Ollama and MemPalace stay off search." : "Ollama \(localAI.version)")
                    .font(.caption)
                    .foregroundStyle(SettingsSkin.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(localAIEnabled ? "On" : "Off")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(localAIEnabled ? SettingsSkin.blue : SettingsSkin.muted)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(SettingsSkin.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SettingsSkin.stroke, lineWidth: 1)
        }
    }

    private func paneButton(_ item: SettingsPane) -> some View {
        Button {
            pane = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(pane == item ? .white : SettingsSkin.blue)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(pane == item ? AnyShapeStyle(SettingsSkin.activeGradient) : AnyShapeStyle(.white.opacity(0.07)))
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(10)
            .background(pane == item ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(item.shortcut, modifiers: .command)
    }

    private func setupCard(
        _ title: String,
        subtitle: String,
        symbol: String,
        state: SetupState,
        action: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(SettingsSkin.blue)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer()
                    statusBadge(state)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(SettingsSkin.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SettingsSkin.blue)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(SettingsSkin.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(SettingsSkin.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ state: SetupState) -> some View {
        Text(state.title)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(state.foreground)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(state.background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(SettingsSkin.stroke, lineWidth: 1)
            }
    }

    private func metricChip(_ title: String, _ target: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(SettingsSkin.muted)
            Text(target)
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(SettingsSkin.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(SettingsSkin.stroke, lineWidth: 1)
        }
    }

    private func controlRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer(minLength: 20)
            content()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }

    private func tokenRow(_ items: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func commandChip(_ command: String) -> some View {
        Text(command)
            .font(.system(.callout, design: .monospaced).weight(.bold))
            .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(SettingsSkin.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quicklinkField(_ title: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(SettingsSkin.muted)
                .textCase(.uppercase)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(monospaced ? .system(.callout, design: .monospaced).weight(.bold) : .callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var quicklinkLogoPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Logo")
                .font(.caption.weight(.bold))
                .foregroundStyle(SettingsSkin.muted)
                .textCase(.uppercase)
            HStack(spacing: 8) {
                quicklinkIconPreview(quicklinks.previewIcon, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Button("Choose", action: quicklinks.chooseIcon)
                        .buttonStyle(GlassButtonStyle())
                    Button("Clear", action: quicklinks.clearCustomIcon)
                        .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .frame(width: 118, alignment: .leading)
    }

    private func quicklinkIconPreview(_ icon: ResultIcon?, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
            if let image = QuicklinkIconRenderer.image(for: icon, size: size - 8) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size - 8, height: size - 8)
            } else {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SettingsSkin.blue)
            }
        }
        .frame(width: size, height: size)
    }

    private func snippetButton(_ item: SnippetRecord) -> some View {
        Button {
            snippets.select(item)
        } label: {
            HStack(spacing: 12) {
                Text(item.trigger)
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 86, alignment: .leading)
                Text(item.preview)
                    .font(.callout)
                    .foregroundStyle(SettingsSkin.muted)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            .background(
                snippets.selectedID == item.id ? .white.opacity(0.12) : .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(snippets.selectedID == item.id ? SettingsSkin.blue.opacity(0.45) : SettingsSkin.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func quicklinkButton(_ item: QuicklinkRecord) -> some View {
        Button {
            quicklinks.select(item)
        } label: {
            HStack(spacing: 12) {
                quicklinkIconPreview(item.resultIcon, size: 28)
                Text(item.keyword)
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, alignment: .leading)
                Text(item.name)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 92, alignment: .leading)
                    .lineLimit(1)
                Text(item.preview)
                    .font(.callout)
                    .foregroundStyle(SettingsSkin.muted)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            .background(
                quicklinks.selectedID == item.id ? .white.opacity(0.12) : .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(quicklinks.selectedID == item.id ? SettingsSkin.blue.opacity(0.45) : SettingsSkin.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func resetLauncherPosition() {
        LauncherPreferences.clearLauncherPosition()
    }

    private func refreshReadiness() {
        accessibilityTrusted = AXIsProcessTrusted()
        if !indexing.isRunning {
            indexing.update(enabled: fullDiskIndexingEnabled)
        }
        if localAIEnabled {
            localAI.refresh(baseURL: localAIBaseURL)
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case setup
    case launcher
    case search
    case files
    case ai
    case quicklinks
    case snippets
    case about
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .launcher: "Launcher"
        case .search: "Search"
        case .files: "Files"
        case .ai: "AI"
        case .quicklinks: "Quicklinks"
        case .snippets: "Snippets"
        case .about: "About"
        case .help: "Cheatsheet"
        }
    }

    var symbol: String {
        switch self {
        case .setup: "checklist"
        case .launcher: "command"
        case .search: "point.3.connected.trianglepath.dotted"
        case .files: "externaldrive"
        case .ai: "sparkle.magnifyingglass"
        case .quicklinks: "link"
        case .snippets: "text.quote"
        case .about: "info.circle"
        case .help: "keyboard"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .setup: "1"
        case .launcher: "2"
        case .search: "3"
        case .files: "4"
        case .ai: "5"
        case .quicklinks: "6"
        case .snippets: "7"
        case .about: "8"
        case .help: "9"
        }
    }
}

private enum SetupState {
    case ready
    case action
    case working
    case optional

    var title: String {
        switch self {
        case .ready: "Ready"
        case .action: "Action"
        case .working: "Working"
        case .optional: "Optional"
        }
    }

    var foreground: Color {
        switch self {
        case .ready, .working: SettingsSkin.blue
        case .action: .white
        case .optional: SettingsSkin.muted
        }
    }

    var background: Color {
        switch self {
        case .ready, .working: SettingsSkin.blue.opacity(0.18)
        case .action: .white.opacity(0.12)
        case .optional: .white.opacity(0.06)
        }
    }
}

private enum SettingsSkin {
    static let blue = Color(red: 0.28, green: 0.62, blue: 1.0)
    static let blueSoft = Color(red: 0.47, green: 0.74, blue: 1.0)
    static let blueDeep = Color(red: 0.08, green: 0.34, blue: 0.86)
    static let muted = Color.white.opacity(0.58)
    static let panel = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.14)
    static let offSwitch = LinearGradient(
        colors: [Color.white.opacity(0.16), Color.white.opacity(0.08)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let activeGradient = LinearGradient(
        colors: [blueSoft, blue, blueDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let logoGradient = LinearGradient(
        colors: [blueSoft, blue, blueDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static var background: some View {
        ZStack {
            Color(red: 0.055, green: 0.056, blue: 0.060)
            Circle()
                .fill(.white.opacity(0.035))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 210, y: -190)
            Circle()
                .fill(.black.opacity(0.16))
                .frame(width: 420, height: 420)
                .blur(radius: 96)
                .offset(x: -270, y: 240)
        }
        .ignoresSafeArea()
    }
}

private struct GlassSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? SettingsSkin.activeGradient : SettingsSkin.offSwitch)
                    .overlay {
                        Capsule()
                            .stroke(SettingsSkin.stroke, lineWidth: 1)
                    }
                Circle()
                    .fill(.white.opacity(0.94))
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .frame(width: 50, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.9))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                .white.opacity(configuration.isPressed ? 0.08 : 0.12),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(SettingsSkin.stroke, lineWidth: 1)
            }
    }
}

@MainActor
private final class IndexingProgressModel: NSObject, ObservableObject {
    @Published private(set) var phase = "Indexing off"
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Full disk search is off."
    @Published private(set) var isRunning = false
    @Published private(set) var hasCompleted = LauncherPreferences.fullDiskWarmupCompleted

    private var task: Task<Void, Never>?

    var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    var symbolName: String {
        if isRunning { return "arrow.triangle.2.circlepath" }
        return hasCompleted ? "checkmark.circle" : "pause.circle"
    }

    func update(enabled: Bool) {
        guard enabled else {
            task?.cancel()
            isRunning = false
            phase = "Indexing off"
            progress = 0
            status = "Full disk search is off."
            return
        }

        progress = hasCompleted ? 1 : 0
        phase = hasCompleted ? "Index ready" : "Indexing not started"
        status = hasCompleted
            ? "Ready. Search files with Space, open, find, in, or tags."
            : "Grant Full Disk Access, then verify the index."
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            isRunning = true
            phase = "Checking access"
            progress = 0.12
            status = "Checking Full Disk Access..."

            guard await hasLikelyFullDiskAccess() else {
                phase = "Indexing paused"
                progress = 0
                status = "Full Disk Access is not visible yet. Add vish, then run again."
                isRunning = false
                return
            }

            phase = "Indexing filenames"
            progress = 0.18
            status = "Indexing filenames..."
            let progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    let snapshot = await FileIndexStore.shared.currentProgress()
                    self?.apply(snapshot)
                }
            }
            let count = await FileIndexStore.shared.rebuild(includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled)
            progressTask.cancel()

            let semantic = await rebuildSemanticIndexIfNeeded()
            phase = "Index ready"
            progress = 1
            if semantic.phase == "Fast embedding model needed" {
                status = "Indexed \(count) files. Install \(LocalAIClient.recommendedEmbeddingModel) for semantic search."
            } else if semantic.totalCount > 0 {
                status = "Indexed \(count) files and \(semantic.totalCount) semantic vectors."
            } else {
                status = count > 0
                    ? "Indexed \(count) files and folders. Search with Space, open, find, in, or tags."
                    : "Ready. Search files with Space, open, find, in, or tags."
            }
            hasCompleted = true
            LauncherPreferences.fullDiskWarmupCompleted = true
            isRunning = false
        }
    }

    private func rebuildSemanticIndexIfNeeded() async -> SemanticVectorIndexProgress {
        guard LauncherPreferences.localAIEnabled else { return .idle }

        phase = "Indexing semantics"
        progress = 0.52
        status = "Building local semantic vectors..."
        let progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { break }
                let snapshot = await SemanticVectorIndexStore.shared.currentProgress()
                guard !Task.isCancelled else { break }
                self?.apply(snapshot)
            }
        }
        let semantic = await SemanticVectorIndexStore.shared.rebuild(includeFullDisk: LauncherPreferences.fullDiskIndexingEnabled)
        progressTask.cancel()
        apply(semantic)
        return semantic
    }

    private func apply(_ snapshot: FileIndexProgress) {
        guard !snapshot.isFinished else { return }

        phase = "Indexing filenames"
        let span = LauncherPreferences.localAIEnabled ? 0.34 : 0.74
        progress = min(LauncherPreferences.localAIEnabled ? 0.52 : 0.94, 0.18 + min(span, Double(snapshot.indexedCount) / 100_000.0 * span))
        let root = snapshot.rootPath.isEmpty ? "local folders" : URL(fileURLWithPath: snapshot.rootPath).lastPathComponent
        status = "Indexed \(snapshot.indexedCount) items from \(snapshot.scannedCount) scanned in \(root)."
    }

    private func apply(_ snapshot: SemanticVectorIndexProgress) {
        let done = snapshot.totalCount == 0
            ? 0
            : Double(snapshot.embeddedCount + snapshot.skippedCount) / Double(snapshot.totalCount)
        phase = snapshot.phase
        progress = snapshot.isFinished ? 1 : min(0.98, 0.54 + done * 0.42)
        if snapshot.phase == "Fast embedding model needed" {
            status = "Install \(LocalAIClient.recommendedEmbeddingModel) in AI settings, then Warm again."
        } else if snapshot.totalCount == 0 {
            status = "No semantic files found for vector indexing."
        } else {
            status = "Semantic vectors \(snapshot.embeddedCount + snapshot.skippedCount)/\(snapshot.totalCount) using \(snapshot.model)."
        }
    }
}

private func hasLikelyFullDiskAccess() async -> Bool {
    await Task.detached(priority: .utility) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let urls = [
            home.appendingPathComponent("Library/Messages", isDirectory: true),
            home.appendingPathComponent("Library/Mail", isDirectory: true),
            home.appendingPathComponent("Library/Safari", isDirectory: true)
        ]

        for url in urls {
            if (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) != nil {
                return true
            }
        }

        return false
    }.value
}
