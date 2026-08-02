#!/bin/bash
# fix-all-now.sh - one-shot server repair (mount + auth sync + user repair)
# Usage: sudo claude-server fix-all-now [oauth-token]
#        sudo bash scripts/server/commands/fix-all-now.sh [oauth-token]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    fail "run as root: sudo claude-server fix-all-now"
fi

_resolve_commands_dir() {
    local self_dir
    self_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
    local d
    for d in \
        "$self_dir" \
        "${CLAUDE_SERVER_REPO:-}/scripts/server/commands" \
        "/home/smart/mounts/claude-code-server/scripts/server/commands" \
        "/usr/local/lib/claude-server"; do
        [ -n "$d" ] || continue
        [ -f "$d/deploy-mount-fix.sh" ] || continue
        printf '%s' "$d"
        return 0
    done
    return 1
}

COMMANDS_DIR="$(_resolve_commands_dir)" || fail "commands dir not found (clone repo to ~/mounts/claude-code-server)"
TOKEN="${1:-}"

echo ""
echo -e "${BOLD}=== Claude Server fix-all-now ===${NC}"
echo -e "  ${BOLD}repo${NC}    $COMMANDS_DIR"
echo ""

echo -e "${BOLD}1. Mount scripts${NC}"
bash "$COMMANDS_DIR/deploy-mount-fix.sh"
echo ""

echo -e "${BOLD}1b. Client bundle (laptop auto-update)${NC}"
bash "$COMMANDS_DIR/deploy-client-bundle.sh"
echo ""

echo -e "${BOLD}2. Claude OAuth${NC}"
if [ -n "$TOKEN" ]; then
    bash "$COMMANDS_DIR/deploy-auth.sh" "$TOKEN"
else
    LIB="/usr/local/lib/claude-server/claude-auth-lib.py"
    if [ -f "$LIB" ] && python3 "$LIB" probe "fix-all-now" 2>/dev/null; then
        ok "server OAuth token valid"
        bash "$COMMANDS_DIR/sync-auth.sh"
    else
        warn "OAuth token INVALID - run: claude setup-token && sudo claude-server deploy-auth <token>"
        bash "$COMMANDS_DIR/sync-auth.sh" || true
    fi
fi
echo ""

echo -e "${BOLD}3. Cursor golden auth${NC}"
if [ -f /etc/cursor-auth/golden/auth.json ]; then
    bash "$COMMANDS_DIR/sync-cursor-auth.sh"
else
    warn "no golden Cursor auth - skip"
fi
echo ""

echo -e "${BOLD}4. Repair user accounts${NC}"
for u in smart amir amirhossein aria danial fateme hamed hamed.kh kiana mahdie mehrdad mohammad parsa reza tarane; do
    id "$u" >/dev/null 2>&1 || continue
    bash "$COMMANDS_DIR/add-user.sh" "$u" --no-password-change >/dev/null 2>&1 && ok "$u" || warn "$u partial"
done
echo ""

echo -e "${BOLD}5. Laptop-exec SSH-first${NC}"
if [ -f "$COMMANDS_DIR/deploy-laptop-exec.sh" ]; then
    bash "$COMMANDS_DIR/deploy-laptop-exec.sh"
else
    warn "deploy-laptop-exec.sh missing"
fi
if [ -f "$COMMANDS_DIR/deploy-client-bundle.sh" ]; then
    bash "$COMMANDS_DIR/deploy-client-bundle.sh"
else
    warn "deploy-client-bundle.sh missing"
fi
echo ""

echo -e "${BOLD}5b. Cursor ECC Claude-hooks neutralize${NC}"
if [ -f "$COMMANDS_DIR/fix-cursor-ecc-hooks.sh" ]; then
    bash "$COMMANDS_DIR/fix-cursor-ecc-hooks.sh"
else
    warn "fix-cursor-ecc-hooks.sh missing"
fi
echo ""

echo -e "${BOLD}6. aria / mehrdad${NC}"
for u in aria mehrdad; do
    id "$u" >/dev/null 2>&1 || continue
    nproj="$(ls "/home/$u/.claude-mounts.d/"*.conf 2>/dev/null | wc -l | tr -d ' ')"
    nmnt="$(mount 2>/dev/null | grep -c "/home/$u/mounts" || true)"
    echo "  $u: projects=$nproj sshfs=$nmnt"
    if [ -f "/home/$u/.claude-connect.conf" ]; then
        grep -E '^(TUNNEL_PORT|ACTIVE_MOUNT|LAPTOP_USER)=' "/home/$u/.claude-connect.conf" | sed 's/^/    /'
    else
        echo "    (no connect.conf - run connect.bat on laptop)"
    fi
done
echo ""
echo -e "${GREEN}Done.${NC}"
echo "  OAuth still broken?  claude setup-token  then  sudo claude-server deploy-auth <token>"
echo "  aria/mehrdad: run connect.bat on laptop (not only Cursor Remote SSH)"
echo ""

