#!/bin/bash
# Run as ROOT on server to add a new developer
# Usage: sudo bash setup-new-user.sh <username>
# Example: sudo bash setup-new-user.sh ali

set -e

USERNAME="${1:-}"

if [ -z "$USERNAME" ]; then
    echo "Usage: sudo bash setup-new-user.sh <username>"
    echo "Example: sudo bash setup-new-user.sh ali"
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
echo "=== Setting up Claude credentials ==="
SMART_CREDS="/home/smart/.claude/.credentials.json"
SMART_CLAUDE_JSON="/home/smart/.claude.json"

if [ ! -f "$SMART_CREDS" ]; then
    echo "  WARNING: /home/smart/.claude/.credentials.json not found!"
    echo "  Login with smart first: su - smart && claude"
    exit 1
fi

if [ ! -f "$SMART_CLAUDE_JSON" ]; then
    echo "  WARNING: /home/smart/.claude.json not found!"
    echo "  Run claude once as smart first."
    exit 1
fi

mkdir -p "/home/$USERNAME/.claude"

# copy credentials from smart (not a symlink, not /etc/claude-shared)
cp "$SMART_CREDS" "/home/$USERNAME/.claude/.credentials.json"

# copy .claude.json from smart (has oauthAccount — without it the login screen appears)
cp "$SMART_CLAUDE_JSON" "/home/$USERNAME/.claude.json"

# settings.json with hooks
cat > "/home/$USERNAME/.claude/settings.json" << 'SETTINGS'
{
  "theme": "dark",
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-logout-block.sh"}]}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-pre.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-stop.sh"}]}]
  }
}
SETTINGS

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.claude"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.claude.json"
chmod 600 "/home/$USERNAME/.claude/.credentials.json"
chmod 600 "/home/$USERNAME/.claude.json"
echo "  OK: credentials and oauthAccount copied"

echo ""
echo "=== Setting up SSH + auto-mount ==="
# ~/.ssh holds: laptop->server key (authorized_keys) and server->laptop key (claude_laptop)
mkdir -p "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
echo "  OK: ~/.ssh ready"

# Auto-mount hook in .bashrc — VSCode Remote-SSH sources .bashrc (NOT .bash_profile),
# so opening the integrated terminal triggers the mount. Interactive shells only.
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
echo "=== Next steps for $USERNAME ==="
echo "1. Give them their password (they change it on first login)."
echo "2. Give them the connect launcher for their OS:"
echo "     Windows : scripts/client/windows/connect.bat  ->  double-click"
echo "     Mac/Lin : scripts/client/mac/connect.sh       ->  bash connect.sh"
echo "3. First run asks: server username ($USERNAME) + project path. That's it."
echo "   The launcher sets up keys, opens the tunnel, mounts the project,"
echo "   and opens VSCode automatically. Inside VSCode they just run: claude"
echo ""
echo "Note: keys & ~/.claude-mount.conf are created by the launcher on first connect."
echo ""
echo "Done. User $USERNAME is ready."
