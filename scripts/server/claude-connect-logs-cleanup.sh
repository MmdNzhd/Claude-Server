#!/bin/bash
# claude-connect-logs-cleanup.sh - delete per-user connect logs older than 1 day (nightly)
# Installed as /usr/local/bin/claude-connect-logs-cleanup + /etc/cron.d/claude-connect-logs
set -uo pipefail

# find may return non-zero when some /home entries are unreadable; never fail the cron job.
while IFS= read -r d; do
    [ -d "$d" ] || continue
    find "$d" -type f -mtime +1 -delete 2>/dev/null || true
done < <(find /home -mindepth 3 -maxdepth 3 -path '/home/*/.claude/logs' -type d 2>/dev/null || true)

exit 0
