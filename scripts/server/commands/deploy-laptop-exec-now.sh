#!/bin/bash
# One-shot: deploy optimized laptop-exec to all users (requires sudo password once)
set -euo pipefail
echo "=== laptop-exec full deploy ==="
sudo cp /home/smart/.local/bin/laptop-exec /usr/local/lib/claude-server/laptop-exec.sh
sudo cp /home/smart/.cursor/rules/laptop-exec.mdc /usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc
sudo cp /home/smart/.cursor/skills/laptop-exec/SKILL.md /usr/local/lib/claude-server/skills/laptop-exec/SKILL.md
sudo cp /tmp/deploy-laptop-exec.sh /usr/local/lib/claude-server/commands/deploy-laptop-exec.sh 2>/dev/null || \
  sudo laptop-exec read -p claude-code-server scripts/server/commands/deploy-laptop-exec.sh | sudo tee /usr/local/lib/claude-server/commands/deploy-laptop-exec.sh >/dev/null
sudo chmod 755 /usr/local/lib/claude-server/commands/deploy-laptop-exec.sh
sudo claude-server deploy-laptop-exec
sudo claude-server verify 2>&1 | grep -A20 "Laptop Exec"
echo "=== done ==="
