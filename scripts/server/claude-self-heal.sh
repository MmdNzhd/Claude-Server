#!/bin/bash
# claude-self-heal — idempotent per-user repair for known connect/mount/git footguns.
# Safe to run on login, cron, or manually: claude-self-heal [--quiet]
# Covers: stale/zombie mounts, empty ACTIVE_MOUNT, orphan sshfs, stuck connect log bufs,
# CRLF bins, Cursor git-off, tunnel-up remount of active project.

set -u

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

_log() { [ "$QUIET" = "1" ] || echo "self-heal: $*" >&2; }

HOME="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
[ -n "$HOME" ] && [ -d "$HOME" ] || exit 0
USER_NAME="$(id -un)"

CONNECT_CONF="$HOME/.claude-connect.conf"
MOUNTS_DIR="$HOME/mounts"
CONF_DIR="$HOME/.claude-mounts.d"
LAST_ACTIVE="$HOME/.cache/claude-last-active-mount"
TUNNEL_PORT=""
GIT_MODE=""
ACTIVE_MOUNT=""

if [ -f "$CONNECT_CONF" ]; then
    while IFS='=' read -r k v || [ -n "$k" ]; do
        v="${v#\"}"; v="${v%\"}"
        v="$(printf '%s' "$v" | tr -d '\r')"
        case "$k" in
            TUNNEL_PORT) TUNNEL_PORT="$v" ;;
            GIT_MODE|git_mode) GIT_MODE="$v" ;;
            ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
        esac
    done < "$CONNECT_CONF"
fi

_tunnel_up() {
    [ -n "$TUNNEL_PORT" ] || return 1
    timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null
}

_mount_bin() {
    local b
    for b in "$HOME/.local/bin/claude-mount" /usr/local/bin/claude-mount /usr/local/lib/claude-mount; do
        if [ -x "$b" ]; then echo "$b"; return 0; fi
    done
    return 1
}

_set_active_mount() {
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
    _log "ACTIVE_MOUNT=$id"
}

_infer_active_mount() {
    local id=""
    if [ -n "${ACTIVE_MOUNT:-}" ]; then
        printf '%s' "$ACTIVE_MOUNT"
        return 0
    fi
    if [ -f "$LAST_ACTIVE" ]; then
        id="$(tr -d '\r\n' < "$LAST_ACTIVE" 2>/dev/null || true)"
        if [ -n "$id" ] && [ -f "$CONF_DIR/$id.conf" ]; then
            printf '%s' "$id"
            return 0
        fi
    fi
    # Prefer a conf whose lpath is already in /proc/mounts
    local conf name lpath
    if [ -d "$CONF_DIR" ]; then
        for conf in "$CONF_DIR"/*.conf; do
            [ -f "$conf" ] || continue
            name=""; lpath=""
            while IFS='=' read -r k v; do
                v="${v#\"}"; v="${v%\"}"; v="$(printf '%s' "$v" | tr -d '\r')"
                case "$k" in
                    id) name="$v" ;;
                    lpath|LOCAL_PATH) lpath="$v" ;;
                esac
            done < "$conf"
            lpath="${lpath//\\//}"
            if [ -n "$lpath" ] && grep -F " $lpath " /proc/mounts >/dev/null 2>&1; then
                printf '%s' "$name"
                return 0
            fi
        done
        # First configured project
        for conf in "$CONF_DIR"/*.conf; do
            [ -f "$conf" ] || continue
            name=""
            while IFS='=' read -r k v; do
                v="${v#\"}"; v="${v%\"}"; v="$(printf '%s' "$v" | tr -d '\r')"
                [ "$k" = "id" ] && name="$v"
            done < "$conf"
            if [ -n "$name" ]; then
                printf '%s' "$name"
                return 0
            fi
        done
    fi
    return 1
}

_heal_connect_conf() {
    [ -f "$CONNECT_CONF" ] || return 0
    local mode_lc
    mode_lc="$(printf '%s' "${GIT_MODE:-}" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
    case "$mode_lc" in
        off|hide|server|fast|slow|on|yes|1|no|none|0|disabled) ;;
        "")
            if ! grep -qiE '^GIT_MODE=' "$CONNECT_CONF" 2>/dev/null; then
                printf '\nGIT_MODE=off\n' >> "$CONNECT_CONF"
                _log "set GIT_MODE=off in connect conf"
                GIT_MODE="off"
            fi
            ;;
        *)
            if grep -qiE '^GIT_MODE=' "$CONNECT_CONF" 2>/dev/null; then
                sed -i 's/^GIT_MODE=.*/GIT_MODE=off/I' "$CONNECT_CONF" 2>/dev/null || true
            else
                printf '\nGIT_MODE=off\n' >> "$CONNECT_CONF"
            fi
            _log "normalized weird GIT_MODE → off"
            GIT_MODE="off"
            ;;
    esac
    # Empty ACTIVE_MOUNT while mounts are configured → infer + persist
    local inferred
    ACTIVE_MOUNT="$(printf '%s' "${ACTIVE_MOUNT:-}" | tr -d '\r\n ')"
    if [ -z "$ACTIVE_MOUNT" ]; then
        if inferred="$(_infer_active_mount)"; then
            _set_active_mount "$inferred"
        fi
    fi
}

