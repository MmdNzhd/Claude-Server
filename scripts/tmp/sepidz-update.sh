#!/bin/bash
set -euo pipefail
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

echo "=== git status ==="
cd /opt/claude-code-server
git status -sb 2>&1 || true
git remote -v 2>&1 || true
git log -1 --oneline 2>&1 || true

echo "=== git pull ==="
git pull 2>&1 || true

echo "=== install ==="
sudo_cmd bash scripts/server/commands/install.sh 2>&1

echo "=== post-install diagnose (cursor section) ==="
sudo_cmd claude-server diagnose-auth 2>&1 | sed -n '/Cursor golden/,/Summary/p' || true
