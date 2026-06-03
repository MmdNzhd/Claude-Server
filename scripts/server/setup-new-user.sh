#!/bin/bash
# Run as ROOT on server to add a new developer
# Usage: sudo bash setup-new-user.sh <username>

set -e

USERNAME="${1:-}"

if [ -z "$USERNAME" ]; then
    echo "Usage: sudo bash setup-new-user.sh <username>"
    exit 1
fi

if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists."
else
    echo "=== Creating user: $USERNAME ==="
    useradd -m -s /bin/bash "$USERNAME"
    echo "  OK: user created"
    echo ""
    echo "Set password for $USERNAME:"
    passwd "$USERNAME"
fi

echo ""
echo "=== Setting up home directory ==="
mkdir -p "/home/$USERNAME/work"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
chmod 700 "/home/$USERNAME"
echo "  OK: /home/$USERNAME/work created (isolated)"

echo ""
echo "=== Installing claude-mount ==="
mkdir -p "/home/$USERNAME/.local/bin"
if [ -f /usr/local/lib/claude-mount ]; then
    install -m 755 /usr/local/lib/claude-mount "/home/$USERNAME/.local/bin/claude-mount"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-mount"
    echo "  OK: ~/.local/bin/claude-mount installed"
else
    echo "  WARNING: /usr/local/lib/claude-mount not found - run server-setup.sh first"
fi

echo ""
echo "=== Setting up Claude ==="
# Auth is via CLAUDE_CODE_OAUTH_TOKEN in /etc/profile.d/claude-auth.sh - no credentials file needed.
mkdir -p "/home/$USERNAME/.claude"
cat > "/home/$USERNAME/.claude/settings.json" << 'SETTINGS'
{
  "theme": "dark",
  "model": "claude-sonnet-4-6",
  "effortLevel": "low",
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-logout-block.sh"}]}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-pre.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-stop.sh"}]}]
  }
}
SETTINGS
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.claude"
echo "  OK: Claude settings configured"

echo ""
echo "=== Setting up SSH + auto-mount ==="
mkdir -p "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
echo "  OK: ~/.ssh ready"

BASHRC="/home/$USERNAME/.bashrc"
touch "$BASHRC"
if ! grep -q "claude-automount" "$BASHRC"; then
cat >> "$BASHRC" << 'HOOK'

# --- Claude Code auto-mount (added by setup-new-user.sh) ---
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
    echo "  OK: auto-mount hook added to .bashrc"
else
    echo "  OK: auto-mount hook already present"
fi
chown "$USERNAME:$USERNAME" "$BASHRC"

echo ""
echo "=== Forcing password change on first login ==="
chage -d 0 "$USERNAME"
echo "  OK: $USERNAME must change password on first login"

echo ""
echo "Done. User $USERNAME is ready."
echo "Give them the connect launcher: windows/connect.bat or bash mac/connect.sh"
