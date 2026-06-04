#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="$HOME/.claude-mounts.d"
CONNECT_CONF="$HOME/.claude-connect.conf"
KEY="$HOME/.ssh/claude_laptop"

# ---------------------------------------------------------------------------
# Globals (populated by _load_global)
# ---------------------------------------------------------------------------
LAPTOP_USER=""
TUNNEL_PORT=""

_load_global() {
    if [ -f "$CONNECT_CONF" ]; then
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                LAPTOP_USER)  LAPTOP_USER="$v" ;;
                TUNNEL_PORT)  TUNNEL_PORT="$v" ;;
            esac
        done < "$CONNECT_CONF"
    fi
    if [ -z "$TUNNEL_PORT" ]; then
        TUNNEL_PORT=$((20000 + $(id -u)))
    fi
}

# ---------------------------------------------------------------------------
# Git hiding — hides .git on Windows by renaming to .git.server-session
# so that git tools on the server never stat() files over SSHFS.
# All operations are best-effort: failures are silently ignored so they
# never block mount/unmount.
#
# Self-healing contract:
#   _hide_git   : idempotent — skips if .git.server-session already exists
#   _restore_git: idempotent — skips if .git already exists
#   cmd_recover : restores all hidden gits for currently-unmounted projects
#
# Edge cases handled:
#   - empty rpath, missing LAPTOP_USER/TUNNEL_PORT → skip silently
#   - SSH timeout/auth failure → skip silently (git stays as-is)
#   - single quotes in path → escaped for PowerShell single-quoted string
#   - .git is a FILE (gitdir pointer for worktrees) → not renamed (-PathType Container)
#   - both .git and .git.server-session exist → skip (manual state, don't touch)
#   - .git.server-session exists already → skip (idempotent)
# ---------------------------------------------------------------------------
# _win_ps — shared SSH helper: runs a PowerShell snippet on the Windows laptop.
# All Windows operations use this to avoid repeating the same 6-flag boilerplate.
_win_ps() {
    local ps_cmd="$1"
    if [ -z "$LAPTOP_USER" ] || [ -z "$TUNNEL_PORT" ]; then
        return 0
    fi
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" \
        "powershell -NoProfile -Command \"${ps_cmd}\"" \
        2>/dev/null || true
}

_hide_git() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    local safe="${rpath//\'/\'\'}"
    _win_ps "if ((Test-Path '${safe}/.git' -PathType Container) -and -not (Test-Path '${safe}/.git.server-session')) { Rename-Item '${safe}/.git' '.git.server-session' -ErrorAction SilentlyContinue }"
}

_restore_git() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    local safe="${rpath//\'/\'\'}"
    _win_ps "if (Test-Path '${safe}/.git.server-session' -PathType Container) { Rename-Item '${safe}/.git.server-session' '.git' -ErrorAction SilentlyContinue }"
}

# Hide .git AND create .claude/ stubs in a single SSH connection.
# Stubs prevent Claude Code from doing one SFTP round-trip per missing path (~3s each).
# Called on every mount (new and already-mounted) so stubs always exist.
_hide_git_and_create_stubs() {
    local rpath="$1"
    [ -z "$rpath" ] && return 0
    local safe="${rpath//\'/\'\'}"
    # Only create .claude stubs if the project has a .git repo — non-git directories
    # (e.g. utility script folders) don't need Claude Code project config files.
    _win_ps "\
\$hasGit = (Test-Path '${safe}/.git' -PathType Container) -or (Test-Path '${safe}/.git.server-session' -PathType Container); \
if ((Test-Path '${safe}/.git' -PathType Container) -and -not (Test-Path '${safe}/.git.server-session')) { Rename-Item '${safe}/.git' '.git.server-session' -ErrorAction SilentlyContinue }; \
if (\$hasGit) { \
  New-Item -ItemType Directory -Force -Path '${safe}/.claude/rules','${safe}/.claude/commands' | Out-Null; \
  if (-not (Test-Path '${safe}/.mcp.json') -or (Get-Item '${safe}/.mcp.json').Length -eq 0) { Set-Content -Path '${safe}/.mcp.json' -Value '{}' -Encoding utf8 } \
}\
"
}

# Pre-warm SSHFS directory caches so first 'claude' run is instant.
# Runs in background — doesn't block mount. Warm by the time user opens VSCode terminal.
_warm_sshfs_cache() {
    local lpath="$1"
    (
        timeout 5 ls "$lpath/.claude/"          >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/rules/"    >/dev/null 2>&1 || true
        timeout 5 ls "$lpath/.claude/commands/" >/dev/null 2>&1 || true
    ) &
}

