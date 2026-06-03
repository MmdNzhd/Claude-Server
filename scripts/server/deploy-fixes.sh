#!/bin/bash
# deploy-fixes.sh - deploy updated server scripts to all users
# Run as root or smart (with sudo) after updating scripts in the repo
# Usage: sudo bash deploy-fixes.sh

REPO="/home/smart/mounts/claude-code-server/scripts/server"

echo "=== Deploying claude-automount to /usr/local/bin/ ==="
sudo install -m 755 "$REPO/claude-automount.sh" /usr/local/bin/claude-automount
echo "  OK: /usr/local/bin/claude-automount updated"

echo ""
echo "=== Deploying claude-mount to /usr/local/lib/ ==="
sudo install -m 644 "$REPO/claude-mount.sh" /usr/local/lib/claude-mount
echo "  OK: /usr/local/lib/claude-mount updated"

echo ""
echo "=== Deploying claude-mount to all users ==="
for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
    [ -d "/home/$u" ] || continue
    mkdir -p "/home/$u/.local/bin"
    install -m 755 /usr/local/lib/claude-mount "/home/$u/.local/bin/claude-mount"
    chown "$u:$u" "/home/$u/.local/bin/claude-mount"
    echo "  updated: $u"
done

echo ""
echo "=== Deploying hooks to /usr/local/bin/ ==="
for hook in claude-hook-logout-block.sh claude-hook-pre.sh claude-hook-stop.sh; do
    src="$REPO/hooks/$hook"
    if [ -f "$src" ]; then
        # deploy both with and without .sh extension — settings.json files use .sh
        sudo install -m 755 "$src" "/usr/local/bin/${hook%.sh}"
        sudo install -m 755 "$src" "/usr/local/bin/$hook"
        echo "  OK: /usr/local/bin/${hook%.sh} and /usr/local/bin/$hook"
    fi
done

echo ""
echo "=== Clearing stale active session files ==="
sudo find /var/run/claude-active -name "*.active" -delete
echo "  OK: stale files cleared"

echo ""
echo "=== Ensuring effortLevel=low for all users ==="
for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
    f="/home/$u/.claude/settings.json"
    [ -f "$f" ] || continue
    tmp=$(mktemp)
    if jq '. + {"effortLevel": "low"}' "$f" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$f"
        chown "$u:$u" "$f"
        echo "  updated: $u"
    else
        rm -f "$tmp"
        echo "  WARN: invalid JSON in $u settings, skipped"
    fi
done

echo ""
echo "Done."
