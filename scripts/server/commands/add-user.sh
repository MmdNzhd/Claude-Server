#!/bin/bash
# commands/add-user.sh - add a new developer user to the Claude Code Server
# Usage: sudo claude-server add-user <username> [--no-password-change]

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}+${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}x${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root: sudo claude-server add-user <username>"

USERNAME="${1:-}"
NO_PASSWD_CHANGE=false
shift 2>/dev/null || true
for arg in "$@"; do
    [ "$arg" = "--no-password-change" ] && NO_PASSWD_CHANGE=true
done

[ -z "$USERNAME" ] && {
    echo "Usage: sudo claude-server add-user <username> [--no-password-change]"
    exit 1
}

echo ""
echo -e "${BOLD}Adding developer: $USERNAME${NC}"

step "1 - create user"
if id "$USERNAME" &>/dev/null; then
    ok "user $USERNAME already exists"
else
    useradd -m -s /bin/bash "$USERNAME"
    ok "user $USERNAME created"
    echo "  Set password for $USERNAME:"
    passwd "$USERNAME"
fi

step "2 - home directory"
mkdir -p "/home/$USERNAME/work"
# Avoid chown -R on the entire home tree: SSHFS mounts under ~/mounts/ are
# owned by the remote user and cannot be chowned, which causes set -e to abort.
chown "$USERNAME:$USERNAME" "/home/$USERNAME"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/work"
chmod 700 "/home/$USERNAME"
ok "/home/$USERNAME/work ready (isolated)"

step "3 - claude-mount + git-setup"
mkdir -p "/home/$USERNAME/.local/bin"
if [ -f /usr/local/lib/claude-mount ]; then
    install -m 755 /usr/local/lib/claude-mount "/home/$USERNAME/.local/bin/claude-mount"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-mount"
    ok "~/.local/bin/claude-mount installed"
else
    warn "/usr/local/lib/claude-mount not found - run: sudo claude-server install"
fi

if [ -x /usr/local/bin/claude-git-setup ]; then
    install -m 755 /usr/local/bin/claude-git-setup "/home/$USERNAME/.local/bin/claude-git-setup"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-git-setup"
    ok "~/.local/bin/claude-git-setup installed"
fi
if [ -x /usr/local/bin/claude-automount ]; then
    install -m 755 /usr/local/bin/claude-automount "/home/$USERNAME/.local/bin/claude-automount"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-automount"
    ok "~/.local/bin/claude-automount installed"
fi
if [ -x /usr/local/bin/claude-self-heal ]; then
    install -m 755 /usr/local/bin/claude-self-heal "/home/$USERNAME/.local/bin/claude-self-heal"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-self-heal"
    ok "~/.local/bin/claude-self-heal installed"
fi
if [ -x /usr/local/bin/laptop-exec ]; then
    install -m 755 /usr/local/bin/laptop-exec "/home/$USERNAME/.local/bin/laptop-exec"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/laptop-exec"
    ok "~/.local/bin/laptop-exec installed"
fi
SKILL_SRC="/usr/local/lib/claude-server/skills/laptop-exec/SKILL.md"
if [ ! -f "$SKILL_SRC" ]; then
    REPO_SKILL="$(cd "$(dirname "$0")/.." && pwd)/skills/laptop-exec/SKILL.md"
    [ -f "$REPO_SKILL" ] && SKILL_SRC="$REPO_SKILL"
fi
if [ -f "$SKILL_SRC" ]; then
    mkdir -p "/home/$USERNAME/.cursor/skills/laptop-exec"
    install -m 644 "$SKILL_SRC" "/home/$USERNAME/.cursor/skills/laptop-exec/SKILL.md"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/skills/laptop-exec"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/skills" 2>/dev/null || true
    ok "~/.cursor/skills/laptop-exec installed"
fi
RULE_SRC="/usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc"
if [ ! -f "$RULE_SRC" ]; then
    REPO_RULE="$(cd "$(dirname "$0")/.." && pwd)/cursor-rules/laptop-exec.mdc"
    [ -f "$REPO_RULE" ] && RULE_SRC="$REPO_RULE"
fi
if [ -f "$RULE_SRC" ]; then
    mkdir -p "/home/$USERNAME/.cursor/rules"
    install -m 644 "$RULE_SRC" "/home/$USERNAME/.cursor/rules/laptop-exec.mdc"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/rules/laptop-exec.mdc"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/rules" 2>/dev/null || true
    ok "~/.cursor/rules/laptop-exec.mdc installed (alwaysApply)"
fi
if [ -x /usr/local/bin/laptop-exec-setup ]; then
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor" 2>/dev/null || true
    sudo -u "$USERNAME" /usr/local/bin/laptop-exec-setup --user 2>/dev/null || true
    ok "laptop-exec-setup --user"
fi

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin"

step "3b - Claude plugins (superpowers + ECC)"
PLUGIN_SRC="/home/smart/.claude/plugins/cache/claude-plugins-official"
PLUGIN_DST="/home/$USERNAME/.claude/plugins/cache/claude-plugins-official"
mkdir -p "$PLUGIN_DST"
if [ -d "$PLUGIN_SRC/superpowers" ]; then
    if [ "$PLUGIN_SRC" = "$PLUGIN_DST" ] || [ -d "$PLUGIN_DST/superpowers" ]; then
        ok "superpowers plugin present"
    else
        cp -r "$PLUGIN_SRC/superpowers" "$PLUGIN_DST/"
        ok "superpowers plugin copied"
    fi
else
    warn "superpowers not found in smart's cache - user must install manually"
fi
ECC_SRC="/home/smart/.claude/plugins/cache/ecc/latest"
if [ -d "$ECC_SRC" ]; then
    mkdir -p "/home/$USERNAME/.claude/plugins/cache/ecc"
    if [ "$USERNAME" = "smart" ] && [ -d "/home/$USERNAME/.claude/plugins/cache/ecc/latest" ]; then
        ok "ECC plugin present"
    else
        cp -r "$ECC_SRC" "/home/$USERNAME/.claude/plugins/cache/ecc/"
        ok "ECC plugin copied"
    fi
else
    warn "ECC not found - run: git clone --depth=1 https://github.com/affaan-m/ECC /home/smart/.claude/plugins/cache/ecc/latest"
fi
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.claude/plugins"

step "4 - Claude settings + hooks"
# NOTE: if hooks change, update this settings.json template too - see CLAUDE.md
mkdir -p "/home/$USERNAME/.claude"
cat > "/home/$USERNAME/.claude/settings.json" << 'SETTINGS'
{
  "theme": "dark",
  "model": "claude-sonnet-4-6",
  "effortLevel": "low",
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-logout-block.sh"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-pre.sh"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-stop.sh"}]}]
  },
  "mcpServers": {
    "codegraph": {
      "type": "stdio",
      "command": "codegraph",
      "args": ["serve", "--mcp"]
    },
    "headroom": {
      "type": "stdio",
      "command": "headroom",
      "args": ["mcp"]
    },
    "sqlserver": {
      "type": "stdio",
      "command": "/usr/bin/mcp-sqlserver",
      "args": [],
      "env": {
        "SQLSERVER_HOST": "192.168.210.124",
        "SQLSERVER_USER": "Mohammad",
        "SQLSERVER_PASSWORD": "CHANGE_ME"
      }
    }
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "ecc@ecc": true
  },
  "extraKnownMarketplaces": {
    "ecc": {
      "source": {
        "source": "github",
        "repo": "affaan-m/ECC"
      }
    }
  }
}
SETTINGS
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.claude"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.claude/settings.json"
ok "~/.claude/settings.json written"

