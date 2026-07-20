#!/bin/bash
# setup-bundle-deploy-sudo.sh - one-time: allow smart user to install client bundle without password
# Usage: sudo bash setup-bundle-deploy-sudo.sh
# Run on each server (Smart + Sepidz) once; then publish deploy works non-interactively.

set -euo pipefail

[ "$EUID" -ne 0 ] && { echo "run as root: sudo bash setup-bundle-deploy-sudo.sh"; exit 1; }

DEST="/etc/sudoers.d/claude-client-bundle"
cat > "$DEST" <<'EOF'
# Claude Code Server - allow smart to install laptop auto-update bundle (no secrets in script)
smart ALL=(ALL) NOPASSWD: /usr/local/lib/claude-server/install-client-bundle.sh
smart ALL=(ALL) NOPASSWD: /bin/bash /home/smart/claude-client-bundle-deploy/install-client-bundle.sh
EOF
chmod 440 "$DEST"
visudo -cf "$DEST"
echo "OK: $DEST installed (smart can sudo install-client-bundle without password)"
