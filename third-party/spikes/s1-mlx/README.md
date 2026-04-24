# s1-mlx — Phase 0 spike S1

Validates that `mlx_lm.server` speaks OpenAI Chat Completions SSE verbatim. This is the foundation of `vish-llm`'s backend abstraction (CLAUDE.md §6) — if `mlx_lm.server` conforms, swapping between MLX / Ollama / any cloud backend is a config change, not a code change.

The spike uses `mlx-community/SmolLM2-135M-Instruct-4bit` (~80MB) because the spike is **protocol-only**. Llama-3.1-8B-Q4 is validated in Phase 3 when inference quality matters.

## Prerequisites

- `uv` (Astral's Python package manager).
- `jq`, `curl`.

Install `uv` if not present:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# then restart shell or: source $HOME/.local/bin/env
```

> Phase 0 kickoff discovered `uv` was not actually present on this machine despite the initial questionnaire answer. `run.sh`'s first sanity check exits with `FAIL: uv not on PATH` if it's missing; that's the expected behavior — install uv and re-run.

## Run

```bash
cd third-party/spikes/s1-mlx
./run.sh
```

Expected timing:
- **First run:** ~2–3 min (uv downloads `mlx-lm` into its global cache + SmolLM2 weights).
- **Subsequent runs:** ~15–30 s.

Environment variables (all optional):
- `PORT` — server port (default `8765`)
- `MODEL` — HF model id (default `mlx-community/SmolLM2-135M-Instruct-4bit`)
- `READY_TIMEOUT` — seconds to wait for `/v1/models` (default `300`)

## Pass criteria

1. Server binds `127.0.0.1:<PORT>` within timeout.
2. `GET /v1/models` returns JSON listing the loaded model.
3. `POST /v1/chat/completions` with `"stream": true` streams Server-Sent Events where:
   - Every data line is `data: {<OpenAI delta chunk JSON>}`
   - Final line is `data: [DONE]`

## Failure modes

| Symptom | Likely cause | Escalation |
|---|---|---|
| `uv run --with mlx-lm` errors | Python 3.11+ missing or corrupt venv cache | `uv python install 3.11 && uv cache clean` |
| Server never responds to `/v1/models` | Model download stuck or MLX init panic | inspect `/tmp/mlx-spike-server.log` |
| Server 404s on `/v1/chat/completions` | mlx_lm.server version too old (pre-OpenAI-compat) | pin newer `mlx-lm` in Phase 3 sidecar |
| Response shape is not OpenAI spec | mlx_lm.server schema diverged from OpenAI | `vish-llm` needs a per-backend shim; escalate — this breaks CLAUDE.md §6 |

## Teardown

The script's `trap` kills the server on any exit path (success, failure, Ctrl-C). No manual cleanup needed.
