#!/bin/bash
# deploy-all-now.sh - client bundle + laptop-exec + claude-mount (GIT_MODE=off)
# Usage: sudo bash deploy-all-now.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

fail() { echo -e "${RED}FAIL${NC}  $1" >&2; exit 1; }

[ "$EUID" -eq 0 ] || fail "run as root: sudo bash $0"

SELF="$(readlink -f "$0")"
COMMANDS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SERVER_DIR="${SERVER_DIR:-/usr/local/lib/claude-server}"
STAGE_USER="${LAPTOP_EXEC_STAGE_USER:-smart}"
REPO="/home/$STAGE_USER/mounts/claude-code-server"

mkdir -p "$SERVER_DIR"
for f in deploy-client-bundle.sh deploy-laptop-exec.sh; do
    if [ -f "$COMMANDS_DIR/$f" ]; then
        install -m 755 "$COMMANDS_DIR/$f" "$SERVER_DIR/$f"
    elif [ -f "$REPO/scripts/server/commands/$f" ]; then
        install -m 755 "$REPO/scripts/server/commands/$f" "$SERVER_DIR/$f"
    fi
done

[ -f "$SERVER_DIR/deploy-client-bundle.sh" ] || fail "missing deploy-client-bundle.sh"
[ -f "$SERVER_DIR/deploy-laptop-exec.sh" ] || fail "missing deploy-laptop-exec.sh"

echo ""
echo -e "${BOLD}=== Full deploy: client bundle + GIT_MODE scripts ===${NC}"
echo -e "    user=$(id -un)"
echo ""

echo -e "${BOLD}--- client bundle (connect auto-update) ---${NC}"
bash "$SERVER_DIR/deploy-client-bundle.sh"

echo ""
echo -e "${BOLD}--- laptop-exec + claude-mount (all users) ---${NC}"
bash "$SERVER_DIR/deploy-laptop-exec.sh"

echo ""
echo -e "${BOLD}--- verify ---${NC}"
grep -q 'GIT_MODE="off"' /usr/local/bin/laptop-exec \
    || fail "/usr/local/bin/laptop-exec missing GIT_MODE=off"
grep -q 'GIT_MODE="off"' "$SERVER_DIR/claude-mount.sh" 2>/dev/null \
    || grep -q 'GIT_MODE="off"' /usr/local/lib/claude-mount \
    || fail "claude-mount missing GIT_MODE=off"
grep -q "Get-GitMode) -ne 'off'" /usr/local/share/claude-client/git-mode.ps1 \
    || fail "client bundle git-mode.ps1 missing OFF mount logic"

VER="$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)"
echo -e "${GREEN}=== Done. Bundle v${VER}. Team: reconnect connect.bat ===${NC}"
echo ""
