#!/bin/bash
# deploy-fixes.sh - deploy updated server scripts to all users
# Run as root or smart (with sudo) after updating scripts in the repo
# Usage: sudo bash deploy-fixes.sh

REPO="/home/smart/mounts/claude-code-server/scripts/server"

if [ ! -d "$REPO" ]; then
    echo "ERROR: repo not found at $REPO"
    echo "Make sure claude-code-server is mounted: connect.bat -> select 'Claude Code Server'"
    exit 1
fi

echo "=== Deploying scripts to /usr/local/bin/ ==="
sudo install -m 755 "$REPO/claude-automount.sh"  /usr/local/bin/claude-automount
sudo install -m 755 "$REPO/claude-watchdog.sh"   /usr/local/bin/claude-watchdog
sudo install -m 755 "$REPO/claude-git-setup.sh"  /usr/local/bin/claude-git-setup
sudo install -m 755 "$REPO/claude-wrapper.sh"    /usr/local/bin/claude
sudo install -m 755 "$REPO/designer-start.sh"    /usr/local/bin/designer-start
echo "  OK: claude-automount, claude-watchdog, claude-git-setup, claude wrapper, designer-start updated"

echo ""
echo "=== Deploying claude-limits.conf to /etc/ ==="
sudo install -m 644 "$REPO/claude-limits.conf" /etc/claude-limits.conf
echo "  OK: /etc/claude-limits.conf updated"
sudo mkdir -p /var/run/claude-active && sudo chmod 1777 /var/run/claude-active
echo "  OK: /var/run/claude-active ready"

echo ""
echo "=== Deploying claude-mount to /usr/local/lib/ ==="
sudo install -m 644 "$REPO/claude-mount.sh" /usr/local/lib/claude-mount
echo "  OK: /usr/local/lib/claude-mount updated"

echo ""
echo "=== Deploying claude-mount and claude-git-setup to all users ==="
for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
    [ -d "/home/$u" ] || continue
    mkdir -p "/home/$u/.local/bin"
    install -m 755 /usr/local/lib/claude-mount "/home/$u/.local/bin/claude-mount"
    chown "$u:$u" "/home/$u/.local/bin/claude-mount"
    install -m 755 /usr/local/bin/claude-git-setup "/home/$u/.local/bin/claude-git-setup"
    chown "$u:$u" "/home/$u/.local/bin/claude-git-setup"
    echo "  updated: $u"
done

echo ""
echo "=== Deploying hooks to /usr/local/bin/ ==="
for hook in claude-hook-logout-block.sh claude-hook-pre.sh claude-hook-stop.sh; do
    src="$REPO/hooks/$hook"
    if [ -f "$src" ]; then
        # deploy both with and without .sh extension -- settings.json files use .sh
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
    tmp=$(mktemp) || { echo "  WARN: mktemp failed for $u, skipped"; continue; }
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
