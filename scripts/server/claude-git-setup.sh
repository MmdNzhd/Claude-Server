#!/usr/bin/env bash
# claude-git-setup -- per-user local git mirror for SSHFS projects
#
# Usage:
#   claude-git-setup init <project_id>   -- first-time setup (idempotent)
#   claude-git-setup sync <project_id>   -- incremental sync from Windows
#   claude-git-setup status <project_id> -- none|ready|partial|no-git|no-conf
#
# Design:
#   - .git on Windows becomes a pointer file -> server-local git dir
#   - Everything is optional: any failure falls back to slow SSHFS git
#   - Idempotent and safe to run repeatedly
#   - Lockfile per project prevents concurrent runs
#   - Recovery: if pointer exists but server git was deleted, restores from backup

set -uo pipefail

GIT_REPOS_DIR="$HOME/.git-repos"
CONF_DIR="$HOME/.claude-mounts.d"
CONNECT_CONF="$HOME/.claude-connect.conf"
KEY="$HOME/.ssh/claude_laptop"
LOG_DIR="$GIT_REPOS_DIR/logs"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_log() { mkdir -p "$LOG_DIR"; echo "[$(date -Iseconds)] $*" >> "$LOG_DIR/${PROJECT_ID:-unknown}.log"; }

_load_conn() {
    LAPTOP_USER="" TUNNEL_PORT=""
    [ -f "$CONNECT_CONF" ] || return 1
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in LAPTOP_USER) LAPTOP_USER="$v";; TUNNEL_PORT) TUNNEL_PORT="$v";; esac
    done < "$CONNECT_CONF"
    [ -n "$LAPTOP_USER" ] && [ -n "$TUNNEL_PORT" ]
}

_load_project() {
    local id="$1"
    local conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { _log "no conf for $id"; return 1; }
    REMOTE_PATH="" LOCAL_PATH=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            REMOTE_PATH|rpath) REMOTE_PATH="$v";;
            LOCAL_PATH|lpath)  LOCAL_PATH="$v";;
        esac
    done < "$conf"
    LOCAL_PATH="${LOCAL_PATH//\\//}"
    REMOTE_PATH="${REMOTE_PATH//\\//}"
    [ -n "$REMOTE_PATH" ] && [ -n "$LOCAL_PATH" ]
}

_ssh_win() {
    [ -n "${TUNNEL_PORT:-}" ] || return 1
    ssh -p "$TUNNEL_PORT" -i "$KEY" \
        -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ControlMaster=no \
        -o ConnectTimeout=10 \
        "${LAPTOP_USER}@127.0.0.1" "$@" 2>/dev/null
}

_scp_from_win() {
    local remote="$1" local_path="$2"
    [ -n "${TUNNEL_PORT:-}" ] || return 1
    scp -P "$TUNNEL_PORT" -i "$KEY" \
        -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ControlMaster=no \
        -o ConnectTimeout=10 \
        "${LAPTOP_USER}@127.0.0.1:${remote}" "$local_path" 2>/dev/null
}

_mount_accessible() {
    timeout 5 ls "$LOCAL_PATH" >/dev/null 2>&1
}

_win_git_is_dir() {
    [ -d "${LOCAL_PATH}/.git" ]
}

_win_git_is_pointer() {
    [ -f "${LOCAL_PATH}/.git" ] && grep -q "^gitdir:" "${LOCAL_PATH}/.git" 2>/dev/null
}

_server_git_ok() {
    [ -d "$SERVER_GIT" ] && [ -f "$SERVER_GIT/HEAD" ] && \
        git --git-dir="$SERVER_GIT" rev-parse HEAD >/dev/null 2>&1
}

_tunnel_up() {
    timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${TUNNEL_PORT:-0}" 2>/dev/null
}

