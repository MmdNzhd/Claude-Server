#!/usr/bin/env bash
# laptop-exec-guard - SSH-first: block SSHFS tools on /mounts/ paths.
set -euo pipefail
input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // empty')
_allow() { echo '{"permission":"allow"}'; exit 0; }
_deny() {
  local agent_msg="$1" user_msg="${2:-SSH-first: use laptop-exec}"
  jq -n --arg permission deny --arg agent_message "$agent_msg" --arg user_message "$user_msg" \
    '{permission:$permission,agent_message:$agent_message,user_message:$user_message}'
  exit 0
}
_touches_mounts() {
  local text="$1"
  [[ "$text" == *"/mounts/"* ]] || [[ "$text" == *"~/mounts"* ]] || [[ "$text" == *'$HOME/mounts'* ]]
}
_is_heavy_shell() {
  local cmd="$1"
  [[ "$cmd" == *"laptop-exec"* ]] && return 1
  [[ "$cmd" =~ (^|[[:space:]|&;])(git|find|rg|grep|dotnet|npm|yarn|pnpm|cargo|make|cmake|mvn|gradle|go[[:space:]]+(build|test|run)|python[[:space:]]+-m[[:space:]]+(pytest|unittest)|pytest|jest|vitest|tsc|webpack|vite[[:space:]]+build|cat|head|tail|sed|awk|wc[[:space:]]+-l|ls[[:space:]]+-R)([[:space:]]|$|/) ]]
}
case "$event" in
  beforeShellExecution)
    cmd=$(echo "$input" | jq -r '.command // empty')
    ctx=$(echo "$input" | jq -r '[.cwd, (.workspace_roots // [])[]] | join(" ")')
    [[ -n "$cmd" ]] || _allow
    if { _touches_mounts "$cmd" || _touches_mounts "$ctx"; } && _is_heavy_shell "$cmd"; then
      _deny \
        "SSH-first BLOCKED shell on /mounts/. Run: laptop-exec status && laptop-exec health. Use laptop-exec read|write|rg|git|run instead. Auto -p from cwd under ~/mounts/PROJECT/." \
        "Use laptop-exec (tunnel SSH) instead of SSHFS shell on /mounts/."
    fi
    _allow ;;
  preToolUse)
    blob=$(echo "$input" | jq -c '.')
    tool=$(echo "$input" | jq -r '.tool_name // .tool // .toolName // empty')
    if _touches_mounts "$blob"; then
      case "$tool" in
        Grep|Glob|Read|Write|Task)
          if [[ "$tool" == Task ]]; then
            sub=$(echo "$input" | jq -r '.tool_input.subagent_type // .input.subagent_type // empty')
            [[ "$sub" == explore || "$sub" == shell ]] || _allow
          fi
          _deny \
            "SSH-first BLOCKED $tool on /mounts/. Run laptop-exec status. Use laptop-exec read (not Read), write (not Write), rg (not Grep). resolve PATH for -p. Mount may be STALE - tunnel still works." \
            "SSH-first: use laptop-exec instead of $tool on /mounts/."
          ;;
      esac
    fi
    _allow ;;
  *) _allow ;;
esac