if [ -x /usr/local/bin/claude-auth-sync ]; then
    if [ -f /etc/claude-code/oauth.env ] || grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment 2>/dev/null; then
        claude-auth-sync "$USERNAME"
        ok "OAuth token synced (settings.json env + empty credentials.json)"
    else
        warn "no server OAuth token in /etc/claude-code/oauth.env (or legacy /etc/environment) yet"
        warn "set token then run: sudo claude-server sync-auth $USERNAME"
    fi
else
    warn "claude-auth-sync not installed - run: sudo claude-server install"
fi

if [ -x /usr/local/bin/cursor-auth-sync ] && [ -f /etc/cursor-auth/golden/auth.json ]; then
    cursor-auth-sync "$USERNAME"
    ok "Cursor golden identity synced (~/.config/Cursor/)"
elif [ -f /etc/cursor-auth/golden/auth.json ]; then
    warn "cursor-auth-sync not installed - run: sudo claude-server install"
else
    warn "no Cursor golden auth yet - after first login run: sudo cursor-auth-export --from-user $USERNAME"
    warn "then: sudo claude-server sync-cursor-auth $USERNAME"
fi

step "5 - SSH"
mkdir -p "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
ok "~/.ssh ready"

step "6 - auto-mount in .bashrc"
BASHRC="/home/$USERNAME/.bashrc"
touch "$BASHRC"
if ! grep -q "claude-automount" "$BASHRC"; then
    cat >> "$BASHRC" << 'HOOK'

# --- Claude Code auto-mount ---
case $- in
  *i*)
    if [ -z "$CLAUDE_AUTOMOUNT_DONE" ] && { [ -x "$HOME/.local/bin/claude-automount" ] || [ -x /usr/local/bin/claude-automount ]; }; then
        export CLAUDE_AUTOMOUNT_DONE=1
        timeout 10 "$HOME/.local/bin/claude-automount" 2>/dev/null || timeout 10 /usr/local/bin/claude-automount 2>/dev/null
        [ "$PWD" = "$HOME" ] && [ -d "$HOME/work" ] && cd "$HOME/work"
    fi
    ;;
esac
# --- end Claude Code auto-mount ---
HOOK
    ok "auto-mount added to .bashrc"
else
    ok "auto-mount already in .bashrc"
fi
chown "$USERNAME:$USERNAME" "$BASHRC"

step "7 - first-login password change"
if $NO_PASSWD_CHANGE; then
    warn "skipped (--no-password-change)"
else
    chage -d 0 "$USERNAME"
    ok "$USERNAME must change password on first login"
fi

echo ""

# SECURITY: do not merge this user's keys into sepidz authorized_keys.
# Auto-update uses the developer's own REMOTE_USER account (connect-update.*).

echo -e "${GREEN}${BOLD}Done.${NC} User $USERNAME is ready."
echo ""
echo "  Next steps:"
echo "    ssh-copy-id -i ~/.ssh/id_ed25519.pub $USERNAME@<server-ip>"
echo "    claude-server verify"
echo ""
