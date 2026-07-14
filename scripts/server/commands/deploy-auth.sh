#!/bin/bash
# deploy-auth.sh - install a new claude setup-token on the server (env + profile + sync + probe)
# Usage: sudo claude-server deploy-auth <sk-ant-oat01-...>
#        echo 'sk-ant-oat01-...' | sudo claude-server deploy-auth

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

[ "$EUID" -eq 0 ] || {
    echo -e "${RED}must run as root: sudo claude-server deploy-auth <token>${NC}" >&2
    exit 1
}

LIB="/usr/local/lib/claude-server/claude-auth-lib.py"
SYNC_BIN="/usr/local/bin/claude-auth-sync"

TOKEN="${1:-}"
if [ -z "$TOKEN" ] && [ ! -t 0 ]; then
    TOKEN="$(cat)"
fi
TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

[ -n "$TOKEN" ] || {
    echo -e "${RED}usage: sudo claude-server deploy-auth <sk-ant-oat01-...>${NC}" >&2
    echo "  Generate on laptop: claude setup-token" >&2
    exit 1
}

[ -f "$LIB" ] || {
    echo -e "${RED}claude-auth-lib.py missing - run: sudo claude-server install${NC}" >&2
    exit 1
}

echo ""
echo -e "${BOLD}=== Deploy Claude OAuth token ===${NC}"
echo ""

python3 "$LIB" snapshot "pre_deploy"
python3 "$LIB" deploy "$TOKEN" "claude-server-deploy-auth"

echo -e "${GREEN}OK${NC}    /etc/environment + /etc/profile.d/claude-auth.sh updated"

if [ -x "$SYNC_BIN" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        python3 -c "
import json, sys
sys.path.insert(0, '/usr/local/lib/claude-server')
import importlib.util
spec = importlib.util.spec_from_file_location('claude_auth_lib', '$LIB')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.log_event('SYNC_USER', detail=sys.argv[1])
" "$line"
        echo "  $line"
    done < <(bash "$SYNC_BIN" --all)
else
    echo -e "${RED}claude-auth-sync missing - run: sudo claude-server install${NC}" >&2
    exit 1
fi

echo ""
echo -e "${BOLD}=== API probe (must be HTTP 2xx) ===${NC}"
if python3 "$LIB" probe "post_deploy"; then
    echo -e "${GREEN}OK${NC}    token accepted by api.anthropic.com"
else
    echo -e "${RED}FAIL${NC}  token rejected by API - check /var/log/claude-auth.log" >&2
    exit 1
fi

python3 "$LIB" snapshot "post_deploy"
echo ""
echo -e "${GREEN}Done.${NC} Ask developers to reload VS Code (Developer: Reload Window)."
echo "  Audit log: /var/log/claude-auth.log"
echo ""
