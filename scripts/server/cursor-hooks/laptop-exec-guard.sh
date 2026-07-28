#!/usr/bin/env bash
# laptop-exec-guard - ALLOW Read/Grep/Glob/Write/Edit/Shell on /mounts/
# (rules: Read/Grep mount-first; Write MCP-first; Glob MCP search; max parallel).
# Writes (Write/Edit/StrReplace/Delete/EditNotebook) and Shell on /mounts/ are ALLOWED.
# Do NOT scan the whole hook JSON (workspace_roots always contain /mounts/ and caused
# false denies on every Read/Grep/Shell).
# Fail OPEN on parse/runtime errors (non-zero exit without JSON looks like a mysterious reject).
set -uo pipefail
# Shell-hook hot path: skip 8-slot flock probes in audit breadcrumbs.
: "${LAPTOP_EXEC_AUDIT_FAST:=1}"
# Last-resort fail-open: never exit 2 from this script (Cursor treats 2 as deny).
trap '_allow' ERR
input=$(cat || true)

# Durable multi-agent audit (same sink as laptop-exec CLI).
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

_allow() {
  echo '{"permission":"allow"}'
  exit 0
}
_allow_msg() {
  local msg="$1"
  _le_audit_log INFO HOOK_ALLOW_MSG "msg=$(_le_audit_trunc "$msg" 300)" \
    "event=${event:-?}" "tool=${tool:-?}" "$(_le_audit_session_fields)" \
    "slots_busy=$(_le_audit_slots_busy)/8"
  jq -n --arg permission allow --arg agent_message "$msg" \
    '{permission:$permission, agent_message:$agent_message}' \
    || echo '{"permission":"allow"}'
  exit 0
}
_deny() {
  local agent_msg="$1" user_msg="${2:-SSH-first: use laptop-exec}"
  local _cmd="" _cwd="" _paths="" _pid="" _tool="${tool:-Shell}"
  _cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)
  _cwd=$(printf '%s' "$input" | jq -r '.tool_input.working_directory // .cwd // empty' 2>/dev/null || true)
  if declare -F _tool_path_blob >/dev/null 2>&1; then
    _paths=$(_tool_path_blob 2>/dev/null | tr '\n' ',' || true)
  fi
  if declare -F _guess_project_id >/dev/null 2>&1; then
    _pid=$(_guess_project_id "$_tool" 2>/dev/null || true)
  fi
  _le_audit_log ERROR HOOK_DENY "tool=${_tool}" "hook_event=${event:-?}" \
    "project=${_pid:-?}" "cwd=$(_le_audit_trunc "${_cwd:-}" 200)" \
    "paths=$(_le_audit_trunc "${_paths:-}" 300)" \
    "cmd=$(_le_audit_trunc "${_cmd:-}" 400)" \
    "agent_msg=$(_le_audit_trunc "$agent_msg" 400)" \
    "user_msg=$(_le_audit_trunc "$user_msg" 200)" \
    "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8" \
    "hint=Expected rare deny. Run NEXT: (hybrid: Read/Grep=mount; Write/Glob=MCP when listed; git=LE). Do NOT retry the blocked tool."
  jq -n --arg permission deny --arg agent_message "$agent_msg" --arg user_message "$user_msg" \
    '{permission:$permission,agent_message:$agent_message,user_message:$user_message}' 2>/dev/null \
    || echo '{"permission":"deny","agent_message":"SSH-first blocked","user_message":"Use laptop-exec"}'
  exit 0
}

command -v jq >/dev/null 2>&1 || _allow
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null) || _allow
[[ -n "$input" ]] || _allow


_touches_mounts() {
  local text="$1"
  [[ -n "$text" ]] || return 1
  [[ "$text" == *"/mounts/"* ]] || [[ "$text" == *"~/mounts/"* ]] || [[ "$text" == *"~/mounts" ]] \
    || [[ "$text" == *'$HOME/mounts/'* ]] || [[ "$text" == *'$HOME/mounts'* ]]
}

