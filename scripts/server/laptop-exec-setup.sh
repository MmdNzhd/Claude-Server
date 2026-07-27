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
GOLDEN_SKILL_REF="/usr/local/lib/claude-server/skills/laptop-exec/reference-windows-mcp.md"
GOLDEN_BIN="/usr/local/bin/laptop-exec"
GOLDEN_HEAL="/usr/local/bin/claude-self-heal"
GOLDEN_HOOKS="/usr/local/lib/claude-server/cursor-hooks"
HOOK_GUARD="laptop-exec-guard.sh"
HOOK_WRAP="laptop-exec-guard-wrap.sh"
HOOK_SCAN="laptop-exec-shell-scan.py"
HOOK_SESSION="laptop-exec-session.sh"
HOOK_CMD_USER="$HOME/.cursor/hooks/laptop-exec-guard-wrap.sh"
HOOK_CMD_SESSION="$HOME/.cursor/hooks/laptop-exec-session.sh"
# Prefer user-local guard for project hooks too: SSHFS ~/mounts/PROJECT/.cursor/hooks
# is often STALE or NOT_MOUNTED and used to run an old guard that false-denied everything.
HOOK_CMD_PROJECT="$HOME/.cursor/hooks/laptop-exec-guard-wrap.sh"
HOOK_MATCHER="Grep|Glob|Read|Write|Edit|EditNotebook|StrReplace|Delete|Task"

# atomic_install MODE SRC DST
# Installs SRC to DST via a same-directory temp file + rename so a process already
# executing DST (laptop-exec is invoked constantly; claude-watchdog polls
# claude-mount every 30s and periodically re-runs claude-self-heal) never observes
# a partially-written file.
atomic_install() {
    local mode="$1" src="$2" dst="$3" tmp="${3}.new.$$"
    install -m "$mode" "$src" "$tmp" || return 1
    mv -f "$tmp" "$dst"
}


_merge_hooks_json() {
    local target="$1" golden="$2" hook_cmd="$3" session_cmd="${4:-}"
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
    jq --arg cmd "$hook_cmd" --arg scmd "$session_cmd" --arg matcher "$HOOK_MATCHER" '
        .version //= 1 |
        .hooks.beforeShellExecution //= [] |
        .hooks.preToolUse //= [] |
        .hooks.sessionStart //= [] |
        # Drop legacy raw guard / relative hook paths so wrap is the only shell gate
        .hooks.beforeShellExecution |= map(select(.command | (endswith("laptop-exec-guard-wrap.sh") or (contains("laptop-exec-guard") | not)))) |
        .hooks.preToolUse |= map(select(.command | (endswith("laptop-exec-guard-wrap.sh") or (contains("laptop-exec-guard") | not)))) |
        if ([.hooks.beforeShellExecution[]? | select(.command == $cmd)] | length) == 0 then
            .hooks.beforeShellExecution += [{"command": $cmd}]
        else . end |
        if ([.hooks.preToolUse[]? | select(.command == $cmd)] | length) == 0 then
            .hooks.preToolUse += [{"command": $cmd, "matcher": $matcher}]
        else
            # Force-correct matcher (strip Shell / add EditNotebook) on existing wrap entry
            .hooks.preToolUse |= map(if .command == $cmd then .matcher = $matcher else . end)
        end |
        if ($scmd != "") and (([.hooks.sessionStart[]? | select(.command == $scmd)] | length) == 0) then
            .hooks.sessionStart += [{"command": $scmd}]
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
        install -m 755 "$GOLDEN_HOOKS/$HOOK_GUARD" "$HOME/.cursor/hooks/$HOOK_GUARD"
    fi
    if [ -f "$GOLDEN_HOOKS/$HOOK_WRAP" ]; then
        install -m 755 "$GOLDEN_HOOKS/$HOOK_WRAP" "$HOME/.cursor/hooks/$HOOK_WRAP"
    fi
    if [ -f "$GOLDEN_HOOKS/$HOOK_SCAN" ]; then
        install -m 755 "$GOLDEN_HOOKS/$HOOK_SCAN" "$HOME/.cursor/hooks/$HOOK_SCAN"
    fi
    if [ -f "$GOLDEN_HOOKS/$HOOK_SESSION" ]; then
        install -m 755 "$GOLDEN_HOOKS/$HOOK_SESSION" "$HOME/.cursor/hooks/$HOOK_SESSION"
    fi
    # Absolute path so hooks keep working regardless of Cursor cwd.
    # Merge into existing hooks.json so we do not wipe unrelated hooks.
    if [ -f "$HOME/.cursor/hooks.json" ]; then
        _merge_hooks_json "$HOME/.cursor/hooks.json" "$GOLDEN_HOOKS/hooks-user.json" "$HOOK_CMD_USER" "$HOOK_CMD_SESSION"
    elif command -v jq >/dev/null 2>&1; then
        local merged
        merged=$(mktemp)
        jq -n --arg cmd "$HOOK_CMD_USER" --arg scmd "$HOOK_CMD_SESSION" --arg matcher "$HOOK_MATCHER" '{
          version: 1,
          hooks: {
            sessionStart: [ {command: $scmd} ],
            beforeShellExecution: [ {command: $cmd} ],
            preToolUse: [ {command: $cmd, matcher: $matcher} ]
          }
        }' > "$merged"
        install -m 644 "$merged" "$HOME/.cursor/hooks.json"
        rm -f "$merged"
    elif [ -f "$GOLDEN_HOOKS/hooks-user.json" ]; then
        install -m 644 "$GOLDEN_HOOKS/hooks-user.json" "$HOME/.cursor/hooks.json"
    fi
}

