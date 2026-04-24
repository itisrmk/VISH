# third-party sources

Records the exact HEAD SHA of every external reference repo we clone into `third-party/reference/`. Bump SHAs deliberately — re-clone, verify, update this file in the same commit.

`third-party/reference/` is git-ignored. SHAs here are the authoritative record.

| Repo | Upstream | Purpose | Cloned SHA | Cloned date |
|---|---|---|---|---|
| loungy-reference | [MatthiasGrandl/Loungy](https://github.com/MatthiasGrandl/Loungy) | UI shell / patterns to port into vish-macos + vish-ui | `303e7d2c46db13c49f8c7ca30762e5ee0ac582d2` | 2026-04-23 |
| tauri-nspanel-reference | [ahkohd/tauri-nspanel](https://github.com/ahkohd/tauri-nspanel) | ~40-line NSPanel `.nonactivating` objc2 wrapper | `a3122e894383aa068ec5365a42994e3ac94ba1b6` | 2026-04-23 |
| imessage-tools-reference | [ReagentX/imessage-exporter](https://github.com/ReagentX/imessage-exporter) | `attributedBody` NSKeyedArchiver decoder (crate: `imessage-database`) | `b60ecc98d07eb31a68d948415b98c7fff23195a9` | 2026-04-23 |
| pop-launcher-reference | [pop-os/launcher](https://github.com/pop-os/launcher) | JSON-line plugin-as-child-process protocol | `5b868510716673b31a650488401489898352e2d9` | 2026-04-23 |
| zed-reference | [zed-industries/zed](https://github.com/zed-industries/zed) | GPUI examples + `picker` crate + ForegroundExecutor pattern (`--filter=blob:none`) | `385f6134bbadf9820f30dfd5944c01359e5ce159` | 2026-04-23 |
| sparkle-updater-reference | TBD — Phase 0 found no repo at `ahkohd/tauri-plugin-sparkle-updater` (404) | Sparkle 2 objc2 bridge pattern | not cloned | pending |

## Followups

- **sparkle-updater-reference:** the URL cited in the original plan (`ahkohd/tauri-plugin-sparkle-updater`) returns 404. Not blocking — only needed in Phase 1 Week 4 for the objc2 Sparkle wrapper. Candidates discovered in a follow-up search:
  - **[hankbao/sparkle-updater](https://github.com/hankbao/sparkle-updater)** — native Rust crate (not Tauri-coupled), targets macOS + Windows, bridges Sparkle.framework. Main surface: `Updater::new()` → `updater.check_for_updates()`. **Best fit** for vish (we're not a Tauri app). Clone before Week 4 and record the SHA here.
  - **[tauri-plugin-sparkle-updater on crates.io](https://crates.io/crates/tauri-plugin-sparkle-updater) v0.2.2** — Tauri-specific; uses the exact objc2 version pins we locked in Phase 0 (objc2 0.6, objc2-app-kit 0.3, objc2-foundation 0.3). Useful as a reference for the objc2 bridging pattern even though we don't need the Tauri wrapper itself.
  - **[sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle)** — the Sparkle framework itself (Objective-C). The ultimate fallback: vendor the framework at build time and write our own ~50-line objc2 bridge. Reserve for the case where both above options go stale.
- **git-lfs install:** `.gitattributes` declares LFS filters for `third-party/mlx_sidecar/**` and `resources/icons/*.{icns,png}`, but `git-lfs` is not installed on the dev machine. No matching files exist yet, so the filter is a silent no-op. **Before committing the first `.icns`/`.png` or any file under `third-party/mlx_sidecar/`, run `brew install git-lfs && git lfs install` or those files will be stored as regular git blobs.**