_shell_scan_text() {
  local cmd="$1" scan="" scanner
  # Fast path (multi-agent): no heredoc/quotes → skip python (~90ms/spawn).
  if [[ "$cmd" != *'<<'* && "$cmd" != *"'"* && "$cmd" != *'"'* ]]; then
    scan=$(printf '%s' "$cmd" | sed -E 's/\|[[:space:]]*(head|tail|wc)([[:space:]]+-[a-zA-Z0-9]+|[[:space:]]+[0-9]+)*//g')
    printf '%s' "$scan"
    return 0
  fi
  scanner="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd)/laptop-exec-shell-scan.py"
  if [[ ! -f "$scanner" ]]; then
    scanner="${HOME}/.cursor/hooks/laptop-exec-shell-scan.py"
  fi
  if [[ -f "$scanner" ]]; then
    scan=$(printf '%s' "$cmd" | python3 "$scanner" 2>/dev/null) || scan="$cmd"
    printf '%s' "$scan"
    return 0
  fi
  printf '%s' "$cmd"
}


_is_heavy_shell() {
  local cmd="$1" scan first
  [[ "$cmd" == *"laptop-exec"* ]] && return 1
  scan="$(_shell_scan_text "$cmd")"
  first=$(printf '%s\n' "$scan" | awk 'NF { print $1; exit }')
  case "$first" in
    python|python2|python3|node|nodejs|ruby|perl|python3.*)
      [[ "$scan" =~ (^|[[:space:]\&\;\|]|/)python[0-9.]*[[:space:]]+-m[[:space:]]+(pytest|unittest)([[:space:]]|$|/) ]] && return 0
      return 1
      ;;
  esac
  # Match tool at start, after shell ops, OR after path slash (/usr/bin/git, /bin/cat).
  # Not matched: head/tail/wc (pipeline filters).
  [[ "$scan" =~ (^|[[:space:]\&\;\|]|/)(git|find|rg|grep|dotnet|npm|npx|yarn|pnpm|bun|deno|cargo|make|cmake|mvn|gradle|go[[:space:]]+(build|test|run)|python[[:space:]]+-m[[:space:]]+(pytest|unittest)|pytest|jest|vitest|tsc|webpack|vite[[:space:]]+build|cat|sed|awk|head|tail|wc|ls[[:space:]]+-R)([[:space:]]|$|/) ]]
}

_cmd_has_non_mount_abs() {
  local cmd="$1" scan
  # Escape only when heavy I/O is CLEARLY aimed at /tmp or non-mount /home.
  # Substring tricks like: git status && echo /tmp  OR  cat README && ls /home/u
  # must NOT escape. Strip shell comments first.
  cmd="${cmd%%#*}"
  scan="$(_shell_scan_text "$cmd")"
  # git -C /tmp ...
  [[ "$scan" =~ git[[:space:]]+-C[[:space:]]+/tmp(/|[[:space:]]|$) ]] && return 0
  # tool /tmp/... or tool /home/user/... (not .../mounts/...)
  if [[ "$scan" =~ (^|[[:space:]\&\;\|]|/)(cat|sed|awk|find|rg|grep|git|npm|dotnet)[[:space:]]+/tmp(/|[[:space:]]|$) ]]; then
    return 0
  fi
  if [[ "$scan" =~ (^|[[:space:]\&\;\|]|/)(cat|sed|awk|find|rg|grep)[[:space:]]+/home/[^[:space:]]+ ]]; then
    local m
    m=$(printf '%s' "$scan" | grep -oE '/home/[^[:space:]]+' | head -1 || true)
    if [[ -n "$m" ]] && ! _touches_mounts "$m"; then
      return 0
    fi
  fi
  return 1
}

