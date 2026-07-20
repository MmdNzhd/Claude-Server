#!/bin/bash
PASS='sepidz@Admin'
sudo_cmd() { printf '%s\n' "$PASS" | sudo -S "$@"; }
echo "=== find state.vscdb ==="
sudo_cmd find /root /home/sepidz /home/smart -name state.vscdb 2>/dev/null | head -10
echo "=== find agent credentials ==="
sudo_cmd find /root /home/sepidz -path '*cursor*' -name '*.json' 2>/dev/null | rg -i 'auth|credential|token' | head -15 || true
sudo_cmd ls -la /root/.cursor/ 2>&1 || true
sudo_cmd ls -la /root/.local/share/cursor-agent/ 2>&1 || true
