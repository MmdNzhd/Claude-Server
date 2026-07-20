#!/bin/bash
# claude-watchdog -- monitors SSHFS mounts and recovers from hangs/disconnects.
# Edge cases covered:
#   - frozen mounts (never use mountpoint -q; use /proc/mounts + timed ls)
#   - tunnel DOWN → umount all + kill orphan sshfs
#   - tunnel UP + ACTIVE_MOUNT missing -> infer (LAST_ACTIVE/mounted only) + remount
#   - tunnel UP + active not mounted / zombie → remount
# Run once per session from automount (background). One instance per user (lock).

LOCK_FILE="/tmp/claude-watchdog-${USER}.pid"
MOUNT_BIN="$HOME/.local/bin/claude-mount"
[ -x "$MOUNT_BIN" ] || MOUNT_BIN="/usr/local/bin/claude-mount"
CONF_DIR="$HOME/.claude-mounts.d"
CONNECT_CONF="$HOME/.claude-connect.conf"
LAST_ACTIVE="$HOME/.cache/claude-last-active-mount"
CHECK_INTERVAL=30
HANG_TIMEOUT=5
HEAL_EVERY=10   # every N loops (~5 min) run quiet self-heal
_loop=0

_load_conf() {
    ACTIVE_MOUNT=""
    TUNNEL_PORT=""
    [ -f "$CONNECT_CONF" ] || return 0
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        v="$(printf '%s' "$v" | tr -d '\r')"
        case "$k" in
            ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
            TUNNEL_PORT) TUNNEL_PORT="$v" ;;
        esac
    done < "$CONNECT_CONF"
}

_set_active() {
    local id="$1"
    [ -n "$id" ] || return 0
    ACTIVE_MOUNT="$id"
    mkdir -p "$(dirname "$LAST_ACTIVE")" 2>/dev/null || true
    printf '%s\n' "$id" > "$LAST_ACTIVE" 2>/dev/null || true
    [ -f "$CONNECT_CONF" ] || return 0
    if grep -qiE '^ACTIVE_MOUNT=' "$CONNECT_CONF" 2>/dev/null; then
        sed -i "s/^ACTIVE_MOUNT=.*/ACTIVE_MOUNT=$id/I" "$CONNECT_CONF" 2>/dev/null || true
    else
        printf '\nACTIVE_MOUNT=%s\n' "$id" >> "$CONNECT_CONF"
    fi
}