_guard_mount_class() {
  # Probe like session: not in /proc => NOT_LIVE; in /proc but ls I/O fail => STALE; else MOUNTED.
  # Also emit NOT_MOUNTED when path empty (mapped near shell deny allow-path).
  local mp="$1" out="" rc=0
  [[ -n "$mp" ]] || { printf 'NOT_MOUNTED'; return; }
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

# Resolve project id for LE routing: -p/--project in cmd, else cwd /mounts/ID, else ACTIVE_MOUNT.
_shell_le_project_id() {
  local cmd="$1" cwd="$2" pid="" conf="${HOME}/.claude-connect.conf" am=""
  if [[ "$cmd" =~ (^|[[:space:];|&])laptop-exec([[:space:]]+[^;|&]*) ]]; then
    local le_tail="${BASH_REMATCH[2]:-}"
    if [[ "$le_tail" =~ (^|[[:space:]])-p[[:space:]]+([^[:space:]]+) ]]; then
      printf '%s' "${BASH_REMATCH[2]}"
      return 0
    fi
    if [[ "$le_tail" =~ (^|[[:space:]])--project(=|[[:space:]]+)([^[:space:]]+) ]]; then
      printf '%s' "${BASH_REMATCH[3]}"
      return 0
    fi
  fi
  if [[ "$cwd" =~ /mounts/([^/[:space:]]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ -f "$conf" ]]; then
    am=$(grep -E '^(ACTIVE_MOUNT|active_mount)=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d '\r' || true)
    [[ -n "$am" ]] && { printf '%s' "$am"; return 0; }
  fi
  return 1
}

# True when command invokes laptop-exec with verb read or rg (not git/run/write/status/...).
_cmd_is_le_read_or_rg() {
  local cmd="$1" scan="" line="" rest="" tok="" skip_next=0 first=""
  # Strip shell comments to reduce false positives on "laptop-exec read" in notes.
  cmd="${cmd%%#*}"
  [[ "$cmd" == *"laptop-exec"* ]] || return 1
  scan="$(_shell_scan_text "$cmd" 2>/dev/null || printf '%s' "$cmd")"
  # Split into simple-command segments so "echo laptop-exec read" does not match.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    rest="$line"
    # Drop leading env assignments (FOO=1 BAR=2 laptop-exec ...).
    while [[ "$rest" =~ ^[[:space:]]*[[:alnum:]_]+=[^[:space:]]+[[:space:]]+(.*)$ ]]; do
      rest="${BASH_REMATCH[1]}"
    done
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ -z "$rest" ]] && continue
    first="${rest%%[[:space:]]*}"
    case "$first" in
      laptop-exec|*/laptop-exec) ;;
      *) continue ;;
    esac
    # Token walk after the laptop-exec command token.
    skip_next=0
    # shellcheck disable=SC2086
    set -- $rest
    shift || true  # drop laptop-exec
    for tok in "$@"; do
      if [[ "$skip_next" -eq 1 ]]; then
        skip_next=0
        continue
      fi
      case "$tok" in
        -p|--project)
          skip_next=1
          continue
          ;;
        --project=*)
          continue
          ;;
        -*)
          continue
          ;;
        read|rg)
          return 0
          ;;
        git|run|write|status|health|list|test|help|mount-status)
          break
          ;;
        *)
          break
          ;;
      esac
    done
  done < <(printf '%s\n' "$scan" | sed -E 's/&&|\|\||[;|&]/\n/g')
  return 1
}

_shell_should_block() {
  local cmd="$1" cwd="$2"
  local pid="" mp="" mclass=""
  # Kill-switch: LAPTOP_EXEC_DENY_OFF=1 or LAPTOP_EXEC_ALLOW_LE_READ=1 → do not block.
  if [[ "${LAPTOP_EXEC_DENY_OFF:-}" == "1" ]] || [[ "${LAPTOP_EXEC_ALLOW_LE_READ:-}" == "1" ]]; then
    return 1
  fi
  # Conditional deny: laptop-exec read|rg only when mount class is MOUNTED.
  # Allow LE read/rg on STALE / NOT_LIVE / NOT_MOUNTED. Fail-open on parse errors.
  _cmd_is_le_read_or_rg "$cmd" || return 1
  pid=$(_shell_le_project_id "$cmd" "$cwd" 2>/dev/null) || true
  [[ -n "$pid" ]] || return 1
  mp="${HOME}/mounts/${pid}"
  mclass=$(_guard_mount_class "$mp" 2>/dev/null) || mclass="NOT_LIVE"
  case "$mclass" in
    MOUNTED)
      _LE_ROUTING_DENY_PID="$pid"
      _LE_ROUTING_DENY_CLASS="MOUNTED"
      _LE_ROUTING_DENY_MP="$mp"
      _le_audit_log WARN ROUTING_DENY \
        "project=${pid}" "mount_class=MOUNTED" "mount=$(_le_audit_trunc "$mp" 200)" \
        "cmd=$(_le_audit_trunc "$cmd" 400)" \
        "$(_le_audit_session_fields)" "slots_busy=?" \
        "hint=LE_READ_DENIED NEXT use Cursor Read/Grep on mount; LE read/rg only when STALE/NOT_LIVE"
      return 0
      ;;
    STALE|NOT_LIVE|NOT_MOUNTED)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# File targets only - NOT working_directory (that is cwd for Shell and would false-deny echo).
