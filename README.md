# VISH

VISH is a native macOS launcher focused on speed, local-first workflows, and low-friction power-user actions.

Press `Option-Space`, type, press `Return`. VISH launches apps, opens files, runs system actions, evaluates calculator expressions, opens URLs, searches the web, expands snippets, searches clipboard history, and can use local AI through Ollama when enabled.

## Download

Download the latest DMG from GitHub Releases:

https://github.com/itisrmk/VISH/releases

Open the DMG, drag `vish.app` to Applications, then launch it. macOS may show a security warning for early builds because the current alpha DMG is not notarized yet.

## Highlights

- Native macOS app built with Swift, AppKit, and SwiftUI only for Settings/onboarding.
- Fast launcher panel with a prewarmed `NSPanel`; no web views, Electron, or background daemon.
- App search, system actions, calculator, URL detection, Quicklinks, web search, file search, snippets, Clipboard History v2, previews, and universal actions.
- Local-only AI through Ollama, enabled explicitly by the user.
- Semantic file finder for explicit `ai find ...` queries using VISH file indexing plus local embeddings when configured.
- Privacy-first design: no telemetry, no cloud AI, no default background disk summarization.
- Settings includes a Privacy dashboard for permissions, local data, clipboard retention, and local AI state.

## Core Commands

| Command | Action |
|---|---|
| `Option-Space` | Open or hide launcher |
| `Esc` | Close launcher |
| `Return` | Run selected result |
| `Command-1...9` | Run a numbered result |
| `Tab` | Lock selected result and show actions |
| `Command-Y` | Quick Look / preview |
| `Command-B` | Buffer selected file |
| `' file` or `space file` | File search |
| `open file`, `find file`, `in text`, `tags name` | File-focused search |
| `gh react`, `yt swiftui`, `maps coffee` | Quicklinks |
| `;trigger` | Snippets |
| `clip` / `clipboard` | Clipboard history |
| `ai question` / `? question` | Ask local AI |
| `ai find paper from last month` | Semantic file finder |

## Optional Permissions

VISH works without granting everything up front.

- Accessibility is only needed for paste automation from snippets and clipboard history.
- Full Disk Access is only needed when you enable full-computer file indexing; VISH can still exclude folders like Downloads, Documents, or custom paths.
- Local AI requires a local Ollama server and an installed model.

Settings includes a Setup pane that shows readiness for Launcher, Files, Clipboard, AI, and Privacy.

## Performance Targets

VISH treats performance as a release gate.

| Metric | Target |
|---|---:|
| Cold launch | <=120 ms |
| Hotkey to first frame | <=16 ms p95 |
| Keystroke to rendered result | <=16 ms p95 |
| Spotlight query | <=30 ms p95 |
| Idle RSS | <=80 MB |
| Idle CPU | 0.0% |
| Warm AI first token | <=1500 ms |

Latest local Release smoke benchmark on April 27, 2026:

- Launch to process: `107 ms`
- Idle RSS: `75.3 MB`
- Idle CPU: `0.0%`

Frame-level p95 numbers still need a full Instruments signpost pass before a production 1.0 claim.

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode 16 or newer
- XcodeGen

```sh
xcodegen generate
xcodebuild -scheme vish -configuration Debug -destination 'platform=macOS,arch=arm64'
```

Create a local DMG:

```sh
scripts/release.sh 0.1.0
```

Release packaging also generates a signed Sparkle `appcast.xml` when the local ignored Sparkle signing key exists at `resources/provisioning/sparkle_ed25519_private_key.txt`. Notarization runs only when `AC_PROFILE` is configured for `notarytool`.

## Status

This is an alpha build. The core launcher is usable, but release hardening is still in progress:

- Developer ID notarization is not configured yet.
- Sparkle is wired to a signed appcast; production hosting/signing automation still needs a final pass.
- Full VoiceOver verification is pending.
- Final Instruments traces for hotkey, keystroke, and Spotlight p95 are pending.

## License

MIT. See [LICENSE](LICENSE).