_ensure_project_hooks() {
    local lpath="$1"
    [ -n "$lpath" ] || return 0
    [ -d "$lpath" ] || return 0
    mkdir -p "$lpath/.cursor"
    # CRITICAL (multi-agent): project hooks must stay EMPTY.
    # User hooks.json already runs wrap. Duplicating here double-fires every tool
    # (and old matcher included Shell) — agents look fully blocked under Task swarms.
    # Also do not install guard copies under mounts (STALE SSHFS confusion).
    printf '%s\n' '{"version":1,"hooks":{}}' > "$lpath/.cursor/hooks.json"
    chmod 644 "$lpath/.cursor/hooks.json" 2>/dev/null || true
    # Neutralize leftover project-local hook scripts (not referenced by empty hooks.json).
    if [ -d "$lpath/.cursor/hooks" ]; then
        local stub hf
        stub='#!/usr/bin/env bash
# DEPRECATED stub — project hooks.json is empty on purpose.
# Active hooks live in ~/.cursor/hooks (user-level wrap). Do not wire this path.
exit 0
'
        for hf in laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-session.sh laptop-exec-audit-log.sh laptop-exec-shell-scan.py; do
            [ -e "$lpath/.cursor/hooks/$hf" ] || continue
            printf '%s\n' "$stub" > "$lpath/.cursor/hooks/$hf" 2>/dev/null || true
            chmod 755 "$lpath/.cursor/hooks/$hf" 2>/dev/null || true
        done
    fi
}

_ensure_cursor_git_off() {
    # GIT_MODE=off|hide: Cursor must not probe SSHFS .git (Failed to execute git).
    # Also keep editors clean on Reload Window: SSHFS can briefly return EPERM while
    # Cursor flushes dirty tabs ("Failed to save … NoPermissions") — scary but
    # usually harmless. Auto-save after 1s means Reload rarely has anything to flush.
    # Keep this in User settings only - never write workspace .vscode (pollutes laptop repos).
    local conf="$HOME/.claude-connect.conf" mode="off"
    if [ -f "$conf" ]; then
        mode="$(grep -iE '^GIT_MODE=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
    fi
    # Auto-save applies even when GIT_MODE=server (SSHFS EPERM is unrelated to git).
    local _apply_git_off=1
    case "${mode:-off}" in
        server|on|yes|1|slow) _apply_git_off=0 ;;
    esac
    APPLY_GIT_OFF="$_apply_git_off" python3 - <<'PY' 2>/dev/null || true
import json, os
home = os.path.expanduser("~")
apply_git_off = os.environ.get("APPLY_GIT_OFF", "1") == "1"
want = {
    # Flush edits quickly so Reload Window does not hit SSHFS mid-teardown (EPERM popup).
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
}
if apply_git_off:
    want.update({
        "git.enabled": False,
        "git.autoRepositoryDetection": False,
        "git.detectSubmodules": False,
        "git.repositoryScanMaxDepth": 0,
    })