_tool_path_blob() {
  printf '%s' "$input" | jq -r '
    [
      .tool_input.path // empty,
      .tool_input.target_directory // empty,
      .tool_input.file_path // empty,
      .tool_input.target_notebook // empty,
      .input.target_notebook // empty,
      .input.path // empty,
      .input.target_directory // empty,
      .input.file_path // empty,
      (.tool_input.paths // [])[],
      (.input.paths // [])[]
    ] | map(select(type=="string" and . != "")) | unique | .[]
  ' 2>/dev/null || true
}

_workspace_touches_mounts() {
  local roots cwd
  roots=$(printf '%s' "$input" | jq -r '(.workspace_roots // []) | map(tostring) | join("\n")' 2>/dev/null || true)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
  _touches_mounts "$roots" || _touches_mounts "$cwd"
}

_tool_targets_mounts() {
  local tool="$1"
  local paths p prompt sub cmd cwd
  # Policy: ALL file tools ALLOWED on /mounts/ (Read/Grep/Glob/Write/Edit/Shell).
  # Prefer mount Read/Grep; MCP Write/Glob in rules/session (not enforced by deny).
  case "$tool" in
    # ALLOW — Grep/Glob same as Read.
    Read|Write|Edit|EditNotebook|StrReplace|Delete|Grep|Glob)
      return 1
      ;;
    Shell)
      return 1
      ;;
    Task)
      # Multi-agent: NEVER block Task spawn.
      return 1
      ;;
  esac
  # No path-based deny for remaining tools targeting mounts (fail-open).
  return 1
}


