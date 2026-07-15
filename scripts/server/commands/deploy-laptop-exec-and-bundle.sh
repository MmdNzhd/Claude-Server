#!/bin/bash
# deploy-laptop-exec-and-bundle.sh - one sudo: server golden + all users + client auto-update bundle
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "run: sudo bash $0"; exit 1; }
REPO="${CLAUDE_SERVER_REPO:-/home/smart/mounts/claude-code-server/scripts/server}"
STAGE="/home/smart/.local/bin/laptop-exec"
[ -f "$STAGE" ] && install -m 755 "$STAGE" /usr/local/lib/claude-server/laptop-exec.sh
[ -f /home/smart/.cursor/rules/laptop-exec.mdc ] && install -m 644 /home/smart/.cursor/rules/laptop-exec.mdc /usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc
[ -f /home/smart/.cursor/skills/laptop-exec/SKILL.md ] && install -m 644 /home/smart/.cursor/skills/laptop-exec/SKILL.md /usr/local/lib/claude-server/skills/laptop-exec/SKILL.md
if [ -f "$REPO/commands/deploy-laptop-exec.sh" ]; then
  install -m 755 "$REPO/commands/deploy-laptop-exec.sh" /usr/local/lib/claude-server/commands/deploy-laptop-exec.sh
fi
claude-server deploy-laptop-exec
if [ -f "$REPO/commands/deploy-client-bundle.sh" ]; then
  bash "$REPO/commands/deploy-client-bundle.sh"
else
  claude-server deploy-client-bundle
fi
echo "Done. Laptops: reconnect connect.bat -> auto-update v20260715.8 + laptop-exec push"
