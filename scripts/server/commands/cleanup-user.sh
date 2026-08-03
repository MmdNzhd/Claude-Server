#!/bin/bash
# cleanup-user.sh - ops hammer: tear down one user's mount/tunnel/mux litter
# Usage: sudo claude-server cleanup-user <username> [--force]
#        sudo bash scripts/server/commands/cleanup-user.sh <username> [--force]
#
# Safety:
#   - Refuses when a live Connect reverse-tunnel (UID port block) or keep-editor
#     (Cursor Remote server-main with established clients) is detected, unless
#     --force is passed.
#   - Always prints WARN: close Connect on the laptop first.
#   - Clears ACTIVE_MOUNT / TUNNEL_PORT / TUNNEL_SLOT / PORT from
#     ~/.claude-connect.conf but keeps LAPTOP_USER / LAPTOP_PATH / GIT_MODE / etc.
#
# Limitations:
#   - Processes in uninterruptible sleep (D-state), common for stuck git/rg over
#     a dead SSHFS, cannot be killed by kill/SIGKILL until the kernel I/O
#     completes or the FUSE mount is torn down. This script best-effort signals
#     them and documents leftovers; a reboot may still be required for hard D.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; exit 1; }
info() { printf "  %s\n" "$1"; }

FORCE=0
USERNAME=""

usage() {
    echo "Usage: sudo claude-server cleanup-user <username> [--force]"
    echo ""
    echo "Tear down sshfs/FUSE mounts, UID tunnel port holders, laptop-exec mux"
    echo "cache, and idle cursor-server for one Linux user. Clears ACTIVE_MOUNT"
    echo "and TUNNEL_* from ~/.claude-connect.conf (keeps LAPTOP_USER/PATH/GIT_MODE)."
    echo ""
    echo "  --force   proceed even if live Connect tunnel or keep-editor detected"
    echo ""
    echo "WARN: close Connect on the laptop first (or pass --force)."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            fail "unknown option: $1 (try --help)"
            ;;
        *)
            if [ -z "$USERNAME" ]; then
                USERNAME="$1"
                shift
            else
                fail "unexpected argument: $1"
            fi
            ;;
    esac
done

[ "$EUID" -eq 0 ] || fail "run as root: sudo claude-server cleanup-user <username> [--force]"
[ -n "$USERNAME" ] || { usage >&2; exit 1; }
id "$USERNAME" >/dev/null 2>&1 || fail "user not found: $USERNAME"

HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
[ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ] || fail "home directory missing for $USERNAME"
UID_NUM="$(id -u "$USERNAME")"
CONNECT_CONF="$HOME_DIR/.claude-connect.conf"
MOUNTS_ROOT="$HOME_DIR/mounts"
LE_CACHE="$HOME_DIR/.cache/laptop-exec"

_tunnel_block_base() {
    local uid="$1"
    if [ "$uid" -ge 1000 ] 2>/dev/null; then
        echo $((20000 + (uid - 1000) * 10))
    else
        echo 20020
    fi
}

_port_tcp_open() {
    local port="$1"
    timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${port}" 2>/dev/null
}

_user_has_live_block() {
    local base slot p
    base="$(_tunnel_block_base "$UID_NUM")"
    for slot in 0 1 2 3 4 5 6 7 8 9; do
        p=$((base + slot))
        if _port_tcp_open "$p"; then
            return 0
        fi
    done
    return 1
}

_estab_for_pid() {
    local pid="$1" n
    n=$(ss -tnp 2>/dev/null | grep -c "pid=${pid}," || true)
    printf '%s' "${n:-0}"
}

# keep-editor = Cursor Remote still has an established client on server-main
_user_has_keep_editor() {
    local pid cmd estab
    while read -r pid cmd; do
        [ -n "${pid:-}" ] || continue
        case "$cmd" in
            *server-main.js*) ;;
            *) continue ;;
        esac
        estab="$(_estab_for_pid "$pid")"
        estab=${estab:-0}
        if [ "$estab" -gt 0 ] 2>/dev/null; then
            return 0
        fi
    done < <(ps -u "$USERNAME" -o pid=,cmd= 2>/dev/null || true)
    return 1
}

_list_live_ports() {
    local base slot p
    base="$(_tunnel_block_base "$UID_NUM")"
    for slot in 0 1 2 3 4 5 6 7 8 9; do
        p=$((base + slot))
        if _port_tcp_open "$p"; then
            printf '%s ' "$p"
        fi
    done
}

echo ""
echo -e "${BOLD}=== cleanup-user: $USERNAME ===${NC}"
echo ""
warn "Close Connect on the laptop first (connect.bat / connect.sh), or use --force."
echo ""

