#!/usr/bin/env bash
# sessionStart: inject hard SSH-first + multi-agent rules (deny-storm prevention).
set -uo pipefail
input=$(cat || true)
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

base='SSH-FIRST HARD STOP: Never call Cursor Read/Grep/Glob/Write/Edit/StrReplace/Delete on ~/mounts/. Hook deny is expected — do NOT retry. First I/O = Shell + laptop-exec (read|rg|write|git|run). Flag orders OK: laptop-exec -p ID read REL  OR  laptop-exec read -p ID REL. Paths are laptop repo-relative (never /home/.../mounts/...).'

multi='MULTI-AGENT: Task spawn is allowed. EVERY subagent prompt MUST require laptop-exec only (-p ID; no Read/Grep/Shell on /mounts/). Parent must pass -p and laptop-exec-only rules in the Task prompt. Parallel agents share one SSH mux (max ~8 concurrent laptop-exec); queue is OK — never spam new connections. If a tool is denied, run the NEXT: laptop-exec command immediately.'

if [[ -z "$pid" ]]; then
  ctx="$base $multi Tunnel DOWN => stop; tell user to run connect.bat/sh."
  jq -n --arg ctx "$ctx" '{additional_context:$ctx}'
else
  ctx="$base Project=${pid}. Examples: laptop-exec read -p ${pid} REL | laptop-exec rg -p ${pid} PATTERN | laptop-exec write -p ${pid} REL | laptop-exec git -p ${pid} -- status. $multi"
  ws="/home/${user}/mounts/${pid}"
  jq -n --arg ctx "$ctx" --arg pid "$pid" --arg ws "$ws" \
    '{additional_context:$ctx, env:{LAPTOP_EXEC_WORKSPACE:$ws, LAPTOP_EXEC_PROJECT:$pid}}'
fi
exit 0
