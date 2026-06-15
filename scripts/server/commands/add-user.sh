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
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
chmod 700 "/home/$USERNAME"
ok "/home/$USERNAME/work ready (isolated)"

step "3 - claude-mount + git-setup"
mkdir -p "/home/$USERNAME/.local/bin"
if [ -f /usr/local/lib/claude-mount ]; then
    install -m 755 /usr/local/lib/claude-mount "/home/$USERNAME/.local/bin/claude-mount"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-mount"
    ok "~/.local/bin/claude-mount installed"
else
    warn "/usr/local/lib/claude-mount not found — run: sudo claude-server install"
fi

if [ -x /usr/local/bin/claude-git-setup ]; then
    install -m 755 /usr/local/bin/claude-git-setup "/home/$USERNAME/.local/bin/claude-git-setup"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-git-setup"
    ok "~/.local/bin/claude-git-setup installed"
fi

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.local"

step "4 - Claude settings + hooks"
# NOTE: if hooks change, update this settings.json template too — see CLAUDE.md
mkdir -p "/home/$USERNAME/.claude"
cat > "/home/$USERNAME/.claude/settings.json" << 'SETTINGS'
{
  "theme": "dark",
  "model": "claude-sonnet-4-6",
  "effortLevel": "low",
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-logout-block"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-pre"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-stop"}]}]
  }
}
SETTINGS
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.claude"
ok "~/.claude/settings.json written"

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
    if [ -z "$CLAUDE_AUTOMOUNT_DONE" ] && [ -x /usr/local/bin/claude-automount ]; then
        export CLAUDE_AUTOMOUNT_DONE=1
        /usr/local/bin/claude-automount 2>/dev/null
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
echo -e "${GREEN}${BOLD}Done.${NC} User $USERNAME is ready."
echo ""
echo "  Next steps:"
echo "    ssh-copy-id -i ~/.ssh/id_ed25519.pub $USERNAME@<server-ip>"
echo "    claude-server verify"
echo ""
