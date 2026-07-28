#!/bin/bash
# claude-mount-reaper.sh - kill genuinely-stuck sshfs mounts (runs every 10 min via cron)
#
# claude-mount.sh wraps its foreground sshfs call in `timeout 30`, but sshfs is invoked
# with `-o reconnect`, which forks a persistent background daemon once mounted - that
# daemon (and the ssh -s sftp subprocess it spawns) is NOT bound by the foreground
# timeout. If the underlying tunnel/port ends up in a bad state, `reconnect` means it
# just keeps retrying forever instead of dying, and a hung helper can survive for days,
# holding the reverse-tunnel port "occupied" and blocking reclaim for every subsequent
# connect attempt (observed directly: one process stuck for 39+ hours in production).
#
# IMPORTANT (learned the hard way): process AGE alone is not a valid "stuck" signal.
# A healthy sshfs mount is *supposed* to run for the entire work session, potentially
# many hours - an early version of this script killed long-running but perfectly
# healthy mounts on age alone, which unmounted active work and made files "disappear"
# (no data was actually lost - the laptop disk is always the source of truth - but it
# was a real, avoidable disruption). This version only kills a mount whose actual
# mountpoint fails to respond to a bounded `stat`, i.e. proven unresponsive, not just old.
#
# Pass 2 also requires MIN_AGE_SECONDS (same grace) — young orphan sftp during WD thrash
# must not be scythed at age_s=5.
#
# Pass 3: fusermount kernel-only fuse.sshfs under /home/*/mounts/ (no sshfs PID / unreadable).
# Pass 4: runuser self-heal when ACTIVE_MOUNT + tunnel effective + not mounted (cap 4/tick).
set -uo pipefail

LOG=/var/log/claude-mount-reaper.log
RESPONSE_TIMEOUT=3     # seconds to wait for `stat` on the mountpoint
MIN_AGE_SECONDS=60     # grace period - a mount still establishing is not "stuck"
PASS4_MAX=4

_log() {
    printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$LOG" 2>/dev/null
    logger -t claude-mount-reaper "$1"
}

[ -f "$LOG" ] || { touch "$LOG" 2>/dev/null; chmod 600 "$LOG" 2>/dev/null; }

killed=0
umounted=0

# Pass 1: sshfs daemons - kill only if the actual mountpoint is unresponsive.
while read -r pid secs user cmd; do
    [ -n "${pid:-}" ] || continue
    [ "${secs:-0}" -ge "$MIN_AGE_SECONDS" ] || continue
    mountpoint=$(printf '%s' "$cmd" | grep -oE '/home/[^ ]+/mounts/[^ ]+' | head -1)
    if [ -z "$mountpoint" ]; then
        continue  # can't identify the mountpoint - do not guess, leave it alone
    fi
    if timeout "$RESPONSE_TIMEOUT" stat "$mountpoint" >/dev/null 2>&1; then
        continue  # responsive - healthy, no matter how long it's been running
    fi
    _log "killing unresponsive sshfs pid=$pid age_s=$secs user=$user mountpoint=$mountpoint"
    kill -9 "$pid" 2>/dev/null || true
    killed=$((killed + 1))
done < <(ps -eo pid,etimes,user,cmd | grep 'sshfs ' | grep -v grep)

# Pass 2: orphaned `ssh ... -s sftp` transports (parent already dead - PPID 1, reaped by
# init) serve no controlling sshfs anymore. Still require MIN_AGE_SECONDS — young orphans
# during WD thrash (age_s=5) must wait for grace before kill.
while read -r pid ppid secs user cmd; do
    [ -n "${pid:-}" ] || continue
    [ "${ppid:-0}" = "1" ] || continue
    case "${secs:-}" in
        ''|*[!0-9]*) continue ;;
    esac
    [ "${secs}" -ge "$MIN_AGE_SECONDS" ] || continue
    _log "killing orphaned sftp transport pid=$pid age_s=$secs user=$user"
    kill -9 "$pid" 2>/dev/null || true
    killed=$((killed + 1))
done < <(ps -eo pid,ppid,etimes,user,cmd | grep -- '-s sftp' | grep -v grep)

# Pass 3: kernel-only fuse.sshfs under /home/*/mounts/ — fusermount when no sshfs PID
# or mount unreadable. Never umount if sshfs PID alive AND ls/stat OK.
_pass3_has_sshfs_pid() {
    local mp="$1"
    pgrep -f "sshfs .*${mp}" >/dev/null 2>&1
}

