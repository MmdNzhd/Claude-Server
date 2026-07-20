#!/bin/bash
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }

echo "=== cli-config.json ==="
sudo_cmd cat /root/.cursor/cli-config.json 2>&1 | head -5

echo "=== find files ==="
sudo_cmd find /root/.cursor /root/.local/share/cursor-agent -type f 2>/dev/null

echo "=== export from-user root via python home ==="
sudo_cmd cursor-auth-export --from-path /root/.cursor 2>&1 || true

echo "=== try export as root user path ==="
sudo_cmd python3 -c "
import importlib.util
spec=importlib.util.spec_from_file_location('m','/usr/local/lib/claude-server/cursor-auth-lib.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
from pathlib import Path
for p in [Path('/root'), Path('/home/sepidz')]:
    print('user paths for', p)
    try:
        m.export_from_user(p, p.name, 'cloud')
        print('export ok')
    except Exception as e:
        print('export fail:', e)
" 2>&1

echo "=== golden after ==="
sudo_cmd ls -la /etc/cursor-auth/golden/ 2>&1