# ---------------------------------------------------------------------------
# Tunnel / mount checks
# ---------------------------------------------------------------------------
_tunnel_up() {
    timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null
}

_is_mounted() {
    local lpath="$1"
    mountpoint -q "$lpath" 2>/dev/null && \
        timeout 2 ls "$lpath" >/dev/null 2>&1
}

# Try every available unmount method, from clean to lazy. Always returns 0.
_do_unmount() {
    local lpath="$1"
    fusermount  -u  "$lpath" 2>/dev/null || \
    fusermount3 -u  "$lpath" 2>/dev/null || \
    fusermount  -uz "$lpath" 2>/dev/null || \
    fusermount3 -uz "$lpath" 2>/dev/null || \
    umount -l "$lpath" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Core mount
# ---------------------------------------------------------------------------
_do_mount() {
    local conf_file="$1"
    local id="" label="" rpath="" lpath=""

    [ -f "$conf_file" ] || { echo "error: conf not found: $conf_file" >&2; return 1; }

    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            id|MOUNT_ID)       id="$v" ;;
            label|MOUNT_LABEL) label="$v" ;;
            rpath|REMOTE_PATH) rpath="$v" ;;
            lpath|LOCAL_PATH)  lpath="$v" ;;
        esac
    done < "$conf_file"

    lpath="${lpath//\\//}"
    rpath="${rpath//\\//}"

    if _is_mounted "$lpath"; then
        echo "already mounted: $lpath"
        # Stubs + cache warm on every up call — dcache_timeout=60s expires between sessions
        # and stubs might not have been created if this is the first time after a reboot.
        _hide_git_and_create_stubs "$rpath"
        _warm_sshfs_cache "$lpath"
        return 0
    fi

    # Clean stale mountpoint (use lazy unmount -uz in case the mount is frozen)
    if timeout 2 mountpoint -q "$lpath" 2>/dev/null; then
        _do_unmount "$lpath"
        sleep 1
    fi

    # mkdir -p can fail with I/O error if lpath is under a stale parent mount
    if ! mkdir -p "$lpath" 2>/dev/null; then
        _do_unmount "$lpath"
        sleep 1
        if ! timeout 5 mkdir -p "$lpath" 2>/dev/null; then
            echo "error: cannot create mountpoint $lpath" >&2
            return 1
        fi
    fi

    # Hide .git and create Claude stubs in one SSH call — from here on, any failure must restore .git
    _hide_git_and_create_stubs "$rpath"

    local sshfs_opts="ServerAliveInterval=10,ServerAliveCountMax=3,idmap=user,allow_other,StrictHostKeyChecking=no,UserKnownHostsFile=/dev/null,ConnectTimeout=10,dir_cache=yes,dcache_timeout=60,attr_timeout=30,entry_timeout=30,max_conns=4"
    local id_opt=""
    [ -f "$KEY" ] && id_opt=",IdentityFile=$KEY"

    local sshfs_out sshfs_exit=0
    sshfs_out=$(timeout 30 sshfs -o "${sshfs_opts}${id_opt}" \
        "${LAPTOP_USER}@127.0.0.1:${rpath}" "${lpath}" \
        -p "${TUNNEL_PORT}" 2>&1) || sshfs_exit=$?

    if [ "$sshfs_exit" -ne 0 ]; then
        # sshfs failed — .git was hidden by _hide_git_and_create_stubs, restore it
        _restore_git "$rpath"
        local reason="$sshfs_out"
        # Check specific errors FIRST so a timed-out sshfs that printed a real
        # error before being killed (exit 124) still shows the actionable message.
        if echo "$reason" | grep -qi "permission denied\|publickey"; then
            reason="key auth failed - re-run connect.bat to reinstall the key"
        elif echo "$reason" | grep -qi "connection reset\|reset by peer"; then
            reason="connection reset - laptop SSH rejected the key (re-run connect.bat to reinstall)"
        elif echo "$reason" | grep -qi "no such file\|cannot find\|not found"; then
            reason="path not found on laptop: $rpath"
        elif echo "$reason" | grep -qi "connection refused"; then
            reason="laptop SSH not running (connection refused)"
        elif [ "$sshfs_exit" -eq 124 ] || [ -z "$reason" ]; then
            reason="laptop SSH not responding (timeout)"
        fi
        echo "error: mount failed - $reason" >&2
        return 1
    fi

    if ! timeout 10 ls -A "$lpath" >/dev/null 2>&1; then
        # mount came up but is not readable — restore .git and clean up
        _restore_git "$rpath"
        echo "error: mount verification failed for $lpath" >&2
        _do_unmount "$lpath"
        return 1
    fi

    echo "mounted: $lpath"
    _warm_sshfs_cache "$lpath"
    return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_list() {
    mkdir -p "$CONF_DIR"
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local id="" label="" rpath="" lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id|MOUNT_ID)       id="$v" ;;
                label|MOUNT_LABEL) label="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
            esac
        done < "$f"
        echo "${id}|${label}|${rpath}|${lpath}"
    done
}

