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

# Inline _sshfs_state semantics (do not source laptop-exec.sh).
# Returns MOUNTED | STALE | NOT_LIVE (NOT_MOUNTED mapped to NOT_LIVE for paste).
_session_mount_class() {
  local mp="$1" out="" rc=0
  [[ -n "$mp" ]] || { printf 'NOT_LIVE'; return; }
  # Prefer /proc/mounts (mountpoint -q hangs on frozen SSHFS).
  if ! grep -F " ${mp} " /proc/mounts >/dev/null 2>&1; then
    printf 'NOT_LIVE'
    return
  fi
  out=$(timeout 2 ls "$mp" 2>&1) || rc=$?
  if [[ "$rc" -ne 0 ]] || [[ "$out" == *"Input/output error"* ]] || [[ "$out" == *"Transport endpoint"* ]]; then
    printf 'STALE'
    return
  fi
  printf 'MOUNTED'
}

roots=$(printf '%s' "$input" | jq -r '(.workspace_roots // []) | map(tostring) | .[]' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
pid="$(_extract_pid "$roots"$'\n'"$cwd"$'\n'"${PWD:-}" 2>/dev/null || true)"
user="${USER:-smart}"

base='PRIORITY+FAILOVER (2026-07-28): Prefer 1st path; if down/error use 2nd then 3rd same turn. Parallel mount~16-32 LE≤4. HEALTHY MOUNT: NEVER laptop-exec read/rg — use Cursor Read/Grep on /mounts (~16-32). READ/GREP=mount→MCP→LE. WRITE=MCP→mount→LE (~8-10). Glob=MCP→mount. git=LE only. One MCP hard fail=>MCP down; continue mount+LE. No rg -i/-l/-n/-A/-B/-C/-m/-g/--glob/--type/--max-count. LE read=one file (no --offset/--limit/multi-file). ANTI-DIE: no rg --glob/-A/--type; git -p PROJECT before subcommand (git log -p OK); LE read=one relative file; no invent verbs; no abs /mounts in LE.'

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
  ws="/home/${user}/mounts/${pid}"
  # ACTIVE_MOUNT may differ from workspace project (single-project SSHFS).
  am=""
  if [[ -f "${HOME}/.claude-connect.conf" ]]; then
    am=$(grep -E '^(ACTIVE_MOUNT|active_mount)=' "${HOME}/.claude-connect.conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d '\r')
  fi
  mount_class="$(_session_mount_class "$ws")"
  mismatch_note=""
  if [[ -n "${am:-}" && "$am" != "$pid" ]]; then
    mismatch_note="ACTIVE_MISMATCH active=${am} workspace=${pid}"
  fi
  case "$mount_class" in
    MOUNTED)
      _le_audit_log INFO SESSION_START "project=${pid}" "workspace=${ws}" "MOUNT_CLASS=MOUNTED" \
        "active_mount=${am:-?}" ${mismatch_note:+"$mismatch_note"} \
        "cwd=$(_le_audit_trunc "${cwd:-}" 200)" "$(_le_audit_session_fields)" \
        "slots_busy=$(_le_audit_slots_busy)/8" "hint=HEALTHY MOUNT live — Cursor Read/Grep; never LE read/rg first."
      base_live="PRIORITY+FAILOVER (2026-07-28): Prefer 1st path; if down use 2nd/3rd same turn. Parallel mount~16-32 LE≤4. MOUNT_CLASS=MOUNTED HEALTHY MOUNT LIVE path=${ws}: NEVER laptop-exec read/rg — Cursor Read/Grep (~16-32). READ/GREP=mount→MCP→LE. WRITE=MCP→mount→LE. Glob=MCP→mount. git=LE -p ${pid}. No rg ripgrep flags. LE read=one relative file. ANTI-DIE: no rg --glob/-A/--type; git -p PROJECT before subcommand (git log -p OK); LE read=one relative file; no invent verbs; no abs /mounts in LE."
      examples="Examples: READ=>Cursor Read ${ws}/REL; GREP=>Cursor Grep; mount fail=>MCP then LE -p ${pid} | WRITE=>MCP | git: laptop-exec git -p ${pid} -- status."
      ;;
    STALE)
      _le_audit_log WARN SESSION_START "project=${pid}" "workspace=${ws}" "MOUNT_CLASS=STALE" \
        "active_mount=${am:-?}" ${mismatch_note:+"$mismatch_note"} \
        "cwd=$(_le_audit_trunc "${cwd:-}" 200)" "$(_le_audit_session_fields)" \
        "slots_busy=$(_le_audit_slots_busy)/8" "hint=STALE mount — do NOT Cursor Read ${ws}; use MCP then LE -p ${pid}."
      base_live="PRIORITY+FAILOVER (2026-07-28): Prefer 1st path; if down use 2nd/3rd same turn. Parallel mount~16-32 LE≤4. MOUNT_CLASS=STALE path=${ws} in /proc/mounts but ls/I/O failed (Transport endpoint or I/O error). Do NOT trust Cursor Read/Grep on ${ws}. Use MCP FileSystem then laptop-exec -p ${pid}. WRITE=MCP→LE. git=LE -p ${pid}. Prefer reconnect/remount. ANTI-DIE: no rg --glob/-A/--type; git -p PROJECT before subcommand (git log -p OK); LE read=one relative file; no invent verbs; no abs /mounts in LE."
      examples="Examples: READ=>MCP abs Windows path or laptop-exec read -p ${pid} REL (STALE — skip Cursor Read on ${ws}) | git: laptop-exec git -p ${pid} -- status | remount: connect and select project ${pid}."
      ;;
    *)
      _le_audit_log WARN SESSION_START "project=${pid}" "workspace=${ws}" "MOUNT_CLASS=NOT_LIVE" \
        "active_mount=${am:-?}" ${mismatch_note:+"$mismatch_note"} \
        "cwd=$(_le_audit_trunc "${cwd:-}" 200)" "$(_le_audit_session_fields)" \
        "slots_busy=$(_le_audit_slots_busy)/8" "hint=Do NOT Cursor Read ${ws} — use MCP then LE -p ${pid}."
      base_live="PRIORITY+FAILOVER (2026-07-28): Prefer 1st path; if down use 2nd/3rd same turn. Parallel mount~16-32 LE≤4. MOUNT_CLASS=NOT_LIVE for ${pid} (ACTIVE_MOUNT=${am:-none}, path=${ws} not in /proc/mounts). Do NOT Cursor Read/Grep ${ws}. Use MCP FileSystem then laptop-exec -p ${pid}. WRITE=MCP→LE. git=LE -p ${pid}. Prefer reconnect/mount if you need SSHFS. ANTI-DIE: no rg --glob/-A/--type; git -p PROJECT before subcommand (git log -p OK); LE read=one relative file; no invent verbs; no abs /mounts in LE."
      examples="Examples: READ=>MCP abs Windows path or laptop-exec read -p ${pid} REL | git: laptop-exec git -p ${pid} -- status | to mount: connect and select project ${pid}."
      ;;
  esac
  if [[ -n "$mismatch_note" ]]; then
    examples="${examples} ${mismatch_note}."
  fi
  if [[ -n "${rpath:-}" ]]; then
    examples="${examples} Project Windows root: ${rpath}"
  fi
  ctx="$base_live $hybrid Project=${pid}. ${examples} $multi"
  if [[ -n "${rpath:-}" ]]; then
    jq -n --arg ctx "$ctx" --arg pid "$pid" --arg ws "$ws" --arg rpath "$rpath" --arg mclass "$mount_class" \
      '{additional_context:$ctx, env:{LAPTOP_EXEC_WORKSPACE:$ws, LAPTOP_EXEC_PROJECT:$pid, LAPTOP_REMOTE_PATH:$rpath, LAPTOP_EXEC_MOUNT_CLASS:$mclass}}'
  else
    jq -n --arg ctx "$ctx" --arg pid "$pid" --arg ws "$ws" --arg mclass "$mount_class" \
      '{additional_context:$ctx, env:{LAPTOP_EXEC_WORKSPACE:$ws, LAPTOP_EXEC_PROJECT:$pid, LAPTOP_EXEC_MOUNT_CLASS:$mclass}}'
  fi
fi
exit 0
