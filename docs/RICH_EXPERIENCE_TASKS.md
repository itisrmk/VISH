# Rich Experience Tasks

Goal: add Alfred/Raycast-style depth without slowing the launcher hot path. All work must stay lazy, cancellable, and triggered by selection/action state rather than by default search.

## Tasks

- [x] Selection preview pane: show a compact lazy preview only after the selected result is stable; cancel on query or selection changes.
- [x] Native Quick Look shortcut: support a direct preview shortcut for local files without changing Return as the primary action.
- [x] Rich preview types: provide useful metadata for files, apps, URLs, snippets, clipboard, AI, calculator, and system actions.
- [x] Detail mode: expose a Raycast-style detail view for the selected result with structured metadata and actions.
- [x] File buffer: allow stacking selected files for batch actions such as copy paths, reveal, and AI context.
- [x] Adaptive actions: rank Tab actions using lightweight local action history while keeping the primary action predictable.

## Shipped V1

- Preview panes are selection-driven and delayed by 160 ms so result rendering stays first.
- Image previews use bounded off-main thumbnails instead of text-reading binary files.
- `Command-Y` opens native Quick Look for local file/app results.
- `Command-I` opens the compact detail view for the selected result.
- `Command-B` adds or removes the selected local item from the in-memory file buffer.
- Tab actions include details, AI, Quick Look, reveal, copy, open-with, snippets, web search, and buffer batch actions.
- Tab action ranking uses a small local `UserDefaults` action history; Return remains the predictable primary action.

## Constraints

- No preview work while the user is actively typing.
- No synchronous file thumbnail or preview loading during row configuration.
- Preview reads must be bounded by size, delay, and cancellation.
- Search results must render before previews.
- No new runtime dependency unless the performance reason is documented in `CLAUDE.md`.
