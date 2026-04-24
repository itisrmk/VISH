#!/usr/bin/env bash
# PostToolUse hook: append one-line bullets to log.md for Bash/Write/Edit tool uses.
# Invoked by Claude Code, reads the tool-use JSON envelope on stdin.
set -u

# Ensure brew-installed tools (jq) resolve whether on Apple Silicon or Intel.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG="/Users/rahulkashyap/Desktop/Projects/VISH/log.md"
INPUT=$(cat)
TS=$(date -u +%FT%TZ)

if ! command -v jq >/dev/null 2>&1; then
  printf -- '- `%s` _(hook fired, jq not installed)_\n' "$TS" >> "$LOG"
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"')

case "$TOOL" in
  Bash)
    DESC=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""')
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' | tr '\n' ' ' | cut -c1-180)
    printf -- '- `%s` **Bash** — %s — `%s`\n' "$TS" "$DESC" "$CMD" >> "$LOG"
    ;;
  Write|Edit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
    # Skip edits to the log itself to prevent noise.
    case "$FP" in
      */log.md) exit 0 ;;
    esac
    printf -- '- `%s` **%s** — `%s`\n' "$TS" "$TOOL" "$FP" >> "$LOG"
    ;;
  *)
    printf -- '- `%s` **%s**\n' "$TS" "$TOOL" >> "$LOG"
    ;;
esac

exit 0