for rel in (
    ".cursor-server/data/User/settings.json",
    ".vscode-server/data/User/settings.json",
):
    top = os.path.join(home, rel.split("/")[0])
    data_dir = os.path.join(home, *rel.split("/")[:2])
    if not os.path.isdir(top) or not os.path.isdir(data_dir):
        continue
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, json.JSONDecodeError):
        data = {}
    data.update(want)
    if apply_git_off:
        data.pop("git.path", None)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PY
}

_ensure_user() {
    [ -f "$GOLDEN_BIN" ] || return 0
    mkdir -p "$HOME/.local/bin" "$HOME/.cursor/rules" "$HOME/.cursor/skills/laptop-exec"
    if [ ! -f "$HOME/.local/bin/laptop-exec" ] || [ "$GOLDEN_BIN" -nt "$HOME/.local/bin/laptop-exec" ]; then
        atomic_install 755 "$GOLDEN_BIN" "$HOME/.local/bin/laptop-exec"
    fi
    # Keep setup itself in PATH so heal/audit/login can re-run without relying only on /usr/local/bin.
    if [ -x /usr/local/bin/laptop-exec-setup ]; then
        if [ ! -f "$HOME/.local/bin/laptop-exec-setup" ] || [ /usr/local/bin/laptop-exec-setup -nt "$HOME/.local/bin/laptop-exec-setup" ]; then
            atomic_install 755 /usr/local/bin/laptop-exec-setup "$HOME/.local/bin/laptop-exec-setup"
        fi
    fi
    if [ -x /usr/local/bin/claude-automount ]; then
        if [ ! -f "$HOME/.local/bin/claude-automount" ] || [ /usr/local/bin/claude-automount -nt "$HOME/.local/bin/claude-automount" ]; then
            atomic_install 755 /usr/local/bin/claude-automount "$HOME/.local/bin/claude-automount"
        fi
    fi
    if [ -f "$GOLDEN_RULE" ]; then
        install -m 644 "$GOLDEN_RULE" "$HOME/.cursor/rules/laptop-exec.mdc"
    fi
    if [ -f "$GOLDEN_SKILL" ]; then
        install -m 644 "$GOLDEN_SKILL" "$HOME/.cursor/skills/laptop-exec/SKILL.md"
    fi
    if [ -f "$GOLDEN_SKILL_REF" ]; then
        install -m 644 "$GOLDEN_SKILL_REF" "$HOME/.cursor/skills/laptop-exec/reference-windows-mcp.md"
    fi
    _ensure_user_hooks
    _ensure_cursor_git_off
    if [ -x "$GOLDEN_HEAL" ]; then
        atomic_install 755 "$GOLDEN_HEAL" "$HOME/.local/bin/claude-self-heal"
        "$HOME/.local/bin/claude-self-heal" --quiet 2>/dev/null || true
    fi
}

_ensure_project_skill() {
    local lpath="$1"
    [ -f "$GOLDEN_SKILL" ] || return 0
    [ -d "$lpath" ] || return 0
    mkdir -p "$lpath/.cursor/skills/laptop-exec"
    install -m 644 "$GOLDEN_SKILL" "$lpath/.cursor/skills/laptop-exec/SKILL.md" 2>/dev/null || true
    if [ -f "$GOLDEN_SKILL_REF" ]; then
        install -m 644 "$GOLDEN_SKILL_REF" "$lpath/.cursor/skills/laptop-exec/reference-windows-mcp.md" 2>/dev/null || true
    fi
}

_ensure_project() {
    local lpath="$1"
    [ -n "$lpath" ] || return 0
    [ -d "$lpath" ] || return 0
    [ -f "$GOLDEN_RULE" ] || return 0
    mkdir -p "$lpath/.cursor/rules"
    install -m 644 "$GOLDEN_RULE" "$lpath/.cursor/rules/laptop-exec.mdc" 2>/dev/null || true
    _ensure_project_skill "$lpath"
    _ensure_project_hooks "$lpath"
}

_ensure_all_mounts() {
    local d require_mount="${1:-1}"
    [ -d "$HOME/mounts" ] || return 0
    for d in "$HOME/mounts"/*/; do
        [ -d "$d" ] || continue
        if [ "$require_mount" = "1" ]; then
            # Never use mountpoint -q: frozen SSHFS can hang. /proc/mounts is instant.
            mp="${d%/}"
            grep -F " $mp " /proc/mounts >/dev/null 2>&1 || continue
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

