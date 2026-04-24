#!/usr/bin/env bash
# Phase 0 spike S1 — verify mlx_lm.server OpenAI Chat Completions SSE conformance.
#
# Why SmolLM2-135M: the spike validates the server's protocol, not inference quality.
# A 135M-param Q4 model is ~80MB to download vs ~4.5GB for Llama-3.1-8B-Q4. Same
# server, same SSE, same /v1/chat/completions surface — just faster iteration.
# Llama-3.1-8B-Q4 is validated in Phase 3 proper.

set -euo pipefail

PORT="${PORT:-8765}"
MODEL="${MODEL:-mlx-community/SmolLM2-135M-Instruct-4bit}"
TMP="${TMPDIR:-/tmp}"
SERVER_LOG="$TMP/mlx-spike-server.log"
MODELS_JSON="$TMP/mlx-spike-models.json"
READY_TIMEOUT="${READY_TIMEOUT:-300}"

log()  { printf '[S1] %s\n' "$*"; }
fail() { printf '[S1] FAIL: %s\n' "$*" >&2; exit 1; }

command -v uv   >/dev/null 2>&1 || fail "uv not on PATH"
command -v curl >/dev/null 2>&1 || fail "curl not on PATH"
command -v jq   >/dev/null 2>&1 || fail "jq not on PATH (brew install jq)"

log "starting mlx_lm.server  model=$MODEL  port=$PORT  log=$SERVER_LOG"
uv run --with mlx-lm mlx_lm.server \
    --model "$MODEL" \
    --host 127.0.0.1 \
    --port "$PORT" \
    > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; true' EXIT
log "server pid=$SERVER_PID"

log "waiting for GET /v1/models  (timeout ${READY_TIMEOUT}s)"
READY=""
for i in $(seq 1 "$READY_TIMEOUT"); do
    if curl -fs "http://127.0.0.1:$PORT/v1/models" -o "$MODELS_JSON" 2>/dev/null; then
        log "ready after ${i}s"
        READY="y"
        break
    fi
    sleep 1
done
if [ -z "$READY" ]; then
    log "--- last 40 lines of server log ---"
    tail -40 "$SERVER_LOG" || true
    fail "server did not come up in ${READY_TIMEOUT}s"
fi

log "GET /v1/models:"
jq . "$MODELS_JSON"

log "POST /v1/chat/completions stream=true (max_tokens=8):"
BODY=$(jq -nc --arg m "$MODEL" '{
    model: $m,
    stream: true,
    max_tokens: 8,
    messages: [{role: "user", content: "Say hi."}]
}')
curl -sS -N -X POST "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    | head -30

echo
log "PASS: server responded. Inspect above for OpenAI SSE shape:"
log "  - each line 'data: {...}' is an OpenAI delta chunk"
log "  - final line is 'data: [DONE]'"
log "  - shape must be unchanged from OpenAI Chat Completions spec or vish-llm needs a shim"