_heal_laptop_exec_crlf() {
    local sys="/usr/local/bin/laptop-exec"
    local dst="$HOME/.local/bin/laptop-exec"
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    if [ -x "$sys" ]; then
        if [ ! -f "$dst" ] || [ "$sys" -nt "$dst" ] || grep -q $'\r' "$dst" 2>/dev/null; then
            cp -f "$sys" "$dst" 2>/dev/null || true
            chmod 755 "$dst" 2>/dev/null || true
            sed -i 's/\r$//' "$dst" 2>/dev/null || true
            _log "refreshed laptop-exec (CRLF-safe)"
        else
            sed -i 's/\r$//' "$dst" 2>/dev/null || true
        fi
    elif [ -f "$dst" ]; then
        sed -i 's/\r$//' "$dst" 2>/dev/null || true
    fi
}

_heal_missing_user_bins() {
    local name sys dst
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    for name in laptop-exec laptop-exec-setup claude-self-heal claude-automount claude-mount claude-watchdog; do
        sys="/usr/local/bin/$name"
        [ -x "$sys" ] || continue
        dst="$HOME/.local/bin/$name"
        if [ ! -f "$dst" ] || [ "$sys" -nt "$dst" ] || grep -q $'\r' "$dst" 2>/dev/null; then
            cp -f "$sys" "$dst" 2>/dev/null || true
            chmod 755 "$dst" 2>/dev/null || true
            sed -i 's/\r$//' "$dst" 2>/dev/null || true
            _log "refreshed $name"
        fi
    done
}

_heal_bin_crlf_all() {
    local f
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    for f in \
        "$HOME/.local/bin/laptop-exec" \
        "$HOME/.local/bin/laptop-exec-setup" \
        "$HOME/.local/bin/claude-mount" \
        "$HOME/.local/bin/claude-automount" \
        "$HOME/.local/bin/claude-self-heal" \
        "$HOME/.local/bin/claude-git-setup" \
        "$HOME/.local/bin/claude-watchdog"
    do
        [ -f "$f" ] || continue
        if grep -q $'\r' "$f" 2>/dev/null; then
            sed -i 's/\r$//' "$f" 2>/dev/null || true
            chmod 755 "$f" 2>/dev/null || true
            _log "stripped CRLF $(basename "$f")"
        fi
    done
}

_heal_cursor_git_off() {
    local mode_lc
    mode_lc="$(printf '%s' "${GIT_MODE:-off}" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
    case "$mode_lc" in
        server|on|yes|1|slow) return 0 ;;
    esac
    python3 - <<'PY' 2>/dev/null || true
