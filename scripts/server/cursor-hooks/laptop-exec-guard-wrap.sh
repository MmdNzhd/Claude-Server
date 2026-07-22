#!/usr/bin/env bash
# Fail-open wrapper: broken guard must NEVER lock the agent (exit 2 = Cursor deny).
set +e
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)"
IMPL="${HOOK_DIR}/laptop-exec-guard.sh"
ALLOW='{"permission":"allow"}'
STAMP="${HOOK_DIR}/.guard-syntax-ok"

# Durable multi-agent audit
for _LE_AUDIT_SRC in \
    "${HOOK_DIR}/laptop-exec-audit-log.sh" \
    "${HOME}/.cursor/hooks/laptop-exec-audit-log.sh" \
    "/usr/local/lib/claude-server/cursor-hooks/laptop-exec-audit-log.sh"; do
  if [[ -f "$_LE_AUDIT_SRC" ]]; then
    # shellcheck source=/dev/null
    . "$_LE_AUDIT_SRC"
    break
  fi
done
unset _LE_AUDIT_SRC
if ! declare -F _le_audit_log >/dev/null 2>&1; then
  _le_audit_log() { :; }
  _le_audit_trunc() { printf '%s' "$1"; }
  _le_audit_slots_busy() { printf '0'; }
  _le_audit_session_fields() { printf 'tunnel_port=?'; }
fi

if [[ ! -f "$IMPL" ]]; then
  _le_audit_log ERROR WRAP_FAIL_OPEN "reason=missing_guard_impl" "impl=${IMPL}" \
    "$(_le_audit_session_fields)" "hint=Deploy laptop-exec hooks; agents are UNPROTECTED (all tools allowed)."
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
    _le_audit_log ERROR WRAP_FAIL_OPEN "reason=guard_syntax_error" "impl=${IMPL}" \
      "$(_le_audit_session_fields)" \
      "hint=Guard bash -n failed — fail-open so agents are not locked. Fix guard ASAP."
    printf '%s\n' "$ALLOW"
    exit 0
  fi
  : > "$STAMP" 2>/dev/null || true
fi

out=$(bash "$IMPL" 2>/dev/null)
rc=$?
if [[ $rc -ne 0 ]]; then
  _le_audit_log ERROR WRAP_FAIL_OPEN "reason=guard_nonzero_exit" "rc=${rc}" \
    "$(_le_audit_session_fields)" \
    "hint=Guard crashed; fail-open. Check guard stderr / recent HOOK_* lines."
  printf '%s\n' "$ALLOW"
  exit 0
fi
if [[ "$out" != *'"permission"'* ]]; then
  _le_audit_log ERROR WRAP_FAIL_OPEN "reason=guard_bad_json" \
    "out=$(_le_audit_trunc "${out:-}" 200)" "$(_le_audit_session_fields)" \
    "hint=Guard returned non-permission JSON; fail-open."
  printf '%s\n' "$ALLOW"
  exit 0
fi
printf '%s\n' "$out"
exit 0