while IFS= read -r line; do
    [ -n "$line" ] || continue
    # fields: src mountpoint fstype ...
    mp="$(printf '%s' "$line" | awk '{print $2}')"
    fstype="$(printf '%s' "$line" | awk '{print $3}')"
    case "$fstype" in
        fuse.sshfs|fuse) ;;
        *) continue ;;
    esac
    case "$mp" in
        /home/*/mounts/*) ;;
        *) continue ;;
    esac
    # Never umount the mounts parent itself
    case "$mp" in
        */mounts|*/mounts/) continue ;;
    esac

    readable=0
    if timeout "$RESPONSE_TIMEOUT" ls "$mp" >/dev/null 2>&1; then
        readable=1
    fi
    has_pid=0
    if _pass3_has_sshfs_pid "$mp"; then
        has_pid=1
    fi

    # Healthy: PID alive + readable → leave alone
    if [ "$has_pid" -eq 1 ] && [ "$readable" -eq 1 ]; then
        continue
    fi

    # Candidate: no PID, or unreadable (zombie / stuck)
    if [ "$has_pid" -eq 0 ] || [ "$readable" -eq 0 ]; then
        _log "pass3 fusermount zombie mountpoint=$mp has_pid=$has_pid readable=$readable"
        timeout 5 fusermount -uz "$mp" 2>/dev/null \
            || timeout 5 fusermount3 -uz "$mp" 2>/dev/null \
            || timeout 5 umount -l "$mp" 2>/dev/null \
            || true
        umounted=$((umounted + 1))
    fi
done < <(awk '$3 ~ /fuse/ && $2 ~ /^\/home\/[^\/]+\/mounts\// {print}' /proc/mounts 2>/dev/null || true)

# Pass 4: ACTIVE_MOUNT + tunnel_up_effective + not mounted → runuser self-heal (cap 4)
_pass4=0
if [ -f /usr/local/lib/claude-server/claude-tunnel-reacquire.sh ]; then
    # shellcheck source=/dev/null
    . /usr/local/lib/claude-server/claude-tunnel-reacquire.sh
fi
for home in /home/*/; do
    [ "$_pass4" -ge "$PASS4_MAX" ] && break
    u="$(basename "$home")"
    [ "$u" = "lost+found" ] && continue
    id "$u" >/dev/null 2>&1 || continue
    conf="$home/.claude-connect.conf"
    [ -f "$conf" ] || continue
    am="$(grep -E '^ACTIVE_MOUNT=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
    [ -n "$am" ] || continue
    lpath="$home/mounts/$am"
    # Cheap skip if already mounted and readable
    if grep -F " $lpath " /proc/mounts >/dev/null 2>&1; then
        if timeout 2 ls "$lpath" >/dev/null 2>&1; then
            continue
        fi
    fi
    # Need effective tunnel for this user
    HOME="$home" USER_NAME="$u"
    TUNNEL_PORT="$(grep -E '^TUNNEL_PORT=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
    LAPTOP_USER="$(grep -E '^LAPTOP_USER=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
    LAPTOP_HOSTKEY_FP="$(grep -E '^LAPTOP_HOSTKEY_FP=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
    LAPTOP_OS="$(grep -E '^LAPTOP_OS=' "$conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r')"
    CONNECT_CONF="$conf"
    if ! declare -F tunnel_up_effective >/dev/null 2>&1; then
        continue
    fi
    if ! HOME="$home" TUNNEL_PORT="$TUNNEL_PORT" LAPTOP_USER="$LAPTOP_USER" \
        LAPTOP_HOSTKEY_FP="$LAPTOP_HOSTKEY_FP" LAPTOP_OS="$LAPTOP_OS" \
        CONNECT_CONF="$conf" tunnel_up_effective; then
        continue
    fi
    if [ -x /usr/local/bin/claude-self-heal ]; then
        _log "pass4 runuser heal user=$u active=$am"
        timeout 60 runuser -u "$u" -- /usr/local/bin/claude-self-heal --quiet >/dev/null 2>&1 || true
        _pass4=$((_pass4 + 1))
    fi
done

if [ "$killed" -gt 0 ] || [ "$umounted" -gt 0 ] || [ "${_pass4:-0}" -gt 0 ]; then
    _log "reap complete killed=$killed umounted=$umounted pass4=$_pass4"
fi

exit 0
