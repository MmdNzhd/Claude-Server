#!/usr/bin/env bash
# laptop-exec-setup - ensure laptop-exec CLI + Cursor rule/skill for user and projects.
# Idempotent; safe to run on every login and every mount.
#
# Usage:
#   laptop-exec-setup              # user + all ~/mounts/* projects
#   laptop-exec-setup --user       # ~/.local/bin, ~/.cursor/rules, ~/.cursor/skills only
#   laptop-exec-setup --project PATH   # one mount path (e.g. ~/mounts/myapp)

set -euo pipefail

GOLDEN_RULE="/usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc"
GOLDEN_SKILL="/usr/local/lib/claude-server/skills/laptop-exec/SKILL.md"
GOLDEN_BIN="/usr/local/bin/laptop-exec"
GOLDEN_HOOKS="/usr/local/lib/claude-server/cursor-hooks"
HOOK_GUARD="laptop-exec-guard.sh"
HOOK_CMD_USER="./hooks/laptop-exec-guard.sh"
HOOK_CMD_PROJECT=".cursor/hooks/laptop-exec-guard.sh"


_merge_hooks_json() {
    local target="$1" golden="$2" hook_cmd="$3"
    [ -f "$golden" ] || return 0
    command -v jq >/dev/null 2>&1 || {
        [ ! -f "$target" ] && install -m 644 "$golden" "$target"
        return 0
    }
    if [ ! -f "$target" ]; then
        install -m 644 "$golden" "$target"
        return 0
    fi
    local tmp merged
    tmp=$(mktemp)
    merged=$(mktemp)
    jq --arg cmd "$hook_cmd" '
        .version //= 1 |
        .hooks.beforeShellExecution //= [] |
        .hooks.preToolUse //= [] |
        if ([.hooks.beforeShellExecution[]? | select(.command == $cmd)] | length) == 0 then
            .hooks.beforeShellExecution += [{"command": $cmd}]
        else . end |
        if ([.hooks.preToolUse[]? | select(.command == $cmd)] | length) == 0 then
            .hooks.preToolUse += [{"command": $cmd, "matcher": "Grep|Glob|Shell"}]
        else . end
    ' "$target" > "$merged"
    install -m 644 "$merged" "$target"
    rm -f "$tmp" "$merged"
}

_ensure_user_hooks() {
    [ -d "$GOLDEN_HOOKS" ] || return 0
    mkdir -p "$HOME/.cursor/hooks"
    # install.sh may leave ~/.cursor owned by root; hooks must be user-writable.
    if [ -d "$HOME/.cursor" ] && [ ! -w "$HOME/.cursor" ]; then
        chown -R "$(id -un):$(id -gn)" "$HOME/.cursor" 2>/dev/null || true
    fi
    if [ -f "$GOLDEN_HOOKS/$HOOK_GUARD" ]; then
        if [ ! -f "$HOME/.cursor/hooks/$HOOK_GUARD" ] || [ "$GOLDEN_HOOKS/$HOOK_GUARD" -nt "$HOME/.cursor/hooks/$HOOK_GUARD" ]; then
            install -m 755 "$GOLDEN_HOOKS/$HOOK_GUARD" "$HOME/.cursor/hooks/$HOOK_GUARD"
        fi
    fi
    if [ -f "$GOLDEN_HOOKS/hooks-user.json" ]; then
        _merge_hooks_json "$HOME/.cursor/hooks.json" "$GOLDEN_HOOKS/hooks-user.json" "$HOOK_CMD_USER"
    fi
}

_ensure_project_hooks() {
    local lpath="$1"
    [ -d "$GOLDEN_HOOKS" ] || return 0
    [ -n "$lpath" ] || return 0
    [ -d "$lpath" ] || return 0
    mkdir -p "$lpath/.cursor/hooks"
    if [ -f "$GOLDEN_HOOKS/$HOOK_GUARD" ]; then
        if [ ! -f "$lpath/.cursor/hooks/$HOOK_GUARD" ] || [ "$GOLDEN_HOOKS/$HOOK_GUARD" -nt "$lpath/.cursor/hooks/$HOOK_GUARD" ]; then
            install -m 644 "$GOLDEN_HOOKS/$HOOK_GUARD" "$lpath/.cursor/hooks/$HOOK_GUARD" 2>/dev/null ||             install -m 755 "$GOLDEN_HOOKS/$HOOK_GUARD" "$lpath/.cursor/hooks/$HOOK_GUARD"
        fi
    fi
    if [ -f "$GOLDEN_HOOKS/hooks-project.json" ]; then
        _merge_hooks_json "$lpath/.cursor/hooks.json" "$GOLDEN_HOOKS/hooks-project.json" "$HOOK_CMD_PROJECT"
    fi
}

_ensure_user() {
    [ -f "$GOLDEN_BIN" ] || return 0
    mkdir -p "$HOME/.local/bin" "$HOME/.cursor/rules" "$HOME/.cursor/skills/laptop-exec"
    if [ ! -f "$HOME/.local/bin/laptop-exec" ] || [ "$GOLDEN_BIN" -nt "$HOME/.local/bin/laptop-exec" ]; then
        install -m 755 "$GOLDEN_BIN" "$HOME/.local/bin/laptop-exec"
    fi
    if [ -f "$GOLDEN_RULE" ]; then
        if [ ! -f "$HOME/.cursor/rules/laptop-exec.mdc" ] || [ "$GOLDEN_RULE" -nt "$HOME/.cursor/rules/laptop-exec.mdc" ]; then
            install -m 644 "$GOLDEN_RULE" "$HOME/.cursor/rules/laptop-exec.mdc"
        fi
    fi
    if [ -f "$GOLDEN_SKILL" ]; then
        if [ ! -f "$HOME/.cursor/skills/laptop-exec/SKILL.md" ] || [ "$GOLDEN_SKILL" -nt "$HOME/.cursor/skills/laptop-exec/SKILL.md" ]; then
            install -m 644 "$GOLDEN_SKILL" "$HOME/.cursor/skills/laptop-exec/SKILL.md"
        fi
    fi
    _ensure_user_hooks
}

_ensure_project() {
    local lpath="$1"
    [ -n "$lpath" ] || return 0
    [ -d "$lpath" ] || return 0
    [ -f "$GOLDEN_RULE" ] || return 0
    mkdir -p "$lpath/.cursor/rules"
    if [ ! -f "$lpath/.cursor/rules/laptop-exec.mdc" ] || [ "$GOLDEN_RULE" -nt "$lpath/.cursor/rules/laptop-exec.mdc" ]; then
        install -m 644 "$GOLDEN_RULE" "$lpath/.cursor/rules/laptop-exec.mdc"
    fi
    _ensure_project_hooks "$lpath"
}

_ensure_all_mounts() {
    local d require_mount="${1:-1}"
    [ -d "$HOME/mounts" ] || return 0
    for d in "$HOME/mounts"/*/; do
        [ -d "$d" ] || continue
        if [ "$require_mount" = "1" ]; then
            mountpoint -q "$d" 2>/dev/null || continue
        fi
        _ensure_project "$d"
    done
}

case "${1:-}" in
    --user)
        _ensure_user
        ;;
    --project)
        _ensure_project "${2:-}"
        ;;
    --all-projects)
        _ensure_all_project_dirs() { _ensure_all_mounts 0; }
        _ensure_all_project_dirs
        ;;
    -h|--help)
        echo "Usage: laptop-exec-setup [--user | --project PATH | --all-projects]"
        ;;
    *)
        _ensure_user
        _ensure_all_mounts 1
        ;;
esac
