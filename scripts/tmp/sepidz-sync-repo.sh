#!/bin/bash
set -euo pipefail
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

sudo_cmd git config --global --add safe.directory /opt/claude-code-server
cd /opt/claude-code-server
git remote -v
git fetch --all 2>&1 || true
git pull 2>&1 || true
git log -1 --oneline 2>&1 || true
ls scripts/server/cursor-auth-export.sh 2>&1 || echo "MISSING cursor-auth-export"