# Write a PowerShell script to the SSHFS mount and run it via SSH back to Windows.
# The SSHFS write works even when directory operations (Move-Item, Remove-Item dir)
# require Windows-side permissions. Cleans up the script file after execution.
_run_ps_via_sshfs() {
    local script_content="$1"
    local local_ps="${LOCAL_PATH}/.claude-git-init.ps1"
    local win_ps="${REMOTE_PATH}/.claude-git-init.ps1"

    printf '%s' "$script_content" > "$local_ps" 2>/dev/null || return 1
    local result
    result=$(_ssh_win "powershell -NoProfile -ExecutionPolicy Bypass -File \"${win_ps}\"" 2>/dev/null)
    local rc=$?
    rm -f "$local_ps" 2>/dev/null || true
    echo "${result:-}"
    return $rc
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_status() {
    _load_project "$PROJECT_ID" || { echo "no-conf"; return; }

    if ! _server_git_ok; then
        if [ ! -e "${LOCAL_PATH}/.git" ]; then
            echo "no-git"
        elif _win_git_is_pointer; then
            echo "partial"   # pointer exists but server git lost -- needs recovery
        else
            echo "none"
        fi
        return
    fi

    if _win_git_is_pointer; then
        echo "ready"
    else
        echo "partial"   # server git exists but pointer not yet created
    fi
}

cmd_init() {
    _load_conn         || { _log "no connection config"; exit 0; }
    _load_project "$PROJECT_ID" || { _log "no project config"; exit 0; }

    local lock_file="$GIT_REPOS_DIR/${PROJECT_ID}.lock"

    # Lockfile: prevent concurrent runs for the same project
    if [ -f "$lock_file" ]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        if kill -0 "$lock_pid" 2>/dev/null; then
            _log "init already running (pid $lock_pid)"
            exit 0
        fi
        rm -f "$lock_file"
    fi
    mkdir -p "$GIT_REPOS_DIR"
    echo $$ > "$lock_file"
    trap 'rm -f "$lock_file"' EXIT

    # Already fully set up?
    if _server_git_ok && _win_git_is_pointer; then
        _log "already ready"
        exit 0
    fi

    # Verify mount is accessible before doing anything
    if ! _mount_accessible; then
        _log "SSHFS mount not accessible, skipping"
        exit 0
    fi

    # No .git on this project at all -- not a git repo, skip silently
    if [ ! -e "${LOCAL_PATH}/.git" ]; then
        _log "no .git found -- not a git repo"
        exit 0
    fi

    # Tunnel must be up for SSH-back-to-Windows operations
    if ! _tunnel_up; then
        _log "tunnel not up, skipping"
        exit 0
    fi

    # -----------------------------------------------------------------------
    # Recovery: pointer exists but server git was lost (e.g. server reinstall)
    # Restore .git-local backup on Windows so we can re-create server git.
    # -----------------------------------------------------------------------
    if _win_git_is_pointer && ! _server_git_ok; then
        _log "pointer exists but server git lost -- attempting recovery"
        local backup_local="${LOCAL_PATH}/.git-local"

        if [ -d "$backup_local" ]; then
            _log "restoring .git-local backup via Windows SSH..."
            local win_git="${REMOTE_PATH}/.git"
            local win_backup="${REMOTE_PATH}/.git-local"

            local recovery_script
            recovery_script=$(cat <<PSEOF
\$g = '${win_git}'
\$b = '${win_backup}'
if (Test-Path \$b) {
    if (Test-Path \$g) { Remove-Item \$g -Force }
    Move-Item \$b \$g
    Write-Host 'restored'
} else {
    Write-Host 'no-backup'
}
PSEOF
)
            local r
            r=$(_run_ps_via_sshfs "$recovery_script")
            _log "recovery result: ${r:-failed}"

            if ! _win_git_is_dir; then
                _log "recovery failed -- cannot proceed"
                exit 0
            fi
        else
            _log "no .git-local backup found -- cannot recover without Windows .git"
            exit 0
        fi
    fi

    # -----------------------------------------------------------------------
    # Step 1: Create server-local git dir from Windows bundle
    # -----------------------------------------------------------------------
    if ! _server_git_ok; then
        _log "creating server git from bundle..."

        # Use user's home dir on Windows -- always exists, no need to create
        local win_bundle="C:/Users/${LAPTOP_USER}/claude-git-${PROJECT_ID}.bundle"
        local local_bundle="/tmp/claude-git-${PROJECT_ID}-$$.bundle"

        local bundle_ok=0
        _ssh_win "git -C \"${REMOTE_PATH}\" bundle create \"${win_bundle}\" --all HEAD" \
            && bundle_ok=1

        if [ "$bundle_ok" -eq 0 ]; then
            _log "bundle failed -- git may not be in Windows PATH or repo path wrong"
            exit 0
        fi

        _log "transferring bundle..."
        if ! _scp_from_win "$win_bundle" "$local_bundle"; then
            _log "scp failed"
            _ssh_win "powershell -NoProfile -Command \"Remove-Item -Force -ErrorAction SilentlyContinue '${win_bundle}'\"" || true
            exit 0
        fi

        if ! git bundle verify "$local_bundle" >/dev/null 2>&1; then
            _log "bundle verification failed -- partial transfer?"
            rm -f "$local_bundle"
            _ssh_win "powershell -NoProfile -Command \"Remove-Item -Force -ErrorAction SilentlyContinue '${win_bundle}'\"" || true
            exit 0
        fi

        rm -rf "$SERVER_GIT"
        if ! git clone --bare "$local_bundle" "$SERVER_GIT" 2>/dev/null; then
            _log "git clone failed"
            rm -f "$local_bundle"
            _ssh_win "powershell -NoProfile -Command \"Remove-Item -Force -ErrorAction SilentlyContinue '${win_bundle}'\"" || true
            exit 0
        fi

        # Configure for use with a working tree (not bare).
        # Use --git-dir to avoid confusion after core.bare is set to false.
        git --git-dir="$SERVER_GIT" config core.bare false           2>/dev/null || true
        git --git-dir="$SERVER_GIT" config core.untrackedCache true  2>/dev/null || true
        git --git-dir="$SERVER_GIT" pack-refs --all                  2>/dev/null || true
        git --git-dir="$SERVER_GIT" gc --auto                        2>/dev/null || true

        # Pre-populate index so first git status is fast
        GIT_DIR="$SERVER_GIT" GIT_WORK_TREE="$LOCAL_PATH" \
            git read-tree HEAD 2>/dev/null || true

        rm -f "$local_bundle"
        _ssh_win "powershell -NoProfile -Command \"Remove-Item -Force -ErrorAction SilentlyContinue '${win_bundle}'\"" || true
        _log "server git created"
    fi

    # Ensure server git is configured for working-tree use regardless of how it was created
    git --git-dir="$SERVER_GIT" config core.bare false          2>/dev/null || true
    git --git-dir="$SERVER_GIT" config core.untrackedCache true 2>/dev/null || true

    # -----------------------------------------------------------------------
    # Step 2: Create gitdir pointer on Windows (replaces .git directory)
    # -----------------------------------------------------------------------
    if ! _win_git_is_pointer; then
        _log "creating gitdir pointer on Windows..."

        if _win_git_is_dir; then
            local win_git="${REMOTE_PATH}/.git"
            local win_backup="${REMOTE_PATH}/.git-local"
            local pointer="gitdir: ${SERVER_GIT}"

            # Write setup script to Windows via SSHFS, then execute via SSH.
            # This sidesteps Windows SSHFS permission issues for directory operations.
            local ps_script
            ps_script=$(cat <<PSEOF
\$g = '${win_git}'
\$b = '${win_backup}'
\$c = '${pointer}'
if ((Get-Item \$g -ErrorAction SilentlyContinue) -is [System.IO.DirectoryInfo]) {
    if (-not (Test-Path \$b)) {
        Move-Item \$g \$b
    } else {
        Remove-Item \$g -Recurse -Force
    }
    Set-Content -NoNewline -Encoding ASCII \$g \$c
    Write-Host 'pointer created'
} elseif (Test-Path \$g) {
    Write-Host 'already a file'
} else {
    Write-Host 'not found'
}
PSEOF
)
            local result
            result=$(_run_ps_via_sshfs "$ps_script")
            _log "pointer setup result: ${result:-no output}"
        fi

        if _win_git_is_pointer; then
            _log "pointer verified"
        else
            _log "warning: pointer not created -- git will use SSHFS (slow but functional)"
        fi
    fi

    _log "init complete"
    exit 0
}

cmd_sync() {
    _load_conn         || exit 0
    _load_project "$PROJECT_ID" || exit 0

    _mount_accessible || { _log "sync: mount not accessible"; exit 0; }

    # If pointer is active, all commits already go directly to server git -- nothing to sync
    if _win_git_is_pointer; then
        _log "sync: pointer active, commits go directly to server git"
        exit 0
    fi

    _server_git_ok || { _log "sync: no server git, run init first"; exit 1; }
    _tunnel_up || { _log "sync: tunnel not up"; exit 0; }

    local server_head
    server_head=$(git --git-dir="$SERVER_GIT" rev-parse HEAD 2>/dev/null) || { _log "sync: no commits on server"; exit 0; }

    local win_head
    win_head=$(_ssh_win "git -C \"${REMOTE_PATH}\" rev-parse HEAD 2>/dev/null") || { _log "sync: can't reach Windows git"; exit 0; }
    win_head=$(echo "$win_head" | tr -d '\r')

    if [ "$server_head" = "$win_head" ]; then
        _log "sync: already in sync ($server_head)"
        exit 0
    fi

    _log "sync: server=$server_head win=$win_head -- syncing..."

    local win_bundle="C:/Users/${LAPTOP_USER}/claude-git-sync-${PROJECT_ID}.bundle"
    local local_bundle="/tmp/claude-git-sync-${PROJECT_ID}-$$.bundle"

    # Try incremental bundle first (only new commits since server HEAD)
    local bundle_ok=0
    _ssh_win "git -C \"${REMOTE_PATH}\" bundle create \"${win_bundle}\" \"^${server_head}\" HEAD 2>/dev/null" \
        && bundle_ok=1

    # Fallback to full bundle
    if [ "$bundle_ok" -eq 0 ]; then
        _ssh_win "git -C \"${REMOTE_PATH}\" bundle create \"${win_bundle}\" --all HEAD 2>/dev/null" \
            && bundle_ok=1
    fi

    [ "$bundle_ok" -eq 1 ] || { _log "sync: bundle failed"; exit 0; }

    _scp_from_win "$win_bundle" "$local_bundle" || { _log "sync: scp failed"; exit 0; }

    git --git-dir="$SERVER_GIT" fetch "$local_bundle" 'refs/heads/*:refs/heads/*' 2>/dev/null || \
    git --git-dir="$SERVER_GIT" fetch "$local_bundle" 2>/dev/null || true

    rm -f "$local_bundle"
    _ssh_win "powershell -NoProfile -Command \"Remove-Item -Force -ErrorAction SilentlyContinue '${win_bundle}'\"" || true

    local new_head
    new_head=$(git --git-dir="$SERVER_GIT" rev-parse HEAD 2>/dev/null)
    _log "sync complete: $new_head"
    exit 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
CMD="${1:-}"
PROJECT_ID="${2:-}"
SERVER_GIT="$GIT_REPOS_DIR/${PROJECT_ID}.git"

[ -n "$PROJECT_ID" ] || { echo "Usage: claude-git-setup {init|sync|status} <project_id>" >&2; exit 1; }
mkdir -p "$GIT_REPOS_DIR" "$LOG_DIR"

case "$CMD" in
    init)   cmd_init ;;
    sync)   cmd_sync ;;
    status) cmd_status ;;
    *) echo "Usage: claude-git-setup {init|sync|status} <project_id>" >&2; exit 1 ;;
esac