LIVE=0
KEEP_EDITOR=0
if _user_has_live_block; then
    LIVE=1
fi
if _user_has_keep_editor; then
    KEEP_EDITOR=1
fi

if [ "$LIVE" -eq 1 ] || [ "$KEEP_EDITOR" -eq 1 ]; then
    [ "$LIVE" -eq 1 ] && warn "live Connect tunnel detected on UID block ports: $(_list_live_ports)"
    [ "$KEEP_EDITOR" -eq 1 ] && warn "keep-editor detected (cursor-server server-main with established clients)"
    if [ "$FORCE" -eq 0 ]; then
        fail "refusing cleanup while live Connect / keep-editor is active (pass --force to override)"
    fi
    warn "--force: proceeding despite live Connect / keep-editor"
fi

PORT_BASE="$(_tunnel_block_base "$UID_NUM")"
info "UID=$UID_NUM PORT_BASE=$PORT_BASE (ports ${PORT_BASE}..$((PORT_BASE + 9)))"

# --- 1. pkill sshfs for user -------------------------------------------------
echo ""
echo -e "${BOLD}1. sshfs processes${NC}"
if pkill -u "$USERNAME" -f 'sshfs ' 2>/dev/null; then
    ok "pkill sshfs for $USERNAME"
    sleep 0.3
else
    ok "no sshfs processes for $USERNAME"
fi
# Orphan sftp transports left after sshfs death
pkill -u "$USERNAME" -f -- '-s sftp' 2>/dev/null || true

