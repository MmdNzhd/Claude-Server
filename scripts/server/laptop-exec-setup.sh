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
}

_ensure_all_mounts() {
    local d
    [ -d "$HOME/mounts" ] || return 0
    for d in "$HOME/mounts"/*/; do
        [ -d "$d" ] || continue
        mountpoint -q "$d" 2>/dev/null || continue
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
    -h|--help)
        echo "Usage: laptop-exec-setup [--user | --project PATH]"
        ;;
    *)
        _ensure_user
        _ensure_all_mounts
        ;;
esac
