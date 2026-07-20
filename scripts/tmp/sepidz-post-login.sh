#!/bin/bash
set -euo pipefail
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

echo "=== root agent auth ==="
sudo_cmd ls -la /root/.config/Cursor/User/globalStorage/ 2>&1 | head -5 || true
sudo_cmd test -f /root/.config/Cursor/User/globalStorage/state.vscdb && echo "root state.vscdb: yes" || echo "root state.vscdb: no"

echo "=== golden ==="
sudo_cmd ls -la /etc/cursor-auth/golden/ 2>&1 || true

echo "=== try export from root ==="
sudo_cmd cursor-auth-export --from-path /root/.config/Cursor/User/globalStorage 2>&1 || \
sudo_cmd cursor-auth-export --from-user sepidz 2>&1 || true

echo "=== sync ==="
sudo_cmd claude-server sync-cursor-auth 2>&1 || true

echo "=== diagnose cursor ==="
sudo_cmd claude-server diagnose-auth 2>&1 | sed -n '/Cursor golden/,/Summary/p' || true