# Infer project id + repo-relative path from any /mounts/ID/... string.
_infer_project_from_text() {
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

_infer_rel_from_path() {
  local path="$1"
  if [[ "$path" =~ /mounts/[^/]+/(.+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

_guess_project_id() {
  local tool="$1" blob pid="" roots cwd paths p
  paths=$(_tool_path_blob)
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    pid=$(_infer_project_from_text "$p" 2>/dev/null) && { printf '%s' "$pid"; return 0; }
  done <<< "${paths:-}"
  roots=$(printf '%s' "$input" | jq -r '(.workspace_roots // []) | map(tostring) | join("\n")' 2>/dev/null || true)
  pid=$(_infer_project_from_text "$roots" 2>/dev/null) && { printf '%s' "$pid"; return 0; }
  cwd=$(printf '%s' "$input" | jq -r '.cwd // .tool_input.working_directory // empty' 2>/dev/null || true)
  pid=$(_infer_project_from_text "$cwd" 2>/dev/null) && { printf '%s' "$pid"; return 0; }
  if [[ "$tool" == Shell ]]; then
    local cmd
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)
    pid=$(_infer_project_from_text "$cmd" 2>/dev/null) && { printf '%s' "$pid"; return 0; }
  fi
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

_remote_path_for() {
  local pid="$1" conf="${HOME}/.claude-mounts.d/${pid}.conf" line v
  [[ -n "$pid" && -f "$conf" ]] || return 1
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

# Join Windows project root + repo-relative path -> absolute Windows path for MCP.
_win_abs_path() {
  local root="$1" rel="$2"
  [[ -n "$root" && -n "$rel" ]] || return 1
  # Normalize separators to Windows backslash (REMOTE_PATH may use D:/...).
  root="${root//\//\\}"
  root="${root%\\}"
  rel="${rel#/}"
  rel="${rel#\\}"
  rel="${rel//\//\\}"
  printf '%s\\%s' "$root" "$rel"
}

_remap_hint() {
  local tool="$1"
  local pid rel paths p first_path="" rpath="" wabs="" hybrid=0
  pid=$(_guess_project_id "$tool" 2>/dev/null || true)
  paths=$(_tool_path_blob)
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    first_path="$p"
    break
  done <<< "${paths:-}"
  rel=""
  [[ -n "$first_path" ]] && rel=$(_infer_rel_from_path "$first_path" 2>/dev/null || true)
  local pflag=""
  [[ -n "$pid" ]] && pflag=" -p $pid"
  if _windows_hybrid_ready; then
    hybrid=1
    [[ -n "$pid" ]] && rpath=$(_remote_path_for "$pid" 2>/dev/null || true)
    if [[ -n "$rpath" && -n "$rel" ]]; then
      wabs=$(_win_abs_path "$rpath" "$rel" 2>/dev/null || true)
    fi
  fi
  # FAIL-FAST suffix: hybrid env ≠ live tools; stop Read/MCP retry storms (seen in logs).
  local ff=' FAIL-FAST: if windows-mcp tools not listed OR one MCP call fails (ECONNREFUSED/fetch failed): use mount + laptop-exec; never retry same MCP call. user-filesystem≠windows-mcp.'
  case "$tool" in
    Read)
      if [[ "$hybrid" -eq 1 ]]; then
        if [[ -n "$wabs" ]]; then
          printf 'NEXT (do not retry Read): prefer Cursor Read on /mounts/ (~16-32 parallel). Else MCP FileSystem "%s" (~8-12). Else laptop-exec read%s %s.%s' "$wabs" "$pflag" "$rel" "$ff"
        elif [[ -n "$rpath" ]]; then
          printf 'NEXT (do not retry Read): prefer Cursor Read on /mounts/ (~16-32). Else MCP FileSystem under %s + REL (~8-12). Else laptop-exec read%s REL.%s' "$rpath" "$pflag" "$ff"
        else
          printf 'NEXT (do not retry Read): prefer Cursor Read on /mounts/ (~16-32). Else MCP FileSystem absolute Windows (~8-12). Else laptop-exec read%s REL.%s' "$pflag" "$ff"
        fi
      elif [[ -n "$rel" ]]; then
        printf 'NEXT (do not retry Read): Cursor Read on /mounts/ or laptop-exec read%s %s' "$pflag" "$rel"
      else
        printf 'NEXT (do not retry Read): Cursor Read on /mounts/ or laptop-exec read%s REL' "$pflag"
      fi
      ;;
    Write|Edit|StrReplace|Delete|EditNotebook)
      if [[ "$hybrid" -eq 1 ]]; then
        if [[ -n "$wabs" ]]; then
          printf 'NEXT (do not retry %s): prefer MCP FileSystem write "%s" (~8-10). Else mount Write/Edit (~10). Else laptop-exec write%s %s.%s' "$tool" "$wabs" "$pflag" "$rel" "$ff"
        elif [[ -n "$rpath" ]]; then
          printf 'NEXT (do not retry %s): prefer MCP FileSystem write under %s + REL (~8-10). Else mount (~10). Else laptop-exec write%s REL.%s' "$tool" "$rpath" "$pflag" "$ff"
        else
          printf 'NEXT (do not retry %s): prefer MCP FileSystem write (~8-10). Else mount (~10). Else laptop-exec write%s REL.%s' "$tool" "$pflag" "$ff"
        fi
      elif [[ -n "$rel" ]]; then
        printf 'NEXT (do not retry %s): mount Write/Edit or laptop-exec write%s %s  <<EOF ... EOF' "$tool" "$pflag" "$rel"
      else
        printf 'NEXT (do not retry %s): mount Write/Edit or laptop-exec write%s REL <<EOF ... EOF' "$tool" "$pflag"
      fi
      ;;
      Grep)
        # Content: mount Grep first, then Select-String (MCP), then laptop-exec rg.
        if [[ "$hybrid" -eq 1 ]]; then
          printf 'NEXT (do not retry Grep): prefer Cursor Grep on /mounts/ (~16-32). Else MCP Select-String (~4-8). Else laptop-exec rg%s PATTERN [pathspec] — no -i/-l/-n/-A/-B/-C/-m/--glob/--type/--max-count.' "$pflag"
        else
          printf 'NEXT (do not retry Grep): Cursor Grep on mounts or laptop-exec rg%s PATTERN [pathspec] (no ripgrep flags)' "$pflag"
        fi
        ;;
    Glob)
      if [[ "$hybrid" -eq 1 && -n "$rpath" ]]; then
        printf 'NEXT (do not retry Glob): windows-mcp FileSystem search/list under %s (prefer; ~8-12 parallel). Or Cursor Glob / mount ls. Not content Grep.' "$rpath"
      elif [[ "$hybrid" -eq 1 ]]; then
        printf 'NEXT (do not retry Glob): windows-mcp FileSystem search/list under project Windows root (prefer; ~8-12). Or Cursor Glob / mount ls.'
      else
        printf 'NEXT (do not retry Glob): Cursor Glob on mounts, or mount Shell ls / Get-ChildItem (or laptop-exec run).'
      fi
      ;;
    Shell)
      if [[ "$hybrid" -eq 1 ]]; then
        printf 'NEXT: prefer Cursor Read/Grep on /mounts when healthy (not laptop-exec read/rg). Heavy build/test: windows-mcp PowerShell once, else laptop-exec run|git%s ...%s' "$pflag" "$ff"
      else
        printf 'NEXT: prefer Cursor Read/Grep on /mounts when healthy. Heavy work: laptop-exec run|git%s ...' "$pflag"
      fi
      ;;
    Task)
      if [[ "$hybrid" -eq 1 ]]; then
        printf 'NEXT: Task OK; child MUST paste: HEALTHY MOUNT=>Cursor Read/Grep; READ=mount→MCP→LE; WRITE=MCP→mount→LE; Glob=MCP; git=LE -p ID before subcmd; LE≤4; LE read=one relative file; LF for .sh writes.'
      else
        printf 'NEXT: Task OK; paste HEALTHY MOUNT=>Cursor Read/Grep; READ=mount→MCP→LE; WRITE=MCP→mount→LE; git=LE -p ID; no rg ripgrep flags; LE read=one file.'
      fi
      ;;
    *)
      if [[ "$hybrid" -eq 1 ]]; then
        printf 'NEXT: mount for Read/Grep; MCP for Write/Glob/Shell if listed; else laptop-exec%s; one MCP fail=>mount+LE.%s' "$pflag" "$ff"
      else
        printf 'NEXT: use laptop-exec%s (read|rg|write|git|run)' "$pflag"
      fi
      ;;
  esac
}

