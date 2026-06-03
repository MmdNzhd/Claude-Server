#!/bin/bash
# Run this as ROOT on the server to fix broken home directory permissions
# Usage: sudo bash fix-permissions.sh

set -e

echo "=== Fixing home directory permissions ==="

fix_user() {
    local username="$1"
    if id "$username" &>/dev/null; then
        echo "Fixing /home/$username..."
        chown -R "$username:$username" "/home/$username"
        chmod 755 "/home/$username"
        echo "  OK: /home/$username"
    else
        echo "  SKIP: user $username does not exist"
    fi
}

fix_user smart
fix_user hamed

echo ""
echo "=== Cleaning root pollution ==="
rm -rf /root/.claude
rm -rf /root/.claude.json
rm -rf /root/.cache/claude-cli-nodejs
echo "  OK: root pollution removed"

echo ""
echo "=== Test SSH access ==="
echo "Run these manually to verify:"
echo "  su - hamed"
echo "  su - smart"
echo ""
echo "Done. Both users should now be able to SSH in."