_infer_active() {
    local id="" conf name lpath
    if [ -n "${ACTIVE_MOUNT:-}" ]; then
        printf '%s' "$ACTIVE_MOUNT"; return 0
    fi
    if [ -f "$LAST_ACTIVE" ]; then
        id="$(tr -d '\r\n' < "$LAST_ACTIVE" 2>/dev/null || true)"
        [ -n "$id" ] && [ -f "$CONF_DIR/$id.conf" ] && { printf '%s' "$id"; return 0; }
    fi
    [ -d "$CONF_DIR" ] || return 1
    for conf in "$CONF_DIR"/*.conf; do
        [ -f "$conf" ] || continue
        name=""; lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id) name="$v" ;;
                lpath|LOCAL_PATH) lpath="$v" ;;
            esac
        done < "$conf"
        lpath="${lpath//\\//}"
        if [ -n "$lpath" ] && grep -F " $lpath " /proc/mounts >/dev/null 2>&1; then
            printf '%s' "$name"; return 0
        fi
    done
    # Do NOT pick first alphabetical conf when ACTIVE_MOUNT empty - require explicit prefer/LAST_ACTIVE/mounted.
    return 1
}

if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

tunnel_up() {
    _load_conf
    [ -n "$TUNNEL_PORT" ] || return 1
    timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null
}

_umount_path() {
    local mp="$1"
    pkill -u "$USER" -f "sshfs .*${mp}" 2>/dev/null || true
    sleep 0.5
    timeout 5 fusermount -uz "$mp" 2>/dev/null || \
    timeout 5 fusermount3 -uz "$mp" 2>/dev/null || \
    timeout 5 umount -l "$mp" 2>/dev/null || true
}

_is_mounted() {
    grep -F " $1 " /proc/mounts >/dev/null 2>&1
}

_is_readable() {
    timeout "$HANG_TIMEOUT" ls "$1" >/dev/null 2>&1
}

while true; do
    sleep "$CHECK_INTERVAL"
    _loop=$((_loop + 1))
    [ -d "$CONF_DIR" ] || continue
    [ -x "$MOUNT_BIN" ] || continue
    _load_conf

    # Periodic quiet self-heal (covers buf finalize, empty ACTIVE_MOUNT, etc.)
    if [ $((_loop % HEAL_EVERY)) -eq 0 ]; then
        if [ -x /usr/local/bin/claude-self-heal ]; then
            timeout 20 /usr/local/bin/claude-self-heal --quiet >/dev/null 2>&1 || true
        elif [ -x "$HOME/.local/bin/claude-self-heal" ]; then
            timeout 20 "$HOME/.local/bin/claude-self-heal" --quiet >/dev/null 2>&1 || true
        fi
        _load_conf
    fi

    if ! tunnel_up; then
        # Edge: tunnel down -> tear down every sshfs under mounts/ (incl. zombies).
        # claude-mount down restores .git from .git.server-session when TCP still
        # briefly reachable (ConnectTimeout-bounded); otherwise recover on reconnect.
        if [ -x "$MOUNT_BIN" ]; then
            "$MOUNT_BIN" down 2>/dev/null || true
        fi
        for conf in "$CONF_DIR"/*.conf; do
            [ -f "$conf" ] || continue
            local_lpath=""
            while IFS='=' read -r k v; do
                v="${v#\"}" v="${v%\"}"
                case "$k" in lpath|LOCAL_PATH) local_lpath="$v" ;; esac
            done < "$conf"
            local_lpath="${local_lpath//\\//}"
            [ -n "$local_lpath" ] || continue
            if _is_mounted "$local_lpath"; then
                _umount_path "$local_lpath"
            fi
        done
        pkill -u "$USER" -f "sshfs .*$HOME/mounts" 2>/dev/null || true
        continue
    fi

    # Tunnel UP: ensure ACTIVE_MOUNT
    if [ -z "${ACTIVE_MOUNT:-}" ]; then
        if id="$(_infer_active)"; then
            _set_active "$id"
        fi
    fi
    [ -n "${ACTIVE_MOUNT:-}" ] || continue

    # Resolve active lpath
    active_conf="$CONF_DIR/$ACTIVE_MOUNT.conf"
    [ -f "$active_conf" ] || continue
    active_lpath=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in lpath|LOCAL_PATH) active_lpath="$v" ;; esac
    done < "$active_conf"
    active_lpath="${active_lpath//\\//}"
    [ -n "$active_lpath" ] || continue

    need_remount=0
    if ! _is_mounted "$active_lpath"; then
        need_remount=1
    elif ! _is_readable "$active_lpath"; then
        _umount_path "$active_lpath"
        sleep 1
        need_remount=1
    fi

    # Also fix any other hung mounts (non-active): umount only
    for conf in "$CONF_DIR"/*.conf; do
        [ -f "$conf" ] || continue
        local_id=""; local_lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id) local_id="$v" ;;
                lpath|LOCAL_PATH) local_lpath="$v" ;;
            esac
        done < "$conf"
        local_lpath="${local_lpath//\\//}"
        [ -n "$local_lpath" ] || continue
        [ "$local_id" = "$ACTIVE_MOUNT" ] && continue
        if _is_mounted "$local_lpath" && ! _is_readable "$local_lpath"; then
            _umount_path "$local_lpath"
            "$MOUNT_BIN" recover 2>/dev/null || true
        fi
    done

    if [ "$need_remount" = "1" ]; then
        "$MOUNT_BIN" recover 2>/dev/null || true
        "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true
        mkdir -p "$(dirname "$LAST_ACTIVE")" 2>/dev/null || true
        printf '%s\n' "$ACTIVE_MOUNT" > "$LAST_ACTIVE" 2>/dev/null || true
    fi
done