_deny_user_msg() {
  local tool="$1"
  if _windows_hybrid_ready; then
    case "$tool" in
      Grep)
        printf 'Prefer Cursor Grep on mounts, else Select-String, else laptop-exec rg. Do not retry denied Grep.'
        ;;
      Glob)
        printf 'Prefer windows-mcp FileSystem search/list, else Cursor Glob on mounts, else ls. Do not retry denied Glob.'
        ;;
      Read)
        printf 'Prefer Cursor Read on mounts, else MCP FileSystem, else laptop-exec read. Do not retry denied Read.'
        ;;
      Write|Edit|StrReplace|Delete|EditNotebook)
        printf 'Prefer MCP FileSystem write, else mount Write/Edit, else laptop-exec write. Do not retry denied %s.' "$tool"
        ;;
      *)
        printf 'Hybrid: mount Read/Grep; MCP Write/Glob/Shell/UI when listed; laptop-exec for git/fallback. Do not retry %s.' "$tool"
        ;;
    esac
  else
    printf 'Use mount tools or laptop-exec instead of %s. Do not retry.' "$tool"
  fi
}


case "$event" in
  beforeShellExecution)
    cmd=$(printf '%s' "$input" | jq -r '.command // empty' 2>/dev/null) || _allow
    cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || _allow
    [[ -n "$cmd" ]] || _allow
    tool=Shell
    if _shell_should_block "$cmd" "$cwd"; then
      hint=$(_remap_hint Shell)
      _deny \
        "ROUTING_DENY LE_READ_DENIED: laptop-exec read/rg blocked while mount MOUNTED (project=${_LE_ROUTING_DENY_PID:-?}). Do NOT retry LE read/rg. NEXT: use Cursor Read/Grep on ${_LE_ROUTING_DENY_MP:-/mounts/<project>}; LE read/rg only when STALE/NOT_LIVE. $hint" \
        "LE_READ_DENIED: prefer Cursor Read/Grep on mount; LE read/rg only when STALE/NOT_LIVE."
    fi
    # Skip slots_busy flock scan on the hot Shell path (~8 lock probes = multi-agent tax).
    if [[ "$cmd" == *"laptop-exec"* ]]; then
      _le_audit_log INFO HOOK_SHELL_LAPTOP_EXEC "cwd=$(_le_audit_trunc "$cwd" 200)" \
        "cmd=$(_le_audit_trunc "$cmd" 400)" "project=$(_guess_project_id Shell 2>/dev/null || echo '?')" \
        "$(_le_audit_session_fields)" "slots_busy=?"
    elif _touches_mounts "$cwd"; then
      _le_audit_log INFO HOOK_SHELL_ALLOW_ON_MOUNTS "reason=light_or_non_heavy" \
        "cwd=$(_le_audit_trunc "$cwd" 200)" "cmd=$(_le_audit_trunc "$cmd" 300)" \
        "project=$(_guess_project_id Shell 2>/dev/null || echo '?')" \
        "$(_le_audit_session_fields)" "slots_busy=?"
    fi
    _allow ;;
  preToolUse)
    tool=$(printf '%s' "$input" | jq -r '.tool_name // .tool // .toolName // empty' 2>/dev/null) || _allow
    case "$tool" in
      Grep|Glob|Read|Write|Edit|EditNotebook|StrReplace|Delete|Task|Shell)
        if [[ "$tool" == Task ]]; then
          # Never block spawn, but remind parent: children need the paste block.
          _tdesc=$(printf '%s' "$input" | jq -r '.tool_input.description // .input.description // empty' 2>/dev/null || true)
          _tsub=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // .input.subagent_type // empty' 2>/dev/null || true)
          _le_audit_log WARN HOOK_TASK_SPAWN "subagent_type=${_tsub:-?}" \
            "description=$(_le_audit_trunc "${_tdesc:-}" 200)" \
            "project=$(_guess_project_id Task 2>/dev/null || echo '?')" \
            "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8" \
            "hint=Child does NOT inherit SSH-first. Prompt MUST paste laptop-exec block. Prefer ≤4 parallel (hard cap 8 slots)."
          _allow_msg "Task spawn OK. Paste: HEALTHY MOUNT=>Cursor Read/Grep only (never LE read/rg first). PRIORITY+FAILOVER READ=mount→MCP→LE; WRITE=MCP→mount→LE; Glob=MCP search/list (FileSystem search≠content Grep); git=LE -p ID before subcommand; parallel mount~16 MCP~8 LE≤4 (hard 8); if 1st down use next same turn; no rg -i/-l/-n/-A/-B/-C/-m/--glob/--type/--max-count; LE read=one relative file (no --offset/--limit); do not MCP-write .sh without LF (CRLF breaks bash)."
        fi
        if _tool_targets_mounts "$tool"; then
          hint=$(_remap_hint "$tool")
          _deny \
            "SSH-first BLOCKED $tool on /mounts/ (expected). Do NOT retry $tool. $hint" \
            "$(_deny_user_msg "$tool")"
        fi
        ;;
    esac
    _allow ;;
  *) _allow ;;
esac
