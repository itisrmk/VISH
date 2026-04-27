# VISH Optimization Tasks

## Active Order

- [x] Keep AI chat and embedding models separated.
- [x] Make AI benchmark report warm and cold chat/embed timings.
- [x] Release Settings memory after the window closes.
- [x] Move uncached file/app icon work off the launcher render path.
- [x] Expand signpost reporting to cover search pipeline timing.
- [x] Tighten semantic vector scoring to avoid avoidable allocations and syscalls.
- [x] Re-run build, smoke, and AI benchmarks after each optimization batch.

## Guardrails

- Launcher first render must never wait on AI, indexing, Spotlight, or icon decoding.
- Settings/indexing progress is allowed to refresh slowly; launcher typing is not.
- Prefer tiny, measurable changes over broad rewrites.
- Keep fallback behavior useful when Ollama, embedding models, or MemPalace are missing.

## Targets

- Hotkey to first frame p95: 16 ms or less.
- Keystroke to rendered result p95: 16 ms or less.
- Spotlight p95: 30 ms or less.
- Warm 8-document embedding batch: 500 ms or less.
- App/File candidate ranking: no first-query index build on the launcher hot path.

## Remaining Measurement

- Capture an Instruments Points of Interest trace and run `scripts/signpost-report.sh` before claiming the 16 ms frame-level targets are met.
