#!/bin/bash
# update-server.sh — pull latest repo + redeploy Claude Code Server
# Usage: sudo bash update-server.sh
#        sudo bash update-server.sh --token   (also prompt for new OAuth token)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

REPO_URL="${CLAUDE_SERVER_REPO_URL:-https://github.com/MmdNzhd/Claude-Server.git}"
REPO_DIR="${CLAUDE_SERVER_REPO:-/opt/claude-code-server}"
REFRESH_TOKEN=false

for arg in "$@"; do
    [ "$arg" = "--token" ] && REFRESH_TOKEN=true
done

ok()   { echo -e "  ${GREEN}+${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}x${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root: sudo bash update-server.sh"

echo ""
echo -e "${BOLD}Claude Code Server — Update + Redeploy${NC}"
echo "repo: $REPO_DIR"
echo ""

# ─── 1. Clone or pull repo ─────────────────────────────────────────────────
step "1 - git repo"

if [ -d "$REPO_DIR/.git" ]; then
    ok "repo exists at $REPO_DIR"
    git -C "$REPO_DIR" fetch --all --prune
    before="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    git -C "$REPO_DIR" pull --ff-only
    after="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    if [ "$before" = "$after" ]; then
        ok "already up to date ($after)"
    else
        ok "updated $before -> $after"
    fi
elif [ -d "$REPO_DIR" ]; then
    warn "$REPO_DIR exists but is not a git repo — backing up and cloning fresh"
    mv "$REPO_DIR" "${REPO_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    git clone --depth=1 "$REPO_URL" "$REPO_DIR"
    ok "cloned to $REPO_DIR"
else
    ok "cloning $REPO_URL -> $REPO_DIR"
    git clone --depth=1 "$REPO_URL" "$REPO_DIR"
    ok "clone complete"
fi

# Fallback: mounted copy from smart laptop (read-only SSHFS — cannot pull)
MOUNTED="/home/smart/mounts/claude-code-server"
if [ ! -f "$REPO_DIR/scripts/server/commands/install.sh" ] && [ -f "$MOUNTED/scripts/server/commands/install.sh" ]; then
    warn "git repo missing install.sh — using mounted copy at $MOUNTED"
    REPO_DIR="$MOUNTED"
fi

[ -f "$REPO_DIR/scripts/server/commands/install.sh" ] || \
    fail "install.sh not found under $REPO_DIR — check network or clone URL"

# ─── 2. Full redeploy (idempotent) ───────────────────────────────────────────
step "2 - claude-server install"

export CLAUDE_SERVER_REPO="$REPO_DIR"
bash "$REPO_DIR/scripts/server/commands/install.sh"

# ─── 3. OAuth token (optional) ───────────────────────────────────────────────
step "3 - OAuth token"

if $REFRESH_TOKEN; then
    echo ""
    echo "  On a laptop with a browser run:  claude setup-token"
    echo "  Then paste the token below (input hidden):"
    echo ""
    read -r -s -p "  CLAUDE_CODE_OAUTH_TOKEN: " NEW_TOKEN
    echo ""
    [ -n "$NEW_TOKEN" ] || fail "empty token — aborted"
    echo "export CLAUDE_CODE_OAUTH_TOKEN=$NEW_TOKEN" > /etc/profile.d/claude-auth.sh
    chmod 644 /etc/profile.d/claude-auth.sh
    grep -v '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment > /tmp/claude-env.$$
    mv /tmp/claude-env.$$ /etc/environment
    echo "CLAUDE_CODE_OAUTH_TOKEN=$NEW_TOKEN" >> /etc/environment
    ok "token updated in profile.d + /etc/environment"
    if [ -x /usr/local/bin/claude-auth-sync ]; then
        claude-auth-sync --all
        ok "OAuth token synced to all users"
    else
        warn "run after install: sudo claude-server sync-auth"
    fi
else
    if [ -f /etc/profile.d/claude-auth.sh ]; then
        # shellcheck disable=SC1091
        source /etc/profile.d/claude-auth.sh
        if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
            ok "existing token kept (use --token to replace)"
            warn "if claude still asks to log in, token is expired — re-run: sudo bash update-server.sh --token"
        else
            warn "no token in claude-auth.sh — run: sudo bash update-server.sh --token"
        fi
    else
        warn "no /etc/profile.d/claude-auth.sh — run: sudo bash update-server.sh --token"
    fi
fi

# ─── 4. Fix users stuck on forced password change ────────────────────────────
step "4 - SSH password flags"

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
    [ -d "/home/$u" ] || continue
    if chage -l "$u" 2>/dev/null | grep -q 'password must be changed'; then
        warn "$u must change password — run as that user: passwd"
    fi
done

# ─── 5. Verify + auth probe ─────────────────────────────────────────────────
step "5 - verify"

if [ -x /usr/local/bin/claude-server ]; then
    claude-server verify || warn "verify reported failures (see above)"
else
    bash "$REPO_DIR/scripts/server/commands/verify.sh" || true
fi

if [ -f "$REPO_DIR/scripts/server/commands/diagnose-auth.sh" ]; then
    echo ""
    bash "$REPO_DIR/scripts/server/commands/diagnose-auth.sh" || true
elif [ -f /usr/local/lib/claude-server/diagnose-auth.sh ]; then
    echo ""
    bash /usr/local/lib/claude-server/diagnose-auth.sh || true
fi

echo ""
echo -e "${GREEN}${BOLD}Update complete.${NC}"
echo ""
echo "  Developers: disconnect + reconnect Cursor/VS Code after token change."
echo ""