import json, os
home = os.path.expanduser("~")
want = {
    "git.enabled": False,
    "git.autoRepositoryDetection": False,
    "git.detectSubmodules": False,
    "git.repositoryScanMaxDepth": 0,
}
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
    changed = False
    for k, v in want.items():
        if data.get(k) != v:
            data[k] = v
            changed = True
    if "git.path" in data:
        del data["git.path"]
        changed = True
    if changed or not os.path.isfile(path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
PY
}

_heal_workspace_git_pollution() {
    [ -d "$MOUNTS_DIR" ] || return 0
    python3 - <<'PY' 2>/dev/null || true
import json, os
home = os.path.expanduser("~")
mroot = os.path.join(home, "mounts")
keys = ("git.enabled", "git.autoRepositoryDetection", "git.detectSubmodules", "git.repositoryScanMaxDepth", "git.path")
if not os.path.isdir(mroot):
    raise SystemExit(0)
for mid in os.listdir(mroot):
    mp = os.path.join(mroot, mid)
    if not os.path.isdir(mp):
        continue
    candidates = [os.path.join(mp, ".vscode", "settings.json")]
    try:
        for name in os.listdir(mp):
            if name.startswith("."):
                continue
            p = os.path.join(mp, name, ".vscode", "settings.json")
            if os.path.isfile(p):
                candidates.append(p)
    except OSError:
        pass
    for path in candidates:
        if not os.path.isfile(path):
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        changed = False
        for k in keys:
            if k in data:
                del data[k]
                changed = True
        if changed:
            try:
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
                    f.write("\n")
            except OSError:
                pass
PY
}

_heal_stale_mounts() {
    [ -d "$MOUNTS_DIR" ] || return 0
    if _tunnel_up; then
        return 0
    fi
    local d mp
    for d in "$MOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        mp="${d%/}"
        if grep -F " $mp " /proc/mounts >/dev/null 2>&1; then
            _log "stale mount (tunnel down) -> umount $mp"
            pkill -u "$USER_NAME" -f "sshfs .*${mp}" 2>/dev/null || true
            timeout 5 fusermount -uz "$mp" 2>/dev/null || timeout 5 fusermount3 -uz "$mp" 2>/dev/null || timeout 5 umount -l "$mp" 2>/dev/null || true
        fi
    done
    # orphan sshfs with no /proc entry
    pkill -u "$USER_NAME" -f "sshfs .*$MOUNTS_DIR" 2>/dev/null || true
}

