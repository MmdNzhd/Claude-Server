#!/usr/bin/env bash
# sessionStart: inject hard SSH-first + multi-agent rules (deny-storm prevention).
set -uo pipefail
input=$(cat || true)
for _LE_AUDIT_SRC in     "$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd)/laptop-exec-audit-log.sh"     "${HOME}/.cursor/hooks/laptop-exec-audit-log.sh"     "/usr/local/lib/claude-server/cursor-hooks/laptop-exec-audit-log.sh"; do
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
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }

_extract_pid() {
  local text="$1" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ /mounts/([^/[:space:]]+) ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <<< "$text"
  return 1
}

roots=$(printf '%s' "$input" | jq -r '(.workspace_roots // []) | map(tostring) | .[]' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
pid="$(_extract_pid "$roots"$'\n'"$cwd"$'\n'"${PWD:-}" 2>/dev/null || true)"
user="${USER:-smart}"

base='SSH-FIRST HARD STOP: Never call Cursor Read/Grep/Glob/Write/Edit/StrReplace/Delete on ~/mounts/. Deny expected — do NOT retry; run NEXT:. First I/O = Shell + laptop-exec -p ID (read|rg|write|git|run). Never laptop-exec rg -i/-l/-n/--glob. Paths repo-relative (never /home/.../mounts/).'

multi='MULTI-AGENT: Task spawn allowed. EVERY Task prompt MUST paste: SSH-first mandatory; laptop-exec -p PROJECT on every read/rg/git/run/write; never Read/Grep/Write on /mounts/; never rg -i/-l/-n/--glob; on deny run NEXT:; prefer ≤4 parallel (hard cap 8 slots). Children do not inherit parent discipline. Queue OK — never raw ssh. Tunnel DOWN => stop; user connect.bat/sh.'

if [[ -z "$pid" ]]; then
  _le_audit_log WARN SESSION_START "project=?" "cwd=$(_le_audit_trunc "${cwd:-${PWD:-}}" 200)"     "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8"     "hint=Could not infer project from workspace_roots; agents must pass -p ID explicitly."
  ctx="$base $multi Tunnel DOWN => stop; tell user to run connect.bat/sh."
  jq -n --arg ctx "$ctx" '{additional_context:$ctx}'
else
  _le_audit_log INFO SESSION_START "project=${pid}" "workspace=/home/${user}/mounts/${pid}"     "cwd=$(_le_audit_trunc "${cwd:-}" 200)" "$(_le_audit_session_fields)"     "slots_busy=$(_le_audit_slots_busy)/8" "hint=Multi-agent: ≤4 parallel laptop-exec; paste SSH-first into every Task prompt."
  ctx="$base Project=${pid}. Examples: laptop-exec read -p ${pid} REL | laptop-exec rg -p ${pid} PATTERN | laptop-exec write -p ${pid} REL | laptop-exec git -p ${pid} -- status. $multi"
  ws="/home/${user}/mounts/${pid}"
  jq -n --arg ctx "$ctx" --arg pid "$pid" --arg ws "$ws"     '{additional_context:$ctx, env:{LAPTOP_EXEC_WORKSPACE:$ws, LAPTOP_EXEC_PROJECT:$pid}}'
fi
exit 0