# --- 2. fusermount mounts under ~/mounts/* -----------------------------------
echo ""
echo -e "${BOLD}2. FUSE mounts under $MOUNTS_ROOT${NC}"
UMOUNTED=0
if [ -d "$MOUNTS_ROOT" ]; then
    # Prefer /proc/mounts so we catch fuse.sshfs even if dir listing hangs
    while IFS= read -r mp; do
        [ -n "$mp" ] || continue
        case "$mp" in
            "$MOUNTS_ROOT"|"$MOUNTS_ROOT"/) continue ;;
            "$MOUNTS_ROOT"/*) ;;
            *) continue ;;
        esac
        if timeout 5 fusermount -uz "$mp" 2>/dev/null \
            || timeout 5 fusermount3 -uz "$mp" 2>/dev/null \
            || timeout 5 umount -l "$mp" 2>/dev/null; then
            ok "unmounted $mp"
            UMOUNTED=$((UMOUNTED + 1))
        else
            warn "could not unmount $mp (may already be gone)"
        fi
    done < <(awk -v root="$MOUNTS_ROOT" '$2 ~ ("^" root "/") { print $2 }' /proc/mounts 2>/dev/null || true)

    # Also try direct children (empty dirs that still look mounted to tools)
    for mp in "$MOUNTS_ROOT"/*; do
        [ -e "$mp" ] || continue
        [ -d "$mp" ] || continue
        if mountpoint -q "$mp" 2>/dev/null; then
            timeout 5 fusermount -uz "$mp" 2>/dev/null \
                || timeout 5 fusermount3 -uz "$mp" 2>/dev/null \
                || timeout 5 umount -l "$mp" 2>/dev/null \
                || true
            UMOUNTED=$((UMOUNTED + 1))
        fi
    done
fi
[ "$UMOUNTED" -eq 0 ] && ok "no FUSE mounts under mounts/"
[ "$UMOUNTED" -gt 0 ] && ok "fusermount attempts=$UMOUNTED"

# --- 3. best-effort D-state git/rg -------------------------------------------
echo ""
echo -e "${BOLD}3. D-state git/rg (best-effort)${NC}"
info "LIMITATION: D-state (uninterruptible sleep) cannot be forced off by kill -9;"
info "  FUSE teardown above is the real fix; leftovers may need reboot."
D_LEFT=0
while read -r pid state cmd; do
    [ -n "${pid:-}" ] || continue
    case "$state" in
        D*) ;;
        *) continue ;;
    esac
    case "$cmd" in
        *git*|*rg*|*ripgrep*) ;;
        *) continue ;;
    esac
    warn "signaling D-state pid=$pid state=$state cmd=$cmd (may be ignored by kernel)"
    kill -TERM "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
    if kill -0 "$pid" 2>/dev/null; then
        warn "still alive after KILL (D-state): pid=$pid"
        D_LEFT=$((D_LEFT + 1))
    fi
done < <(ps -u "$USERNAME" -o pid=,state=,cmd= 2>/dev/null || true)
if [ "$D_LEFT" -eq 0 ]; then
    ok "no leftover D-state git/rg (or none found)"
else
    warn "$D_LEFT D-state git/rg process(es) still alive after best-effort kill"
fi

# --- 4. cursor-server (safe: idle only; --force: all) ------------------------
echo ""
echo -e "${BOLD}4. cursor-server processes${NC}"
_kill_tree() {
    local root="$1" c
    [ -n "$root" ] || return 0
    while read -r c; do
        c=$(echo "$c" | tr -d ' ')
        [ -n "$c" ] || continue
        _kill_tree "$c"
    done < <(ps -o pid= --ppid "$root" 2>/dev/null || true)
    kill -TERM "$root" 2>/dev/null || true
    sleep 0.15
    kill -KILL "$root" 2>/dev/null || true
}

CS_KILLED=0
CS_SKIPPED=0
while read -r pid cmd; do
    [ -n "${pid:-}" ] || continue
    case "$cmd" in
        *server-main.js*) ;;
        *) continue ;;
    esac
    estab="$(_estab_for_pid "$pid")"
    estab=${estab:-0}
    if [ "$estab" -gt 0 ] 2>/dev/null && [ "$FORCE" -eq 0 ]; then
        # Should not reach here (gate refused), but belt-and-suspenders
        warn "skip cursor-server pid=$pid (estab=$estab, not --force)"
        CS_SKIPPED=$((CS_SKIPPED + 1))
        continue
    fi
    _kill_tree "$pid"
    CS_KILLED=$((CS_KILLED + 1))
done < <(ps -u "$USERNAME" -o pid=,cmd= 2>/dev/null || true)
ok "cursor-server trees killed=$CS_KILLED skipped=$CS_SKIPPED"

# --- 5. fuser on UID tunnel port block ---------------------------------------
echo ""
echo -e "${BOLD}5. fuser UID tunnel ports ${PORT_BASE}..$((PORT_BASE + 9))${NC}"
FUSER_HIT=0
for slot in 0 1 2 3 4 5 6 7 8 9; do
    p=$((PORT_BASE + slot))
    if command -v fuser >/dev/null 2>&1; then
        if fuser -k "${p}/tcp" >/dev/null 2>&1; then
            ok "fuser -k ${p}/tcp"
            FUSER_HIT=$((FUSER_HIT + 1))
        fi
    else
        warn "fuser not installed; skip port $p"
        break
    fi
done
[ "$FUSER_HIT" -eq 0 ] && ok "no fuser hits on UID port block"
[ "$FUSER_HIT" -gt 0 ] && ok "fuser killed holders on $FUSER_HIT port(s)"

# --- 6. laptop-exec mux/cache ------------------------------------------------
echo ""
echo -e "${BOLD}6. laptop-exec cache${NC}"
if [ -d "$LE_CACHE" ]; then
    # Prefer removing mux sockets/locks; wipe whole cache dir (safe ops hammer)
    rm -rf "$LE_CACHE"
    ok "removed $LE_CACHE"
else
    ok "no laptop-exec cache at $LE_CACHE"
fi

# --- 7. clear session keys from connect conf ---------------------------------
echo ""
echo -e "${BOLD}7. ~/.claude-connect.conf session keys${NC}"
if [ -f "$CONNECT_CONF" ]; then
    tmp="${CONNECT_CONF}.cleanup.$$"
    # Drop session/tunnel keys; keep LAPTOP_USER, LAPTOP_PATH, GIT_MODE, LAPTOP_OS, etc.
    grep -vE '^(ACTIVE_MOUNT|active_mount|TUNNEL_PORT|TUNNEL_SLOT|PORT)=' "$CONNECT_CONF" > "$tmp" 2>/dev/null \
        || { rm -f "$tmp"; fail "failed rewriting $CONNECT_CONF"; }
    printf '# cleanup-user cleared ACTIVE_MOUNT/TUNNEL_PORT/TUNNEL_SLOT/PORT at %s\n' \
        "$(date -Is 2>/dev/null || date)" >> "$tmp"
    chown "$USERNAME:$USERNAME" "$tmp" 2>/dev/null || true
    chmod 600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$CONNECT_CONF"
    ok "cleared ACTIVE_MOUNT / TUNNEL_PORT / TUNNEL_SLOT / PORT (kept LAPTOP_* / GIT_MODE)"
else
    warn "no connect conf at $CONNECT_CONF"
fi

echo ""
echo -e "${BOLD}Done.${NC} User $USERNAME cleaned. Reconnect via connect.bat / connect.sh when ready."
echo ""
exit 0
