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

# ---------------------------------------------------------------------------
# Core mount
# ---------------------------------------------------------------------------
_do_mount() {
    local conf_file="$1"
    local id label rpath lpath

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

    # Normalize backslashes
    lpath="${lpath//\\//}"
    rpath="${rpath//\\//}"

    if _is_mounted "$lpath"; then
        echo "already mounted: $lpath"
        return 0
    fi

    # Clean stale mountpoint
    if mountpoint -q "$lpath" 2>/dev/null; then
        fusermount -u "$lpath" 2>/dev/null || fusermount3 -u "$lpath" 2>/dev/null || true
    fi

    mkdir -p "$lpath"

    local sshfs_opts="ServerAliveInterval=10,ServerAliveCountMax=3,idmap=user,allow_other,StrictHostKeyChecking=no,UserKnownHostsFile=/dev/null,ConnectTimeout=10,dir_cache=yes,dcache_timeout=60,max_conns=4"

    local id_opt=""
    if [ -f "$KEY" ]; then
        id_opt=",IdentityFile=$KEY"
    fi

    local sshfs_cmd="sshfs -o ${sshfs_opts}${id_opt} ${LAPTOP_USER}@127.0.0.1:${rpath} ${lpath} -p ${TUNNEL_PORT}"

    if ! timeout 30 bash -c "$sshfs_cmd" 2>&1; then
        echo "error: sshfs mount failed for $id ($lpath)" >&2
        return 1
    fi

    if ! timeout 10 ls -A "$lpath" >/dev/null 2>&1; then
        echo "error: mount verification failed for $lpath" >&2
        fusermount -u "$lpath" 2>/dev/null || fusermount3 -u "$lpath" 2>/dev/null || true
        return 1
    fi

    echo "mounted: $lpath"
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

    printf "Label [%s]: " "$cur_label"; read -r v; [ -n "$v" ] && cur_label="$v"
    printf "Remote path [%s]: " "$cur_rpath"; read -r v; [ -n "$v" ] && cur_rpath="$v"
    printf "Local path [%s]: " "$cur_lpath"; read -r v; [ -n "$v" ] && cur_lpath="$v"

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
    rm -f "$conf"
    echo "removed: $id"
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
    local target="${1:-}"

    if [ -n "$target" ]; then
        local conf="$CONF_DIR/${target}.conf"
        [ -f "$conf" ] || { echo "error: not found: $target" >&2; return 1; }
        local lpath=""
        while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}" 
            [ "$k" = "lpath" ] && lpath="$v"
        done < "$conf"
        lpath="${lpath//\\//}"
        if _is_mounted "$lpath" 2>/dev/null; then
            fusermount -u "$lpath" 2>/dev/null || fusermount3 -u "$lpath" 2>/dev/null || \
                umount "$lpath" 2>/dev/null || { echo "error: unmount failed: $lpath" >&2; return 1; }
            echo "unmounted: $lpath"
        else
            echo "not mounted: $lpath"
        fi
    else
        for f in "$CONF_DIR"/*.conf; do
            [ -f "$f" ] || continue
            local lpath=""
            while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}" 
                [ "$k" = "lpath" ] && lpath="$v"
            done < "$f"
            lpath="${lpath//\\//}"
            if _is_mounted "$lpath" 2>/dev/null; then
                fusermount -u "$lpath" 2>/dev/null || fusermount3 -u "$lpath" 2>/dev/null || \
                    umount "$lpath" 2>/dev/null || true
                echo "unmounted: $lpath"
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
    *)
        echo "Usage: claude-mount {list|status|add|edit|rm|up|down} [id]" >&2
        exit 1
        ;;
esac
