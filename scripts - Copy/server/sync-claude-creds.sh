#!/bin/bash
# Sync Claude credentials from smart to all users
# Run as root: sudo /usr/local/bin/sync-claude-creds.sh
# Cron: */5 * * * * root /usr/local/bin/sync-claude-creds.sh

SMART_CREDS="/home/smart/.claude/.credentials.json"
SMART_CLAUDE_JSON="/home/smart/.claude.json"

if [ ! -f "$SMART_CREDS" ]; then
    echo "ERROR: $SMART_CREDS not found — smart must login first: su - smart && claude"
    exit 1
fi

if [ ! -f "$SMART_CLAUDE_JSON" ]; then
    echo "ERROR: $SMART_CLAUDE_JSON not found"
    exit 1
fi

# Sync to all non-system users (UID >= 1000, excluding smart)
while IFS=: read -r user _ uid _ _ home _; do
    [ "$uid" -lt 1000 ] && continue
    [ "$user" = "smart" ] && continue
    [ -d "$home" ] || continue
    [ -d "$home/.claude" ] || continue

    cp "$SMART_CREDS" "$home/.claude/.credentials.json"
    cp "$SMART_CLAUDE_JSON" "$home/.claude.json"
    chown "$user:$user" "$home/.claude/.credentials.json" "$home/.claude.json"
    chmod 600 "$home/.claude/.credentials.json" "$home/.claude.json"
    echo "  synced: $user"
done < /etc/passwd

echo "Done."
