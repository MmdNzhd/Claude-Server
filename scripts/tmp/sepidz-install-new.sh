#!/bin/bash
set -euo pipefail
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

echo "=== sync scripts into /opt/claude-code-server ==="
sudo_cmd rsync -a /tmp/claude-server-sync/server/ /opt/claude-code-server/scripts/server/ 2>&1 || \
  sudo_cmd cp -a /tmp/claude-server-sync/server/. /opt/claude-code-server/scripts/server/

echo "=== check cursor-auth-export ==="
ls -la /opt/claude-code-server/scripts/server/cursor-auth-export.sh

echo "=== install ==="
sudo_cmd bash /opt/claude-code-server/scripts/server/commands/install.sh 2>&1

echo "=== cursor tools ==="
ls -la /usr/local/bin/cursor-auth-* 2>&1 || true

echo "=== diagnose cursor ==="
sudo_cmd claude-server diagnose-auth 2>&1 | sed -n '/Cursor golden/,/Summary/p'
