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
set -uo pipefail

LOG=/var/log/claude-mount-reaper.log
RESPONSE_TIMEOUT=3     # seconds to wait for `stat` on the mountpoint
MIN_AGE_SECONDS=60     # grace period - a mount still establishing is not "stuck"

_log() {
    printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$LOG" 2>/dev/null
    logger -t claude-mount-reaper "$1"
}

[ -f "$LOG" ] || { touch "$LOG" 2>/dev/null; chmod 600 "$LOG" 2>/dev/null; }

killed=0

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
# init) serve no controlling sshfs anymore, so they are always safe to kill regardless
# of age. This does not touch sftp subprocesses that still have a live sshfs parent.
while read -r pid ppid secs user cmd; do
    [ -n "${pid:-}" ] || continue
    [ "${ppid:-0}" = "1" ] || continue
    _log "killing orphaned sftp transport pid=$pid age_s=$secs user=$user"
    kill -9 "$pid" 2>/dev/null || true
    killed=$((killed + 1))
done < <(ps -eo pid,ppid,etimes,user,cmd | grep -- '-s sftp' | grep -v grep)

if [ "$killed" -gt 0 ]; then
    _log "reap complete killed=$killed"
fi

exit 0
