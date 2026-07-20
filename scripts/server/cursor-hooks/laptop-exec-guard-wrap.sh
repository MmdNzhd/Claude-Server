#!/usr/bin/env bash
# Fail-open wrapper: broken guard must NEVER lock the agent (exit 2 = Cursor deny).
set +e
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)"
IMPL="${HOOK_DIR}/laptop-exec-guard.sh"
ALLOW='{"permission":"allow"}'
STAMP="${HOOK_DIR}/.guard-syntax-ok"

if [[ ! -f "$IMPL" ]]; then
  printf '%s\n' "$ALLOW"
  exit 0
fi

# Syntax-check only when guard changes (bash -n every call was multi-agent tax).
_need_check=1
if [[ -f "$STAMP" && "$STAMP" -nt "$IMPL" ]]; then
  _need_check=0
fi
if [[ "$_need_check" -eq 1 ]]; then
  if ! bash -n "$IMPL" 2>/dev/null; then
    printf '%s\n' "$ALLOW"
    exit 0
  fi
  : > "$STAMP" 2>/dev/null || true
fi

out=$(bash "$IMPL" 2>/dev/null)
rc=$?
if [[ $rc -ne 0 ]]; then
  printf '%s\n' "$ALLOW"
  exit 0
fi
if [[ "$out" != *'"permission"'* ]]; then
  printf '%s\n' "$ALLOW"
  exit 0
fi
printf '%s\n' "$out"
exit 0
