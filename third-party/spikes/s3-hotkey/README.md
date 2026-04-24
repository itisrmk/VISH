# s3-hotkey — Phase 0 spike S3

Validates that the `global-hotkey` crate can register **⌥Space** on current macOS and
deliver events, **without** triggering an Accessibility permission prompt. This is the
kill-check for CLAUDE.md §10 invariant #10 (only hotkey API allowed is `global-hotkey`).

## Run

```bash
cd third-party/spikes/s3-hotkey
cargo run
```

Then press **⌥Space**. Expected output per press:

```
INFO s3_hotkey: hotkey fired id=<u32> state=Pressed
INFO s3_hotkey: hotkey fired id=<u32> state=Released
```

Ctrl-C (or Cmd-Q) to exit.

## Failure criterion

If macOS shows a **"… would like to control this computer using accessibility
features"** prompt, the spike has **FAILED**. `global-hotkey` relies on the Carbon
`RegisterEventHotKey` API, which should not require AX for modifier+key chords. An
AX prompt means Apple changed the surface area and vish's hotkey strategy has to
change (fallback: ⌥⌘Space, per PHASE_1_PLAN.md risk R2). Escalate before Week 2.

Silent failure (no log line on ⌥Space) is also a fail — hotkey conflict with another
process or the registration silently dropping.
