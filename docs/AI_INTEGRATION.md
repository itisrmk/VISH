# AI_INTEGRATION.md - vish local AI plan

## Product rule

AI is an opt-in assistant layer, not the launcher. The default flow stays: hotkey, type, Enter. AI never runs on startup, never participates in default ranking, and never blocks app/file/calculator/system results.

The first useful version is "local context help":

- Answer questions about files, folders, clipboard text, snippets, and prior VISH interactions.
- Explain or summarize a selected file/result through Universal Actions.
- Convert selected text into a snippet, quicklink, or search query.
- Find likely files by meaning when filename search is not enough.
- Suggest safe next actions, but require explicit user confirmation before opening, deleting, moving, editing, or running system commands.

## Runtime choice

Primary runtime: Ollama local API.

Reasoning:

- VISH can talk to `http://localhost:11434/api` with no embedded model server, no Python in the app bundle, and no startup cost.
- Ollama exposes streaming chat, embeddings, model listing, and keep-alive controls over a stable local REST API.
- On Apple Silicon, Ollama's MLX preview is the preferred fast path when available. If the installed Ollama version/model does not support MLX, VISH still works through Ollama's normal local backend.

Fallback runtime: direct `mlx-lm` sidecar only if profiling proves Ollama overhead or model coverage is the blocker. Do not ship both paths before one real user problem requires it.

## Memory choice

Use two separate memory layers:

- VISH index: fast file/app/system/snippet/clipboard retrieval, owned by VISH, optimized for UI latency.
- MemPalace: long-term AI memory for conversations, decisions, user preferences, and explicitly mined projects/folders.

Do not dump the entire disk into MemPalace by default. Full Disk Access gives VISH permission to index/search files, but AI memory ingestion must remain scoped and visible. The AI may retrieve file candidates from VISH and then read small previews through a capped tool.

MemPalace integration starts through its CLI/Python API, not MCP. MCP is useful for external agents, but VISH needs a direct, predictable local integration with bounded process cost.

## UX entry points

Use explicit triggers so AI cannot slow normal launcher work:

- `ai <question>`: stream a local answer in the launcher lower pane.
- `? <question>`: alias for quick questions.
- `ai find/search/locate/show me ...` and `? find/search ...`: AI file finder. VISH parses the natural-language file intent, searches its file index plus Spotlight, reads tiny previews for the shortlist, then reranks candidates with local Ollama embeddings when Local AI is enabled. Results stay normal file rows with existing actions.
- Universal Actions on a selected result: `Ask AI`, `Summarize`, `Explain`, `Find Related`, `Save Answer as Snippet`. Current build implements `Ask AI`, `Summarize`, and `Explain`; the other two are deferred.
- Settings: Local AI toggle, runtime status, model selector, memory scope, indexing/memory progress, benchmark button.

The launcher result list should only show one low-priority "Ask local AI" row after fast results are already rendered. Selecting it swaps the lower pane from results to an inline AI answer view; it does not create a separate window.

## Tool boundary

The model never receives direct filesystem access. It can request these VISH-owned tools:

- `search_files(query, scope, limit)`: file metadata and ranked paths only.
- `read_file_preview(path, byte_limit)`: text preview, default 16 KB, max 64 KB, deny binary and protected extensions.
- `search_memory(query, limit)`: MemPalace semantic results.
- `search_clipboard(query, limit)`: only when Clipboard History is enabled.
- `search_snippets(query, limit)`: snippets metadata and expansion text.
- `open_result(id)`, `reveal_result(id)`, `copy_text(value)`: confirmation required except copy.

No shell execution, no arbitrary file writes, no deletion/move/rename in the first AI phase.

## Privacy and safety

- Local-only by default. No cloud fallback.
- AI disabled by default.
- Per-folder memory ingestion allowlist.
- Denylist secret-like paths and extensions: `.ssh`, `.gnupg`, Keychain exports, 1Password/Bitwarden exports, `.env`, private keys, certificates, browser cookies, caches.
- Show sources for every answer. If no source was used, label it as model-only.
- Keep prompt context capped. Prefer top 5 retrieved snippets plus file previews over huge prompts.
- Store AI transcripts only if the user enables memory.

## Performance gates

Existing VISH budgets remain unchanged:

