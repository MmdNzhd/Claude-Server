#!/bin/bash
set -euo pipefail
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

echo "=== verify ==="
sudo_cmd claude-server verify 2>&1 || true

echo "=== diagnose-auth ==="
sudo_cmd claude-server diagnose-auth 2>&1 || true

echo "=== golden ==="
sudo_cmd ls -la /etc/cursor-auth/golden/ 2>&1 || true

echo "=== client bundle ==="
ls -la /usr/local/share/claude-client/ 2>&1 || true

echo "=== laptop-exec GIT_MODE ==="
grep GIT_MODE /usr/local/bin/laptop-exec 2>/dev/null | head -1 || echo "no laptop-exec"
