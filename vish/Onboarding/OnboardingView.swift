import AppKit
import ApplicationServices
import KeyboardShortcuts
import SwiftUI

struct OnboardingView: View {
    @AppStorage(LauncherPreferences.clipboardHistoryEnabledKey) private var clipboardHistoryEnabled = false
    @AppStorage(LauncherPreferences.fullDiskIndexingEnabledKey) private var fullDiskIndexingEnabled = false
    @AppStorage(LauncherPreferences.webSearchProviderKey) private var webSearchProvider = WebSearchProvider.google.rawValue
    @State private var step = OnboardingStep.welcome
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            OnboardingSkin.background
            VStack(spacing: 18) {
                header
                content
                footer
            }
            .padding(22)
        }
        .frame(width: 620, height: 460)
        .tint(OnboardingSkin.blue)
        .toggleStyle(OnboardingSwitchStyle())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(OnboardingSkin.activeGradient)
                .frame(width: 34, height: 34)
                .overlay {
                    Text("V")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            Text("vish setup")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases) { item in
                    Circle()
                        .fill(item.rawValue <= step.rawValue ? OnboardingSkin.blue : .white.opacity(0.16))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            card {
                VStack(alignment: .leading, spacing: 18) {
                    title("Fast launcher. Local by default.")
                    HStack(spacing: 12) {
                        pill("Apps")
                        pill("Files")
                        pill("AI")
                        pill("Snippets")
                    }
                    hotkeyRow
                    HStack(spacing: 10) {
                        shortcut("⌥ Space", "Open")
                        shortcut("Esc", "Close")
                        shortcut("↵", "Run")
                        shortcut("⌘1...9", "Pick")
                    }
                }
            }
        case .permissions:
            card {
                VStack(alignment: .leading, spacing: 14) {
                    title("Permissions")
                    permissionRow(
                        title: "Accessibility",
                        subtitle: accessibilityTrusted ? "Ready for paste actions" : "Needed for clipboard/snippet auto-paste",
                        status: accessibilityTrusted ? "Ready" : "Open",
                        symbol: "hand.tap",
                        action: openAccessibilitySettings
                    )
                    divider
                    permissionRow(
                        title: "Full Disk Access",
                        subtitle: "Optional for full-computer file search",
                        status: "Open",
                        symbol: "externaldrive",
                        action: openFullDiskAccessSettings
                    )
                }
            }
        case .features:
            card {
                VStack(alignment: .leading, spacing: 14) {
                    title("Choose what turns on")
                    controlRow("Clipboard") {
                        Toggle("Clipboard", isOn: $clipboardHistoryEnabled)
                            .labelsHidden()
                    }
                    divider
                    controlRow("Full disk files") {
                        Toggle("Full disk files", isOn: $fullDiskIndexingEnabled)
                            .labelsHidden()
                    }
                    divider
                    controlRow("Web") {
                        Picker("Web", selection: $webSearchProvider) {
                            ForEach(WebSearchProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
            }
        case .ready:
            card {
                VStack(alignment: .leading, spacing: 18) {
                    title("Ready.")
                    HStack(spacing: 10) {
                        shortcut("⌥ Space", "Open")
                        shortcut("Tab", "Actions")
                        shortcut("⌘Y", "Preview")
                        shortcut("⌘B", "Buffer")
                    }
                    VStack(spacing: 10) {
                        readyRow("Setup lives in Settings", "Use it when you want files, clipboard, AI, or snippets.")
                        readyRow("Speed stays protected", "Optional features are trigger-based and measured separately.")
                    }
                }
            }
        }
    }

    private var hotkeyRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "command")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(OnboardingSkin.blue)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Launcher hotkey")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            KeyboardShortcuts.Recorder("Toggle launcher", name: .toggleLauncher)
                .frame(width: 220, alignment: .trailing)
        }
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Button("Skip") {
                onFinish()
            }
            .buttonStyle(OnboardingButtonStyle())

            Spacer()

            if step != .welcome {
                Button("Back") {
                    step = step.previous
                    accessibilityTrusted = AXIsProcessTrusted()
                }
                .buttonStyle(OnboardingButtonStyle())
            }

            Button(step == .ready ? "Finish" : "Continue") {
                if step == .ready {
                    onFinish()
                } else {
                    step = step.next
                    accessibilityTrusted = AXIsProcessTrusted()
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(OnboardingSkin.panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(OnboardingSkin.stroke, lineWidth: 1)
        }
    }

    private func title(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func pill(_ value: String) -> some View {
        Text(value)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(keys)
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(OnboardingSkin.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func readyRow(_ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(OnboardingSkin.blue)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(OnboardingSkin.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func permissionRow(title: String, subtitle: String, status: String, symbol: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(OnboardingSkin.blue)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(OnboardingSkin.muted)
            }
            Spacer()
            Button(status, action: action)
                .buttonStyle(OnboardingButtonStyle())
        }
    }

    private func controlRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            content()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }

    private func openAccessibilitySettings() {
        accessibilityTrusted = AXIsProcessTrusted()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case features
    case ready

    var id: Int { rawValue }

    var next: Self {
        Self(rawValue: min(rawValue + 1, Self.allCases.count - 1)) ?? .features
    }

    var previous: Self {
        Self(rawValue: max(rawValue - 1, 0)) ?? .welcome
    }
}

private enum OnboardingSkin {
    static let blue = Color(red: 0.28, green: 0.62, blue: 1.0)
    static let blueSoft = Color(red: 0.47, green: 0.74, blue: 1.0)
    static let blueDeep = Color(red: 0.08, green: 0.34, blue: 0.86)
    static let muted = Color.white.opacity(0.58)
    static let panel = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.14)
    static let activeGradient = LinearGradient(
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
                .blur(radius: 82)
                .offset(x: 210, y: -190)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(OnboardingSkin.activeGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct OnboardingSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(OnboardingSkin.activeGradient) : AnyShapeStyle(.white.opacity(0.12)))
                    .overlay {
                        Capsule()
                            .stroke(OnboardingSkin.stroke, lineWidth: 1)
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
    }
}
