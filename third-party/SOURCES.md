# third-party sources

Records the exact HEAD SHA of every external reference repo we clone into `third-party/reference/`. Bump SHAs deliberately — re-clone, verify, update this file in the same commit.

`third-party/reference/` is git-ignored. SHAs here are the authoritative record.

| Repo | Upstream | Purpose | Cloned SHA | Cloned date |
|---|---|---|---|---|
| loungy-reference | [MatthiasGrandl/Loungy](https://github.com/MatthiasGrandl/Loungy) | UI shell / patterns to port into vish-macos + vish-ui | TBD | TBD |
| tauri-nspanel-reference | [ahkohd/tauri-nspanel](https://github.com/ahkohd/tauri-nspanel) | ~40-line NSPanel `.nonactivating` objc2 wrapper | TBD | TBD |
| imessage-tools-reference | [ReagentX/imessage-exporter](https://github.com/ReagentX/imessage-exporter) | `attributedBody` NSKeyedArchiver decoder | TBD | TBD |
| sparkle-updater-reference | [ahkohd/tauri-plugin-sparkle-updater](https://github.com/ahkohd/tauri-plugin-sparkle-updater) | Sparkle 2 objc2 bridge pattern | TBD | TBD |
| zed-reference | [zed-industries/zed](https://github.com/zed-industries/zed) | GPUI examples + picker crate + ForegroundExecutor pattern | TBD | TBD |
| pop-launcher-reference | [pop-os/launcher](https://github.com/pop-os/launcher) | JSON-line plugin-as-child-process protocol | TBD | TBD |