cmd_status() {
    mkdir -p "$CONF_DIR"
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local id="" label="" rpath="" lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id|MOUNT_ID)       id="$v" ;;
                label|MOUNT_LABEL) label="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
            esac
        done < "$f"
        local status="OFF"
        _is_mounted "$lpath" 2>/dev/null && status="MOUNTED"
        echo "${id}|${label}|${lpath}|${status}"
    done
}

cmd_add() {
    local id label rpath lpath
    if [ $# -ge 4 ]; then
        id="$1"; label="$2"; rpath="$3"; lpath="$4"
    else
        printf "ID: "; read -r id
        printf "Label: "; read -r label
        printf "Remote path: "; read -r rpath
        printf "Local path: "; read -r lpath
    fi

    mkdir -p "$CONF_DIR"
    local conf="$CONF_DIR/${id}.conf"
    cat > "$conf" <<EOF
id=$id
label=$label
rpath=$rpath
lpath=$lpath
EOF
    echo "added: $id ($label)"
}

cmd_edit() {
    local id="$1"
    local new_label="${2:-}"
    local new_rpath="${3:-}"
    local new_lpath="${4:-}"
    local conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { echo "error: not found: $id" >&2; return 1; }

    local cur_label="" cur_rpath="" cur_lpath=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            label) cur_label="$v" ;;
            rpath) cur_rpath="$v" ;;
            lpath) cur_lpath="$v" ;;
        esac
    done < "$conf"

    # Save old rpath before any modification
    local old_rpath="${cur_rpath//\\//}"

    if [ -n "$new_label" ] || [ -n "$new_rpath" ] || [ -n "$new_lpath" ]; then
        # Non-interactive: use provided args, keep current value if arg is empty
        [ -n "$new_label" ] && cur_label="$new_label"
        [ -n "$new_rpath" ] && cur_rpath="$new_rpath"
        [ -n "$new_lpath" ] && cur_lpath="$new_lpath"
    else
        # Interactive (local terminal)
        printf "Label [%s]: " "$cur_label"; read -r v; [ -n "$v" ] && cur_label="$v"
        printf "Remote path [%s]: " "$cur_rpath"; read -r v; [ -n "$v" ] && cur_rpath="$v"
        printf "Local path [%s]: " "$cur_lpath"; read -r v; [ -n "$v" ] && cur_lpath="$v"
    fi

    # If rpath changed, restore .git at old path before losing the reference
    local cur_rpath_norm="${cur_rpath//\\//}"
    if [ -n "$old_rpath" ] && [ "$cur_rpath_norm" != "$old_rpath" ]; then
        _load_global
        _restore_git "$old_rpath"
    fi

    cat > "$conf" <<EOF
id=$id
label=$cur_label
rpath=$cur_rpath
lpath=$cur_lpath
EOF
    echo "updated: $id"
}

cmd_rm() {
    local id="$1"
    local conf="$CONF_DIR/${id}.conf"
    [ -f "$conf" ] || { echo "error: not found: $id" >&2; return 1; }

    _load_global

    # Read paths before deleting config — once config is gone, rpath is lost forever
    local rpath="" lpath=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            rpath|REMOTE_PATH) rpath="$v" ;;
            lpath|LOCAL_PATH)  lpath="$v" ;;
        esac
    done < "$conf"
    rpath="${rpath//\\//}"
    lpath="${lpath//\\//}"

    # Unmount first so SSHFS isn't left pointing at a removed project
    if [ -n "$lpath" ] && _is_mounted "$lpath" 2>/dev/null; then
        _do_unmount "$lpath"
    fi

    # Restore .git on Windows before losing the rpath reference
    [ -n "$rpath" ] && _restore_git "$rpath"

    rm -f "$conf"
    echo "removed: $id"
}

