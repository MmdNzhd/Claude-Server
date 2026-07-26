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
    [[ "$line" =~ ^(REMOTE_PATH|remote_path)=(.*)$ ]] || continue
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

base='SSH-FIRST HARD STOP: Never call Cursor Read/Grep/Glob/Write/Edit/StrReplace/Delete on ~/mounts/. Deny expected - do NOT retry; run NEXT:. Never laptop-exec rg -i/-l/-n/--glob. Paths: laptop-exec=repo-relative (-p ID); windows-mcp FileSystem=absolute Windows under project root (not Desktop-relative).'

if _windows_hybrid_ready; then
  hybrid='Windows hybrid CONFIGURED: prefer windows-mcp FileSystem/PowerShell/UI ONLY if those tools are listed in the catalog. SPEED: ~8 parallel FileSystem calls in ONE turn when MCP works. FAIL-FAST: tools missing OR one ECONNREFUSED/fetch failed => MCP down for session; use laptop-exec immediately; never retry denied Read; never retry same MCP call. user-filesystem≠windows-mcp. Keep laptop-exec for git, content rg, and MCP-down.'
else
  hybrid='First I/O = Shell + laptop-exec -p ID (read|rg|write|git|run). On Windows, if windows-mcp tools become listed mid-session, switch FS/shell/UI to MCP; still FAIL-FAST on one connection error.'
fi

multi='MULTI-AGENT: Task spawn allowed. EVERY Task prompt MUST paste hybrid+FAIL-FAST: never Read/Grep/Write on /mounts/; never rg -i/-l/-n/--glob; on deny run NEXT:; windows-mcp only if tools listed; one MCP fail=>laptop-exec only. Parallelism: MCP ~8/turn when ready; laptop-exec <=4 (cap 8). Children do not inherit discipline. Tunnel DOWN => stop; user connect.bat/sh.'

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
    "slots_busy=$(_le_audit_slots_busy)/8" "hint=Hybrid: fan-out ~8 parallel windows-mcp FS; laptop-exec <=4 (cap 8 slots)."
  examples="Examples: fan-out ~8x windows-mcp FileSystem reads (absolute under project root) in one turn | laptop-exec rg -p ${pid} PATTERN | laptop-exec git -p ${pid} -- status | laptop-exec read -p ${pid} REL as fallback."
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
