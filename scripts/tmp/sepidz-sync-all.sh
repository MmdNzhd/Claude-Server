#!/bin/bash
set -euo pipefail
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

echo "=== export official ==="
sudo_cmd cursor-auth-export --from-user root 2>&1 || \
sudo_cmd bash -lc 'python3 - <<PY
import importlib.util
from pathlib import Path
lib="/usr/local/lib/claude-server/cursor-auth-lib.py"
spec=importlib.util.spec_from_file_location("m",lib)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.export_from_user(Path("/root"), "root", "cloud")
PY'

echo "=== sync all ==="
sudo_cmd claude-server sync-cursor-auth 2>&1

echo "=== refresh ==="
sudo_cmd cursor-auth-refresh 2>&1 || true

echo "=== diagnose ==="
sudo_cmd claude-server diagnose-auth 2>&1 | sed -n '/Cursor golden/,/Summary/p'

echo "=== golden files ==="
sudo_cmd ls -la /etc/cursor-auth/golden/
