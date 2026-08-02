#!/bin/bash
# claude-perm-drift-check.sh - detect the 2026-08-02 class of failure early: any real
# mountpoint's directory losing its execute/search bit (mode 644 or similar, no u+x)
# blocks every non-root login/exec under it. The original incident's own verification
# (find / -xdev -type d -perm 0644) was scoped to one filesystem and missed /boot on a
# separate mount - this checks every real local mountpoint, not just /.
#
# Cron: every 15 min via /etc/cron.d/claude-perm-drift (see install.sh). Logs findings
# to journald (tag claude-perm-drift) and a flat file for humans; does not fix anything
# automatically - drift here means "go look," not "auto-repair a possibly-adversarial state."

set -uo pipefail

LOG_FILE="/var/log/claude-perm-drift.log"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Real local filesystems only - skip virtual/network fs where "no execute bit" is either
# meaningless (procfs/sysfs) or someone else's problem (nfs/cifs/sshfs/fuse mounts).
SKIP_FSTYPES='proc|sysfs|devtmpfs|devpts|tmpfs|cgroup|cgroup2|pstore|bpf|tracefs|securityfs|debugfs|mqueue|hugetlbfs|autofs|binfmt_misc|configfs|fusectl|nfs|nfs4|cifs|fuse.sshfs|fuse'

mapfile -t MOUNTS < <(findmnt -rn -o TARGET,FSTYPE | awk -v skip="$SKIP_FSTYPES" '
  BEGIN { split(skip, arr, "|"); for (i in arr) skipset[arr[i]] = 1 }
  { if (!($2 in skipset)) print $1 }
')

FOUND=0
DETAIL=""
for m in "${MOUNTS[@]}"; do
    [ -d "$m" ] || continue
    while IFS= read -r -d '' bad; do
        FOUND=$((FOUND + 1))
        DETAIL="${DETAIL}${bad}\n"
    done < <(find "$m" -xdev -maxdepth 6 -type d ! -perm -u+x -print0 2>/dev/null)
done

if [ "$FOUND" -gt 0 ]; then
    MSG="PERM_DRIFT_FOUND count=${FOUND} ts=${TS} - see ${LOG_FILE}"
    logger -t claude-perm-drift -p daemon.warning "$MSG"
    {
        echo "[$TS] $MSG"
        printf '%b' "$DETAIL"
    } >> "$LOG_FILE"
    exit 1
else
    logger -t claude-perm-drift -p daemon.info "PERM_DRIFT_OK ts=${TS} mounts_checked=${#MOUNTS[@]}"
    exit 0
fi
