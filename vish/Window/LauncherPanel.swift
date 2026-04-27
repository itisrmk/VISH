import AppKit
import QuartzCore

private final class LauncherBackgroundView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class LauncherPanel: NSPanel {
    private enum Metrics {
        static let inputInset: CGFloat = 24
        static let resultsInset: CGFloat = 10
        static let screenMargin: CGFloat = 12
    }

    private enum ContentMode {
        case results
        case actions
        case ai
        case detail
    }

    private let inputField = InputField()
    private let aiResponseView = AIInlineAnswerView()
    private let actionsView = InlineActionsView()
    private let previewView = ResultPreviewView()
    private let resultsView = ResultsTableView()
    private weak var materialView: NSVisualEffectView?
    private var contentMode: ContentMode = .results
    private var style = LauncherVisualStyle.current
    private var isExpanded = false
    private var isHiding = false
    private var ignoresMovePersistence = false
    var onQueryChange: ((String) -> Void)?
    var onActionQueryChange: ((String) -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onActivateSelection: (() -> Void)?
    var onActivateAction: (() -> Void)?
    var onShowActions: (() -> Void)?
    var onSelectionChange: ((SearchResult?) -> Void)?
    var onQuickLookSelection: (() -> Void)?
    var onShowDetails: (() -> Void)?
    var onToggleBuffer: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        let style = LauncherVisualStyle.current
        self.style = style
        let frame = NSRect(
            origin: NSPoint(x: -10_000, y: -10_000),
            size: NSSize(width: style.width, height: style.collapsedHeight)
        )
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        alphaValue = 0
        animationBehavior = .none
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = true
        isOpaque = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating

        contentView = makeContentView(frame: NSRect(origin: .zero, size: frame.size))
        observeMoves()
        wireInput()
        resultsView.onSelectionChange = { [weak self] result in
            self?.onSelectionChange?(result)
        }
        setAccessibilityLabel("vish launcher")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if firstResponder === inputField || firstResponder === inputField.currentEditor() {
            return
        }

        focusInput(select: false)
        if inputField.handleKeyCommand(event) {
            return
        }

        guard let editor = inputField.currentEditor() else {
            return
        }
        editor.keyDown(with: event)
    }

    func prewarm() {
        orderOut(nil)
    }

    func show() {
        isHiding = false
        applyStyle()
        isExpanded = false
        contentMode = .results
        aiResponseView.reset()
        aiResponseView.alphaValue = 0
        aiResponseView.isHidden = true
        actionsView.alphaValue = 0
        actionsView.isHidden = true
        previewView.alphaValue = 0
        previewView.isHidden = true
        resultsView.alphaValue = 0
        resultsView.isHidden = true
        setPanelFrame(Self.launchFrame(width: style.width, height: style.collapsedHeight), display: false)
        alphaValue = 0
        orderFrontRegardless()
        focusInput(select: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.016
            animator().alphaValue = 1
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isVisible else { return }
            self.contentView?.layoutSubtreeIfNeeded()
            self.contentView?.displayIfNeeded()
            self.displayIfNeeded()
            PerformanceProbe.endHotkeyToFrame()
            self.focusInput(select: true)
        }
    }

