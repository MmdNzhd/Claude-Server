#!/usr/bin/env bash
# laptop-exec-guard — Cursor hook: block slow SSHFS scan/git/build; force laptop-exec.
# Events: beforeShellExecution, preToolUse (Grep|Glob|Shell)
set -euo pipefail

input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // empty')

_allow() {
    echo '{"permission":"allow"}'
    exit 0
}

_deny() {
    local agent_msg="$1"
    local user_msg="${2:-SSHFS fast path: use laptop-exec instead of direct commands on /mounts/}"
    jq -n \
        --arg permission "deny" \
        --arg agent_message "$agent_msg" \
        --arg user_message "$user_msg" \
        '{permission: $permission, agent_message: $agent_message, user_message: $user_message}'
    exit 0
}

_touches_mounts() {
    local text="$1"
    [[ "$text" == *"/mounts/"* ]] || [[ "$text" == *"~/mounts"* ]] || [[ "$text" == *'$HOME/mounts'* ]]
}

_is_heavy_shell() {
    local cmd="$1"
    [[ "$cmd" =~ (^|[[:space:]|&;])(git|find|rg|grep|dotnet|npm|yarn|pnpm|cargo|make|cmake|mvn|gradle|go[[:space:]]+(build|test|run)|python[[:space:]]+-m[[:space:]]+(pytest|unittest)|pytest|jest|vitest|tsc|webpack|vite[[:space:]]+build)([[:space:]]|$|/) ]]
}

case "$event" in
    beforeShellExecution)
        cmd=$(echo "$input" | jq -r '.command // empty')
        ctx=$(echo "$input" | jq -r '[.cwd, (.workspace_roots // [])[]] | join(" ")')
        [[ -n "$cmd" ]] || _allow
        [[ "$cmd" == *"laptop-exec"* ]] && _allow
        if { _touches_mounts "$cmd" || _touches_mounts "$ctx"; } && _is_heavy_shell "$cmd"; then
            _deny \
                "BLOCKED: Do not run heavy commands on SSHFS /mounts/ paths. Use laptop-exec instead. Examples: laptop-exec git -- status | laptop-exec rg PATTERN | laptop-exec run -- dotnet build. Run laptop-exec status first." \
                "Agent tried a slow SSHFS command — use laptop-exec (tunnel SSH to laptop)."
        fi
        _allow
        ;;

    preToolUse)
        blob=$(echo "$input" | jq -c '.')
        tool=$(echo "$input" | jq -r '.tool_name // .tool // .toolName // empty')
        if _touches_mounts "$blob"; then
            case "$tool" in
                Grep|Glob|Task)
                    if [[ "$tool" == "Task" ]]; then
                        subagent=$(echo "$input" | jq -r '.tool_input.subagent_type // .input.subagent_type // empty')
                        [[ "$subagent" == "explore" || "$subagent" == "shell" ]] || _allow
                    fi
                    _deny \
                        "BLOCKED: Do not use $tool on SSHFS paths under /mounts/. Use laptop-exec instead: laptop-exec rg PATTERN | laptop-exec git -- status | laptop-exec run -- dotnet build. Single-file Read/Write on /mounts/ is OK."
                    ;;
            esac
        fi
        _allow
        ;;

    *)
        _allow
        ;;
esac