- Cold launch <= 120 ms.
- Hotkey to first frame <= 16 ms.
- Keystroke to rendered result <= 16 ms p95.
- Idle CPU 0.0%.
- Idle RSS <= 80 MB before any model is loaded.

AI-specific budgets:

- With AI disabled: no new resident process, no network listener, no model probing on startup.
- With AI enabled but idle: VISH RSS increase <= 10 MB, CPU remains 0.0%, no model loaded unless the user opts into warm mode.
- Trigger row latency: `ai ` or `? ` intent classification <= 1 ms and first placeholder row <= 16 ms.
- Warm local answer: first streamed token <= 1500 ms on the selected default model.
- Warm local answer throughput: >= 20 tokens/sec on the selected default model.
- Embedding batch: 8 short documents embedded <= 500 ms after model warmup.
- Memory search: MemPalace top-5 search <= 250 ms warm.
- File preview assembly: top-5 previews, 16 KB each, <= 50 ms after file candidates are known.
- Semantic file finder: intent parse <= 1 ms, candidate fusion before preview <= 50 ms warm, preview rerank limited to top 12 candidates and off the main thread.

Hardware tiers may override model recommendations, not UI budgets.

## Implementation phases

### Phase AI-0 - Bench and status

- Add an AI benchmark script that measures Ollama chat TTFT, tokens/sec, embeddings, and MemPalace search when available.
- Add Settings status only: Ollama reachable, installed models, selected model, MemPalace reachable.
- No AI result rows yet.

### Phase AI-1 - Ask selected result

- Add Universal Actions: `Ask AI`, `Summarize`, `Explain`, `Find Related`.
- Stream answer in the existing launcher detail area.
- Context source is only the selected result plus capped file/text preview.
- Current build: `Ask AI`, `Summarize`, and `Explain` are implemented for app, file, URL/web/quicklink, clipboard, and snippet results. URL content is not fetched; file previews are capped and secret-like paths are denied.

### Phase AI-2 - AI trigger

- Add `ai ` and `? ` intents.
- Render a single low-priority "Ask local AI" row after fast results.
- Selecting the row opens the inline AI answer view and streams.
- Current build also implements semantic file finder triggers before normal AI chat: `ai find/search/locate/show me ...` and `? find/search ...`.
- Current semantic file finder is retrieval-first, not LLM-first: it combines VISH file index, filename search, Spotlight content search, capped previews, and a local vector cache stored at `Application Support/vish/file-vectors.plist`. Settings > Files > Warm builds semantic vectors after the filename catalog only when a dedicated embedding model is available, skips unchanged files by path/model/modified time, and pauses while the launcher is active. Interactive semantic queries embed only the query and read cached vectors; they do not create file vectors. Automatic idle vector ingestion remains deferred until it can be scheduled without affecting launcher latency.

### Phase AI-3 - Memory

- Add MemPalace search and write integration.
- Store only user-approved AI transcripts and saved facts.
- Add scoped folder/project mining from Settings with visible progress.

### Phase AI-4 - Tool calling

- Add constrained tool loop for search/read/open/reveal/copy.
- Require confirmation for side effects.
- Add source citations and tool trace in answer view.

## Model policy

Default model should be small enough to feel instant. On unknown hardware, prefer a 3B-8B instruct model. The 35B MLX preview class is optional for high-memory Macs; Ollama currently recommends more than 32 GB unified memory for that class.

Model settings:

- `stream: true`
- `think: false` by default
- `keep_alive: 5m` only after first user AI request
- Low temperature for file/help tasks
- Small `num_predict` for quick actions

Embedding policy:

- Use a dedicated embedding model for vector indexing and querying. Do not use a chat model for full-disk vector indexing.
- Prefer `embeddinggemma` when available. Ollama documents it as a 300M on-device embedding model for search/retrieval, and the app can install it through `/api/pull`.
- Keep embedding previews small: file name, folder/path, and a capped first preview chunk. Larger summaries belong in explicit selected-result AI actions, not background indexing.

## Non-goals for the first AI release

- Autonomous agents.
- Background full-disk summarization.
- Shell command execution.
- File editing/moving/deleting.
- Cloud models.
- Web search through the model.
- Training or fine-tuning.