    func hide(reset: Bool = true) {
        guard isVisible, !isHiding else { return }

        isHiding = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.016
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                self?.isHiding = false
                if reset {
                    self?.reset()
                }
            }
        }
    }

    private func focusInput(select: Bool) {
        makeKey()
        makeFirstResponder(inputField)
        if select {
            inputField.selectText(nil)
        }
    }

    func setResults(_ results: [SearchResult]) {
        guard contentMode == .results else { return }
        resultsView.reload(results)
    }

    func setPreview(_ preview: ResultPreview?, result: SearchResult?) {
        guard contentMode == .results else { return }
        guard let preview else {
            previewView.reset()
            previewView.alphaValue = 0
            previewView.isHidden = true
            layoutContent(height: isExpanded ? style.expandedHeight : style.collapsedHeight)
            return
        }
        previewView.configure(preview, result: result)
        previewView.isHidden = !isExpanded
        previewView.alphaValue = isExpanded ? 1 : 0
        layoutContent(height: isExpanded ? style.expandedHeight : style.collapsedHeight)
    }

    func moveSelection(by delta: Int) {
        if contentMode == .actions {
            actionsView.moveSelection(by: delta)
        } else {
            resultsView.moveSelection(by: delta)
        }
    }

    func activateSelection() -> SearchResult? {
        resultsView.primaryResult
    }

    func selectedResult() -> SearchResult? {
        resultsView.primaryResult
    }

    var isShowingAIResponse: Bool {
        contentMode == .ai
    }

    var isShowingActions: Bool {
        contentMode == .actions
    }

    var query: String {
        inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeContentView(frame: NSRect) -> NSView {
        let view = LauncherBackgroundView(frame: frame)
        view.autoresizingMask = [.width, .height]
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.borderWidth = 1
        view.layer?.masksToBounds = true
        materialView = view
        applyStyle()

        inputField.frame = NSRect(
            x: Metrics.inputInset,
            y: floor((frame.height - style.inputHeight) / 2),
            width: frame.width - Metrics.inputInset * 2,
            height: style.inputHeight
        )
        inputField.autoresizingMask = [.width]

        resultsView.frame = NSRect(
            x: Metrics.resultsInset,
            y: Metrics.resultsInset,
            width: frame.width - Metrics.resultsInset * 2,
            height: 0
        )
        resultsView.alphaValue = 0
        resultsView.autoresizingMask = [.width]
        resultsView.isHidden = true

        aiResponseView.frame = resultsView.frame
        aiResponseView.alphaValue = 0
        aiResponseView.autoresizingMask = [.width]
        aiResponseView.isHidden = true

        previewView.frame = resultsView.frame
        previewView.alphaValue = 0
        previewView.autoresizingMask = [.width]
        previewView.isHidden = true

        actionsView.frame = resultsView.frame
        actionsView.alphaValue = 0
        actionsView.autoresizingMask = [.width]
        actionsView.isHidden = true

        view.addSubview(aiResponseView)
        view.addSubview(actionsView)
        view.addSubview(previewView)
        view.addSubview(resultsView)
        view.addSubview(inputField)
        return view
    }

    private func applyCornerStyle() {
        materialView?.layer?.cornerCurve = .continuous
        materialView?.layer?.cornerRadius = LauncherPreferences.roundedCorners
            ? min(max(style.collapsedHeight * 0.21, 12), 18)
            : 0
    }

    private func applyStyle() {
        style = LauncherVisualStyle.current
        appearance = style.windowAppearance
        materialView?.appearance = style.windowAppearance
        materialView?.material = style.material
        materialView?.layer?.backgroundColor = style.backgroundColor.cgColor
        materialView?.layer?.borderColor = style.borderColor.cgColor
        inputField.applyStyle(style)
        resultsView.applyStyle(style)
        actionsView.applyStyle(style)
        previewView.applyStyle(style)
        aiResponseView.applyStyle(style)
        applyCornerStyle()
        layoutContent(height: isExpanded ? style.expandedHeight : style.collapsedHeight)
    }

    func showResultsMode() {
        contentMode = .results
        inputField.setPlaceholder("")
        aiResponseView.isHidden = true
        aiResponseView.alphaValue = 0
        aiResponseView.reset()
        actionsView.isHidden = true
        actionsView.alphaValue = 0
        resultsView.isHidden = !isExpanded
        resultsView.alphaValue = isExpanded ? 1 : 0
        previewView.isHidden = previewView.alphaValue == 0 || !isExpanded
    }

    func showActionMode(result: SearchResult, actions: [InlineActionItem]) {
        contentMode = .actions
        inputField.setText("")
        inputField.setPlaceholder("Ask AI or filter actions")
        actionsView.configure(result: result, actions: actions)
        setExpanded(true, animate: true)
        resultsView.isHidden = true
        resultsView.alphaValue = 0
        aiResponseView.isHidden = true
        aiResponseView.alphaValue = 0
        previewView.isHidden = true
        previewView.alphaValue = 0
        actionsView.isHidden = false
        actionsView.alphaValue = 1
        focusInput(select: false)
    }

    func setInlineActions(_ actions: [InlineActionItem]) {
        guard contentMode == .actions else { return }
        actionsView.reload(actions)
    }

    func activateInlineAction() -> InlineActionItem? {
        actionsView.selectedAction
    }

    func beginAIResponse(title: String = "Local AI", status: String = "Thinking") {
        contentMode = .ai
        inputField.setPlaceholder("")
        aiResponseView.begin(title: title, status: status)
        setExpanded(true, animate: true)
        resultsView.isHidden = true
        resultsView.alphaValue = 0
        actionsView.isHidden = true
        actionsView.alphaValue = 0
        previewView.isHidden = true
        previewView.alphaValue = 0
        aiResponseView.isHidden = false
        aiResponseView.alphaValue = 1
        focusInput(select: false)
    }

    func appendAIResponse(_ chunk: String) {
        guard contentMode == .ai else { return }
        aiResponseView.append(chunk)
    }

    func finishAIResponse(status: String) {
        guard contentMode == .ai else { return }
        aiResponseView.finish(status)
    }

    func showAIMessage(_ message: String, status: String) {
        contentMode = .ai
        inputField.setPlaceholder("")
        setExpanded(true, animate: true)
        resultsView.isHidden = true
        resultsView.alphaValue = 0
        actionsView.isHidden = true
        actionsView.alphaValue = 0
        previewView.isHidden = true
        previewView.alphaValue = 0
        aiResponseView.isHidden = false
        aiResponseView.alphaValue = 1
        aiResponseView.showMessage(message, status: status)
        focusInput(select: false)
    }

    func showDetail(_ preview: ResultPreview, result: SearchResult) {
        contentMode = .detail
        inputField.setPlaceholder("")
        previewView.configure(preview, result: result)
        setExpanded(true, animate: true)
        resultsView.isHidden = true
        resultsView.alphaValue = 0
        actionsView.isHidden = true
        actionsView.alphaValue = 0
        aiResponseView.isHidden = true
        aiResponseView.alphaValue = 0
        previewView.isHidden = false
        previewView.alphaValue = 1
        focusInput(select: false)
    }

    private func wireInput() {
        inputField.onTextChange = { [weak self] query in
            guard let self else { return }
            let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            self.setExpanded(self.contentMode == .actions || hasQuery, animate: true)
            if self.contentMode == .actions {
                self.onActionQueryChange?(query)
            } else {
                self.onQueryChange?(query)
            }
        }
        inputField.onMoveSelection = { [weak self] delta in
            guard let self else { return }
            if self.contentMode == .actions {
                self.actionsView.moveSelection(by: delta)
            } else {
                self.onMoveSelection?(delta)
            }
        }
        inputField.onActivateSelection = { [weak self] in
            guard let self else { return }
            if self.contentMode == .actions {
                self.onActivateAction?()
            } else {
                self.onActivateSelection?()
            }
        }
        inputField.onRevealSelection = { [weak self] in
            guard let result = self?.activateSelection() else { return }
            ResultActionExecutor.reveal(result.action)
            self?.hide()
        }
        inputField.onSearchWeb = { [weak self] in
            let query = self?.inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !query.isEmpty else { return }
            ResultActionExecutor.searchWeb(query)
            self?.hide()
        }
        inputField.onShowActions = { [weak self] in
            self?.onShowActions?()
        }
        inputField.onQuickLookSelection = { [weak self] in
            self?.onQuickLookSelection?()
        }
        inputField.onShowDetails = { [weak self] in
            self?.onShowDetails?()
        }
        inputField.onToggleBuffer = { [weak self] in
            self?.onToggleBuffer?()
        }
        inputField.onOpenSettings = { [weak self] in
            self?.onOpenSettings?()
        }
        inputField.onCancel = { [weak self] in
            self?.onCancel?()
        }
    }

    private func observeMoves() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard isVisible, !ignoresMovePersistence else { return }
        LauncherPreferences.launcherTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }

    private func reset() {
        inputField.setText("")
        contentMode = .results
        inputField.setPlaceholder("")
        aiResponseView.reset()
        aiResponseView.alphaValue = 0
        aiResponseView.isHidden = true
        actionsView.alphaValue = 0
        actionsView.isHidden = true
        previewView.reset()
        previewView.alphaValue = 0
        previewView.isHidden = true
        resultsView.reload([])
        setExpanded(false, animate: false)
    }

    private func setExpanded(_ expanded: Bool, animate: Bool) {
        guard expanded != isExpanded else { return }

        isExpanded = expanded
        let targetHeight = expanded ? style.expandedHeight : style.collapsedHeight
        let targetFrame = frameKeepingTop(height: targetHeight)

        if expanded {
            resultsView.isHidden = contentMode != .results
            actionsView.isHidden = contentMode != .actions
            aiResponseView.isHidden = contentMode != .ai
            previewView.isHidden = contentMode != .detail && (contentMode != .results || previewView.alphaValue == 0)
        }

        let updates = {
            self.setPanelFrame(targetFrame, display: true)
            self.layoutContent(height: targetHeight)
            self.resultsView.alphaValue = expanded && self.contentMode == .results ? 1 : 0
            self.actionsView.alphaValue = expanded && self.contentMode == .actions ? 1 : 0
            self.aiResponseView.alphaValue = expanded && self.contentMode == .ai ? 1 : 0
            self.previewView.alphaValue = expanded && (self.contentMode == .detail || (self.contentMode == .results && self.previewView.alphaValue > 0)) ? 1 : 0
        }

        guard animate, isVisible else {
            updates()
            resultsView.isHidden = !(expanded && contentMode == .results)
            actionsView.isHidden = !(expanded && contentMode == .actions)
            aiResponseView.isHidden = !(expanded && contentMode == .ai)
            previewView.isHidden = !(expanded && (contentMode == .detail || (contentMode == .results && previewView.alphaValue > 0)))
            return
        }

        ignoresMovePersistence = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
            self.layoutContent(height: targetHeight)
            self.resultsView.animator().alphaValue = expanded && self.contentMode == .results ? 1 : 0
            self.actionsView.animator().alphaValue = expanded && self.contentMode == .actions ? 1 : 0
            self.aiResponseView.animator().alphaValue = expanded && self.contentMode == .ai ? 1 : 0
            self.previewView.animator().alphaValue = expanded && (self.contentMode == .detail || (self.contentMode == .results && self.previewView.alphaValue > 0)) ? 1 : 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.ignoresMovePersistence = false
                guard let self else { return }
                self.resultsView.isHidden = !(self.isExpanded && self.contentMode == .results)
                self.actionsView.isHidden = !(self.isExpanded && self.contentMode == .actions)
                self.aiResponseView.isHidden = !(self.isExpanded && self.contentMode == .ai)
                self.previewView.isHidden = !(self.isExpanded && (self.contentMode == .detail || (self.contentMode == .results && self.previewView.alphaValue > 0)))
            }
        }
    }

    private func frameKeepingTop(height: CGFloat) -> NSRect {
        if isVisible {
            return Self.clampedFrame(
                topLeft: CGPoint(x: frame.minX, y: frame.maxY),
                width: style.width,
                height: height
            )
        }

        return Self.launchFrame(width: style.width, height: height)
    }

    private func layoutContent(height: CGFloat) {
        let width = contentView?.bounds.width ?? style.width
        inputField.frame = NSRect(
            x: Metrics.inputInset,
            y: height - style.inputTop - style.inputHeight,
            width: width - Metrics.inputInset * 2,
            height: style.inputHeight
        )
        let contentFrame = NSRect(
            x: Metrics.resultsInset,
            y: Metrics.resultsInset,
            width: width - Metrics.resultsInset * 2,
            height: max(0, height - style.collapsedHeight - Metrics.resultsInset)
        )
        if contentMode == .results && (!previewView.isHidden || previewView.alphaValue > 0) {
            let gap: CGFloat = 8
            let previewWidth = min(320, max(280, contentFrame.width * 0.40))
            resultsView.frame = NSRect(
                x: contentFrame.minX,
                y: contentFrame.minY,
                width: max(220, contentFrame.width - previewWidth - gap),
                height: contentFrame.height
            )
            previewView.frame = NSRect(
                x: resultsView.frame.maxX + gap,
                y: contentFrame.minY,
                width: previewWidth,
                height: contentFrame.height
            )
        } else {
            resultsView.frame = contentFrame
            previewView.frame = contentFrame
        }
        aiResponseView.frame = resultsView.frame
        actionsView.frame = resultsView.frame
        if contentMode == .detail {
            previewView.frame = contentFrame
        }
    }

    private func setPanelFrame(_ targetFrame: NSRect, display: Bool) {
        ignoresMovePersistence = true
        setFrame(targetFrame, display: display)
        ignoresMovePersistence = false
    }

    private static func launchFrame(width: CGFloat, height: CGFloat) -> NSRect {
        if let topLeft = LauncherPreferences.launcherTopLeft {
            return clampedFrame(topLeft: topLeft, width: width, height: height)
        }

        return centeredFrame(width: width, height: height)
    }

    private static func clampedFrame(topLeft: CGPoint, width: CGFloat, height: CGFloat) -> NSRect {
        let visibleFrame = visibleFrame(containing: topLeft)
        let minX = visibleFrame.minX + Metrics.screenMargin
        let maxX = visibleFrame.maxX - width - Metrics.screenMargin
        let minTop = visibleFrame.minY + height + Metrics.screenMargin
        let maxTop = visibleFrame.maxY - Metrics.screenMargin
        let x = minX <= maxX ? clamp(topLeft.x, minX, maxX) : visibleFrame.midX - width / 2
        let top = minTop <= maxTop ? clamp(topLeft.y, minTop, maxTop) : visibleFrame.maxY

        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    private static func centeredFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = min(visibleFrame.maxY - 96, visibleFrame.midY + 240)
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: top - height,
            width: width,
            height: height
        )
    }

    private static func visibleFrame(containing point: CGPoint) -> NSRect {
        let nsPoint = NSPoint(x: point.x, y: point.y)
        let screen = NSScreen.screens.first { NSMouseInRect(nsPoint, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static func clamp(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}

@MainActor
struct LauncherVisualStyle {
    let width: CGFloat
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    let inputHeight: CGFloat
    let inputTop: CGFloat
    let rowHeight: CGFloat
    let inputFontSize: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let iconSize: CGFloat
    let material: NSVisualEffectView.Material
    let windowAppearance: NSAppearance?
    let backgroundColor: NSColor
    let borderColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let tertiaryTextColor: NSColor

    static var current: LauncherVisualStyle {
        let textSize = LauncherPreferences.textSize
        let appearance = LauncherPreferences.appearance
        let scale = CGFloat(LauncherPreferences.launcherScale)
        let systemLight = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let isLight = appearance == .light || (appearance == .system && systemLight)
        let inputFontSize: CGFloat = scaled(textSize == .large ? 23 : 21, by: scale, min: 19, max: 27)
        let titleFontSize: CGFloat = scaled(textSize == .large ? 15.5 : 14.5, by: scale, min: 13, max: 18)
        let subtitleFontSize: CGFloat = scaled(textSize == .large ? 12.5 : 11.5, by: scale, min: 10.5, max: 14.5)
        let windowAppearance: NSAppearance?
        switch appearance {
        case .system:
            windowAppearance = nil
        case .dark:
            windowAppearance = NSAppearance(named: .darkAqua)
        case .light:
            windowAppearance = NSAppearance(named: .aqua)
        }

        return LauncherVisualStyle(
            width: scaled(704, by: scale, min: 600, max: 860),
            collapsedHeight: scaled(68, by: scale, min: 60, max: 82),
            expandedHeight: scaled(392, by: scale, min: 340, max: 470),
            inputHeight: scaled(46, by: scale, min: 42, max: 54),
            inputTop: scaled(11, by: scale, min: 9, max: 14),
            rowHeight: scaled(48, by: scale, min: 44, max: 56),
            inputFontSize: inputFontSize,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            iconSize: scaled(34, by: scale, min: 30, max: 42),
            material: isLight ? .popover : .underWindowBackground,
            windowAppearance: windowAppearance,
            backgroundColor: isLight ? NSColor.white.withAlphaComponent(0.44) : NSColor.black.withAlphaComponent(0.22),
            borderColor: isLight ? NSColor.black.withAlphaComponent(0.12) : NSColor.white.withAlphaComponent(0.16),
            primaryTextColor: isLight ? NSColor.black.withAlphaComponent(0.88) : NSColor.white.withAlphaComponent(0.96),
            secondaryTextColor: isLight ? NSColor.black.withAlphaComponent(0.54) : NSColor.white.withAlphaComponent(0.50),
            tertiaryTextColor: isLight ? NSColor.black.withAlphaComponent(0.38) : NSColor.white.withAlphaComponent(0.38)
        )
    }

    private static func scaled(_ value: CGFloat, by scale: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        min(max(value * scale, minValue), maxValue)
    }
}
