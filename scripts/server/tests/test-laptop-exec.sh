#!/usr/bin/env bash
# laptop-exec regression: binary self-test + hook/matcher invariants
set -euo pipefail
LE="${1:-/usr/local/bin/laptop-exec}"
"$LE" test

HOOKS="${HOME}/.cursor/hooks.json"
if [ -f "$HOOKS" ] && command -v jq >/dev/null 2>&1; then
  m=$(jq -r '.hooks.preToolUse[]? | select(.command|endswith("laptop-exec-guard-wrap.sh")) | .matcher // empty' "$HOOKS" | head -1)
  if [[ "$m" == *Shell* ]]; then
    echo "FAIL  hooks.json preToolUse matcher contains Shell: $m" >&2
    exit 1
  fi
  echo "PASS  hooks matcher has no Shell"
fi

GUARD="${HOME}/.cursor/hooks/laptop-exec-guard.sh"
if [ -x "$GUARD" ]; then
  out=$(printf '%s' '{"hook_event_name":"preToolUse","tool_name":"Task"}' | bash "$GUARD")
  echo "$out" | grep -Eq '"permission"[[:space:]]*:[[:space:]]*"allow"' || { echo "FAIL Task allow"; exit 1; }
  echo "$out" | grep -qi 'SSH-first\|laptop-exec\|Child prompt' || { echo "FAIL Task agent_message"; exit 1; }
  echo "PASS  Task allow + agent_message"
fi

for p in "$HOME"/mounts/*/.cursor/hooks.json; do
  [ -f "$p" ] || continue
  if command -v jq >/dev/null 2>&1; then
    h=$(jq -c '.hooks // {}' "$p")
    [ "$h" = "{}" ] || { echo "FAIL nonempty project hooks: $p -> $h" >&2; exit 1; }
  fi
done
echo "PASS  project hooks empty"
echo "ALL EXTRA CHECKS PASSED"
