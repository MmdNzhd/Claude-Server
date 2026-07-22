#!/usr/bin/env bash
# laptop-exec-guard - SSH-first: block SSHFS-heavy tools on real /mounts/ targets only.
# Do NOT scan the whole hook JSON (workspace_roots always contain /mounts/ and caused
# false denies on every Read/Grep/Shell).
# Fail OPEN on parse/runtime errors (non-zero exit without JSON looks like a mysterious reject).
set -uo pipefail
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
    "hint=Expected SSH-first deny. Agent must run NEXT: laptop-exec -p PROJECT — do NOT retry the blocked tool."
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

_shell_should_block() {
  local cmd="$1" cwd="$2"
  _is_heavy_shell "$cmd" || return 1
  # Heavy + explicit /mounts/ in command => always block (no /tmp escape bypass).
  if _touches_mounts "$cmd"; then
    return 0
  fi
  # Heavy while cwd is under mounts: allow only pure /tmp (or non-mount /home) ops.
  if _touches_mounts "$cwd"; then
    if _cmd_has_non_mount_abs "$cmd"; then
      return 1
    fi
    return 0
  fi
  return 1
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
  # Shell: evaluate command heaviness; ignore working_directory-as-path false positive.
  if [[ "$tool" == Shell ]]; then
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)
    cwd=$(printf '%s' "$input" | jq -r '.tool_input.working_directory // .cwd // empty' 2>/dev/null || true)
    _shell_should_block "$cmd" "$cwd" && return 0
    return 1
  fi
  paths=$(_tool_path_blob)
  if [[ -n "${paths}" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      _touches_mounts "$p" && return 0
    done <<< "$paths"
    return 1
  fi
  case "$tool" in
    Grep|Glob|Read|Write|Edit|EditNotebook|StrReplace|Delete)
      _workspace_touches_mounts && return 0
      ;;
    Task)
      # Multi-agent: NEVER block Task spawn. explore/shell used to be denied and
      # parents cascaded into many failing subagents. Individual Read/Grep/Shell
      # denies + NEXT remap guide each subagent instead.
      return 1
      ;;
  esac
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

_remap_hint() {
  local tool="$1"
  local pid rel paths p first_path=""
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
  case "$tool" in
    Read)
      if [[ -n "$rel" ]]; then
        printf 'NEXT (do not retry Read): laptop-exec read%s %s' "$pflag" "$rel"
      else
        printf 'NEXT (do not retry Read): laptop-exec read%s REL' "$pflag"
      fi
      ;;
    Write|Edit|StrReplace|Delete)
      if [[ -n "$rel" ]]; then
        printf 'NEXT (do not retry %s): laptop-exec write%s %s  <<EOF ... EOF' "$tool" "$pflag" "$rel"
      else
        printf 'NEXT (do not retry %s): laptop-exec write%s REL <<EOF ... EOF' "$tool" "$pflag"
      fi
      ;;
    Grep|Glob)
      printf 'NEXT (do not retry %s): laptop-exec rg%s PATTERN [pathspec]' "$tool" "$pflag"
      ;;
    Shell)
      printf 'NEXT (do not retry heavy shell on mounts): laptop-exec git|rg|run|read%s ...' "$pflag"
      ;;
    Task)
      printf 'NEXT: Task spawn allowed; each child MUST use laptop-exec -p ID. Do not retry Read/Grep/Shell on /mounts/.'
      ;;
    *)
      printf 'NEXT: use laptop-exec%s (read|rg|write|git|run)' "$pflag"
      ;;
  esac
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
        "SSH-first BLOCKED shell on /mounts/ (expected). Do NOT retry the same shell. $hint" \
        "Use laptop-exec. Do not retry."
    fi
    if [[ "$cmd" == *"laptop-exec"* ]]; then
      _le_audit_log INFO HOOK_SHELL_LAPTOP_EXEC "cwd=$(_le_audit_trunc "$cwd" 200)" \
        "cmd=$(_le_audit_trunc "$cmd" 400)" "project=$(_guess_project_id Shell 2>/dev/null || echo '?')" \
        "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8"
    elif _touches_mounts "$cwd"; then
      _le_audit_log INFO HOOK_SHELL_ALLOW_ON_MOUNTS "reason=light_or_non_heavy" \
        "cwd=$(_le_audit_trunc "$cwd" 200)" "cmd=$(_le_audit_trunc "$cmd" 300)" \
        "project=$(_guess_project_id Shell 2>/dev/null || echo '?')" \
        "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8"
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
          _allow_msg "Task spawn OK. Child prompt MUST paste SSH-first block (laptop-exec -p ID; no Read/Grep on /mounts/; no rg -i/-l/--glob; ≤4 parallel). See laptop-exec skill."
        fi
        if _tool_targets_mounts "$tool"; then
          hint=$(_remap_hint "$tool")
          _deny \
            "SSH-first BLOCKED $tool on /mounts/ (expected). Do NOT retry $tool. $hint" \
            "SSH-first: use laptop-exec instead of $tool. Do not retry."
        fi
        ;;
    esac
    _allow ;;
  *) _allow ;;
esac
