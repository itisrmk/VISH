# S2 + S4 combined spike — results

**Status: GREEN on first attempt.** `cargo check` and `cargo clippy --all-targets -- -D warnings` both clean (0 warnings, 0 errors). Total 1st build: ~1m 31s (629 resolved crates, includes two copies of the Zed monorepo — see "Surprise #1" below).

## Pinned SHAs / versions that compile

| Dep | Value | Source |
|---|---|---|
| `gpui` | git `f7d46cf7d02c88d3d71ec495a31d7f19bd5eb96b` (zed-industries/zed) | Extracted from gpui-component's own `Cargo.lock` on main — guaranteed-compatible point |
| `gpui-component` | git `808df4069295ef4e0b3b01445671c3c7057377cd` (longbridge/gpui-component) | main HEAD at time of spike (2026-04-23) |
| `objc2` | `0.6` (resolved `0.6.4`) | crates.io |
| `objc2-app-kit` | `0.3` (resolved `0.3.2`), `default-features = false`, features `["NSApplication", "NSResponder"]` | crates.io |
| `objc2-foundation` | `0.3` (resolved `0.3.2`), `default-features = false`, features `["NSString"]` | crates.io |
| `dispatch2` | `0.3` (resolved `0.3.1`) | crates.io |

Rust toolchain: stable (edition 2024).

## API adjustments vs. task draft

The task suggested three API calls that do NOT match the current upstream. Replacements that actually compile:

1. `gpui::App::new()` → NOT PRESENT. `App` is re-exported but has no public `new()`. The public constructor is `gpui::Application::with_platform(Rc<dyn Platform>)`; the convenience factory at this SHA is `gpui_platform::application()`. For a compile-only spike neither is needed — a type reference (`let _: Option<&gpui::Application> = None;`) forces the crate into the graph without requiring a `Platform` Rc.
2. `dispatch2::Queue::main()` → Actual type is `DispatchQueue`. Use `dispatch2::DispatchQueue::main()` which returns `&'static Self`.
3. `objc2-app-kit` with "minimal features" requires BOTH `NSApplication` AND `NSResponder` to expose `NSApplication` — the type inherits from `NSResponder` and the feature gate fails the build if only `NSApplication` is listed.

## Surprise #1 — gpui-component does not pin gpui

`gpui-component`'s `Cargo.toml` declares `gpui = { git = "https://github.com/zed-industries/zed" }` with **no `rev`**. Consequence: when a downstream consumer pins `gpui` to a specific SHA and also depends on `gpui-component`, Cargo clones the Zed monorepo **twice** — once at the consumer's pinned SHA, once at whatever Zed HEAD resolves gpui-component to. The lockfile confirms both:

```
name = "gpui" source = "git+https://github.com/zed-industries/zed?rev=f7d46cf7...#f7d46cf7..."
name = "gpui" source = "git+https://github.com/zed-industries/zed#385f6134..."
```

This compiles, but doubles the build time cost of the Zed clone. Two options for the workspace `Cargo.toml`:

- **Option A (recommended for CLAUDE.md §2):** Pin only `gpui-component` and let it transitively pull gpui. Do not pin `gpui` directly in `[workspace.dependencies]`. Accept that gpui's rev is whatever Cargo resolves on first `cargo update`. Revisit if a specific gpui feature is needed.
- **Option B:** Pin gpui at `f7d46cf7...` AND use `[patch.crates-io]` or `[patch."https://github.com/zed-industries/zed"]` to force gpui-component's transitive gpui to match. Brittle — `[patch]` sections on git deps have historically broken across Cargo versions.

Option A is simpler, and the "same SHA both places" property is only valuable if we start depending on gpui internals that gpui-component doesn't already re-export. We don't — we use GPUI's public UI API.

## Surprise #2 — objc2 0.2 vs 0.3 conflict did NOT materialize

Pre-compile worry (based on gpui-component's own lock showing `objc2-app-kit = 0.2.2`): that a transitive chain through `cocoa`/`cocoa-foundation` would introduce the 0.2 line of objc2-family in parallel with our direct 0.3 line. Reality: at this particular Zed SHA, `cocoa 0.26.0` + `cocoa-foundation 0.2.0` do NOT transitively depend on `objc2-app-kit` or `objc2-foundation` — they use the older `objc 0.2.7` / `block 0.1.6` bindings instead. The lock shows a single entry each for `objc2-app-kit 0.3.2` and `objc2-foundation 0.3.2`.

For reference the graph does contain `objc 0.2.7` (legacy) alongside `objc2 0.6.4` (modern), and `block 0.1.6` alongside `block2 0.6.2`. These are independent crates, not version conflicts — fine.

## Surprise #3 — gpui's default features include wayland/x11 on macOS

Per gpui's own `Cargo.toml`:
```toml
default = ["font-kit", "wayland", "x11", "windows-manifest"]
```
Looks wrong for a macOS-only build. Reality: the `wayland` / `x11` features gate `scap?/x11` (screen capture), and `scap` itself is `cfg`-gated to non-macOS in gpui's target-specific deps. Enabling them on macOS is a no-op. `windows-manifest` only gates `embed-resource` in a Windows build-deps block. Default features stay on; no override needed for the workspace `Cargo.toml`.

## Inputs for next turn (CLAUDE.md §2 update)

Replace `[workspace.dependencies]` entries with:

```toml
# Option A (recommended — single Zed clone)
gpui-component = { git = "https://github.com/longbridge/gpui-component", rev = "808df4069295ef4e0b3b01445671c3c7057377cd" }
# Reach gpui via gpui-component's re-exports, or via `gpui = { git = ... }` unpinned with a note
# that the rev is gpui-component's own resolved rev.

objc2 = "0.6"
objc2-app-kit = { version = "0.3", default-features = false, features = ["NSApplication", "NSResponder"] }
objc2-foundation = { version = "0.3", default-features = false, features = ["NSString"] }
dispatch2 = "0.3"
```

As more objc2-family crates are added (`objc2-core-spotlight`, `objc2-event-kit`, `objc2-contacts`), each will need its own explicit feature list — the 0.3-line crates default to zero bindings exposed. Do this per-type as they are first used.

## Files in this spike

- `Cargo.toml` — dep declarations as listed above.
- `src/main.rs` — ~15 lines, forces every crate into the compile graph via type references only. No runtime AppKit/GPUI calls.
- `Cargo.lock` — committed for the next consumer of this spike.

Delete before Week 1 per PHASE_1_PLAN.md §1.2.