# Restore .git for all projects whose mount is NOT currently active.
# Called at session start (connect.bat, automount) to recover from crashes.
# Safe to call while other mounts are active — mounted projects are skipped.
cmd_recover() {
    _load_global
    mkdir -p "$CONF_DIR"
    for f in "$CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local rpath="" lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                rpath|REMOTE_PATH) rpath="$v" ;;
                lpath|LOCAL_PATH)  lpath="$v" ;;
            esac
        done < "$f"
        rpath="${rpath//\\//}"
        lpath="${lpath//\\//}"
        # Use mountpoint -q only (no ls/timeout) — _is_mounted's 2s ls timeout
        # gives false negatives on slow SSHFS, which would restore .git on an
        # active mount. mountpoint -q reads /proc/mounts: instant and reliable.
        # Also guard lpath: mountpoint -q "" exits 1, which would falsely
        # trigger restore on a malformed conf with empty lpath.
        if [ -n "$rpath" ] && [ -n "$lpath" ] && ! mountpoint -q "$lpath" 2>/dev/null; then
            _restore_git "$rpath"
        fi
    done
}

cmd_up() {
    _load_global

    if [ -z "$LAPTOP_USER" ]; then
        echo "error: LAPTOP_USER not set in $CONNECT_CONF" >&2
        return 1
    fi

    if ! _tunnel_up; then
        echo "error: reverse tunnel not up on port $TUNNEL_PORT" >&2
        return 1
    fi

    local target="${1:-}"

    if [ -n "$target" ]; then
        local conf="$CONF_DIR/${target}.conf"
        [ -f "$conf" ] || { echo "error: not found: $target" >&2; return 1; }
        _do_mount "$conf"
    else
        local any_error=0
        for f in "$CONF_DIR"/*.conf; do
            [ -f "$f" ] || continue
            _do_mount "$f" || any_error=1
        done
        return $any_error
    fi
}

cmd_down() {
    _load_global

    local target="${1:-}"

    if [ -n "$target" ]; then
        local conf="$CONF_DIR/${target}.conf"
        [ -f "$conf" ] || { echo "error: not found: $target" >&2; return 1; }
        local lpath="" rpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                lpath|LOCAL_PATH)  lpath="$v" ;;
                rpath|REMOTE_PATH) rpath="$v" ;;
            esac
        done < "$conf"
        lpath="${lpath//\\//}"
        rpath="${rpath//\\//}"

        if _is_mounted "$lpath" 2>/dev/null; then
            if fusermount  -u  "$lpath" 2>/dev/null || \
               fusermount3 -u  "$lpath" 2>/dev/null || \
               fusermount  -uz "$lpath" 2>/dev/null || \
               fusermount3 -uz "$lpath" 2>/dev/null || \
               umount -l "$lpath" 2>/dev/null; then
                echo "unmounted: $lpath"
            else
                echo "error: unmount failed: $lpath" >&2
                return 1
            fi
        else
            echo "not mounted: $lpath"
        fi
        # Restore .git whether mount was active or already down
        # (skipped only when unmount hard-fails above)
        _restore_git "$rpath"
    else
        for f in "$CONF_DIR"/*.conf; do
            [ -f "$f" ] || continue
            local lpath="" rpath=""
            while IFS='=' read -r k v; do
                v="${v#\"}" v="${v%\"}"
                case "$k" in
                    lpath|LOCAL_PATH)  lpath="$v" ;;
                    rpath|REMOTE_PATH) rpath="$v" ;;
                esac
            done < "$f"
            lpath="${lpath//\\//}"
            rpath="${rpath//\\//}"
            if _is_mounted "$lpath" 2>/dev/null; then
                _do_unmount "$lpath"
                echo "unmounted: $lpath"
                _restore_git "$rpath"
            else
                # Not mounted — still restore in case .git was hidden by a crashed session
                _restore_git "$rpath"
            fi
        done
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
cmd="${1:-list}"
shift 2>/dev/null || true

case "$cmd" in
    list)                cmd_list ;;
    status)              cmd_status ;;
    add)                 cmd_add "$@" ;;
    edit)                cmd_edit "$@" ;;
    rm|remove|del)       cmd_rm "$@" ;;
    up|mount)            cmd_up "$@" ;;
    down|umount|unmount) cmd_down "$@" ;;
    recover)             cmd_recover ;;
    *)
        echo "Usage: claude-mount {list|status|add|edit|rm|up|down|recover} [id]" >&2
        exit 1
        ;;
esac
