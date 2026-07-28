#!/usr/bin/env bash
# sessionStart: inject hard SSH-first + multi-agent rules (deny-storm prevention).
set -uo pipefail
input=$(cat || true)
for _LE_AUDIT_SRC in \
    "$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd)/laptop-exec-audit-log.sh" \
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

_remote_path_for() {
  local pid="$1" conf="${HOME}/.claude-mounts.d/${pid}.conf" line v
  [[ -f "$conf" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    # mounts.d uses REMOTE_PATH= (legacy) or rpath= (connect UI) — both valid.
    [[ "$line" =~ ^(REMOTE_PATH|remote_path|rpath)=(.*)$ ]] || continue
    v="${BASH_REMATCH[2]}"
    v="${v%\"}"; v="${v#\"}"
    v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
    return 0
  done < "$conf"
  return 1
}

_windows_hybrid_ready() {
  local os="" conf="${HOME}/.claude-connect.conf"
  [[ -f "$conf" ]] || return 1
  os=$(grep -E '^(LAPTOP_OS|laptop_os)=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr '[:upper:]' '[:lower:]')
  case "$os" in mac|darwin|osx) return 1 ;; esac
  [[ -f "${HOME}/.config/windows-mcp/env" ]] || return 1
  return 0
}

roots=$(printf '%s' "$input" | jq -r '(.workspace_roots // []) | map(tostring) | .[]' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
pid="$(_extract_pid "$roots"$'\n'"$cwd"$'\n'"${PWD:-}" 2>/dev/null || true)"
user="${USER:-smart}"

base='PRIORITY+FAILOVER (2026-07-28): Prefer 1st path; if down/error use 2nd then 3rd same turn. HEALTHY MOUNT: NEVER laptop-exec read/rg — use Cursor Read/Grep on /mounts (~16-32). READ/GREP=mount→MCP→LE. WRITE=MCP→mount→LE (~8-10). Glob=MCP→mount. git=LE only. One MCP hard fail=>MCP down; continue mount+LE. No rg -i/-l/-n/-A/-B/-C/-m/-g/--glob/--type/--max-count. LE read=one file (no --offset/--limit/multi-file).'

if _windows_hybrid_ready; then
  hybrid='READ/GREP=>Cursor on mount first (not LE). Then MCP if listed then LE. WRITE=>MCP if listed then mount then LE. git=>laptop-exec. Failover if path down.'
else
  hybrid='READ/GREP=>Cursor on mount first (not LE). Then MCP if listed then LE. WRITE/EDIT=>MCP if listed then mount then LE. git=>laptop-exec.'
fi

multi='MULTI-AGENT: paste PRIORITY+FAILOVER: healthy mount=>Cursor Read/Grep only; prefer 1st; if down use 2nd/3rd. READ=mount→MCP→LE; WRITE=MCP→mount→LE; Glob=MCP; git=LE. No rg ripgrep flags. Children do not inherit. Tunnel DOWN=>stop; connect.bat/sh.'

if [[ -z "$pid" ]]; then
  _le_audit_log WARN SESSION_START "project=?" "cwd=$(_le_audit_trunc "${cwd:-${PWD:-}}" 200)" \
    "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8" \
    "hint=Could not infer project from workspace_roots; agents must pass -p ID explicitly."
  ctx="$base $hybrid $multi Tunnel DOWN => stop; tell user to run connect.bat/sh."
  jq -n --arg ctx "$ctx" '{additional_context:$ctx}'
else
  rpath="$(_remote_path_for "$pid" || true)"
  _le_audit_log INFO SESSION_START "project=${pid}" "workspace=/home/${user}/mounts/${pid}" \
    "cwd=$(_le_audit_trunc "${cwd:-}" 200)" "$(_le_audit_session_fields)" \
    "slots_busy=$(_le_audit_slots_busy)/8" "hint=Hybrid: mount Read/Grep ~16-32; MCP FS ~8-12 write/read; LE <=4 (cap 8). Never LE read/rg when mount healthy."
  examples="Examples: healthy READ=>Cursor Read /home/$USER/mounts/${pid}/REL (NOT laptop-exec read); GREP=>Cursor Grep; if mount fails=>MCP then LE | WRITE=>MCP then mount | Glob=>MCP search | git: laptop-exec git -p ${pid} -- status."
  if [[ -n "${rpath:-}" ]]; then
    examples="${examples} Project Windows root: ${rpath}"
  fi
  ctx="$base $hybrid Project=${pid}. ${examples} $multi"
  ws="/home/${user}/mounts/${pid}"
  if [[ -n "${rpath:-}" ]]; then
    jq -n --arg ctx "$ctx" --arg pid "$pid" --arg ws "$ws" --arg rpath "$rpath" \
      '{additional_context:$ctx, env:{LAPTOP_EXEC_WORKSPACE:$ws, LAPTOP_EXEC_PROJECT:$pid, LAPTOP_REMOTE_PATH:$rpath}}'
  else
    jq -n --arg ctx "$ctx" --arg pid "$pid" --arg ws "$ws" \
      '{additional_context:$ctx, env:{LAPTOP_EXEC_WORKSPACE:$ws, LAPTOP_EXEC_PROJECT:$pid}}'
  fi
fi
exit 0