_heal_zombie_readable() {
    # Tunnel UP but mount in /proc is unreadable → force remount path later
    [ -d "$MOUNTS_DIR" ] || return 0
    _tunnel_up || return 0
    local d mp
    for d in "$MOUNTS_DIR"/*/; do
        [ -d "$d" ] || continue
        mp="${d%/}"
        grep -F " $mp " /proc/mounts >/dev/null 2>&1 || continue
        if ! timeout 3 ls "$mp" >/dev/null 2>&1; then
            _log "zombie mount (unreadable) -> umount $mp"
            pkill -u "$USER_NAME" -f "sshfs .*${mp}" 2>/dev/null || true
            timeout 5 fusermount -uz "$mp" 2>/dev/null || timeout 5 umount -l "$mp" 2>/dev/null || true
        fi
    done
}

_heal_connect_log_bufs() {
    local logdir="$HOME/.claude/logs"
    [ -d "$logdir" ] || return 0
    local f day dest
    for f in "$logdir"/.connect-buf-*.tmp; do
        [ -f "$f" ] || continue
        day="$(date -u +%Y%m%d -r "$f" 2>/dev/null || date -u +%Y%m%d)"
        dest="$logdir/connect-$day.log"
        cat "$f" >> "$dest" 2>/dev/null || true
        rm -f "$f" 2>/dev/null || true
        chmod 600 "$dest" 2>/dev/null || true
        _log "finalized $(basename "$f") -> $(basename "$dest")"
    done
    # retention: drop connect logs older than 7 days
    find "$logdir" -type f -name 'connect-*.log' -mtime +7 -delete 2>/dev/null || true
}

_heal_remove_shim() {
    local p="$HOME/.local/bin/git-via-laptop-exec"
    if [ -e "$p" ]; then
        rm -f "$p" 2>/dev/null || true
        _log "removed git-via-laptop-exec shim"
    fi
}

_heal_active_remount() {
    _tunnel_up || return 0
    local mb id lpath conf
    mb="$(_mount_bin)" || return 0
    id="${ACTIVE_MOUNT:-}"
    if [ -z "$id" ]; then
        id="$(_infer_active_mount || true)"
        [ -n "$id" ] && _set_active_mount "$id"
    fi
    [ -n "$id" ] || return 0
    conf="$CONF_DIR/$id.conf"
    [ -f "$conf" ] || return 0
    lpath=""
    while IFS='=' read -r k v; do
        v="${v#\"}"; v="${v%\"}"; v="$(printf '%s' "$v" | tr -d '\r')"
        case "$k" in lpath|LOCAL_PATH) lpath="$v" ;; esac
    done < "$conf"
    lpath="${lpath//\\//}"
    if [ -n "$lpath" ] && grep -F " $lpath " /proc/mounts >/dev/null 2>&1; then
        if timeout 3 ls "$lpath" >/dev/null 2>&1; then
            mkdir -p "$(dirname "$LAST_ACTIVE")" 2>/dev/null || true
            printf '%s\n' "$id" > "$LAST_ACTIVE" 2>/dev/null || true
            return 0
        fi
    fi
    _log "tunnel up -> remount $id"
    "$mb" recover 2>/dev/null || true
    "$mb" up "$id" 2>/dev/null || true
    mkdir -p "$(dirname "$LAST_ACTIVE")" 2>/dev/null || true
    printf '%s\n' "$id" > "$LAST_ACTIVE" 2>/dev/null || true
}

_heal_bashrc_timeout() {
    local br="$HOME/.bashrc"
    [ -f "$br" ] || return 0
    grep -q 'claude-automount' "$br" 2>/dev/null || return 0
    if grep -qE 'timeout[[:space:]]+10[[:space:]].*claude-automount' "$br" 2>/dev/null; then
        return 0
    fi
    sed -i -E 's@(\$HOME/\.local/bin/claude-automount|/usr/local/bin/claude-automount)[[:space:]]+2>/dev/null@timeout 10 \1 2>/dev/null@g' "$br" 2>/dev/null || true
    if ! grep -qE 'timeout[[:space:]]+10[[:space:]].*claude-automount' "$br" 2>/dev/null; then
        # last resort: replace bare invocation line
        sed -i 's@/usr/local/bin/claude-automount 2>/dev/null@timeout 10 /usr/local/bin/claude-automount 2>/dev/null@g' "$br" 2>/dev/null || true
        sed -i 's@"\$HOME/\.local/bin/claude-automount" 2>/dev/null@timeout 10 "\$HOME/.local/bin/claude-automount" 2>/dev/null@g' "$br" 2>/dev/null || true
    fi
    _log "bashrc automount timeout wrap"
}

# Run
_heal_connect_conf
_heal_laptop_exec_crlf
_heal_missing_user_bins
_heal_bin_crlf_all
_heal_cursor_git_off
_heal_remove_shim
_heal_bashrc_timeout
_heal_connect_log_bufs
_heal_stale_mounts
_heal_zombie_readable
if [ -d "$MOUNTS_DIR" ] && timeout 3 ls "$MOUNTS_DIR" >/dev/null 2>&1; then
    _heal_workspace_git_pollution
fi
_heal_active_remount

[ "$QUIET" = "1" ] || _log "done"
exit 0
