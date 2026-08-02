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

# atomic_install MODE SRC DST [OWNER] [GROUP]
# Installs SRC to DST via a same-directory temp file + rename so a process already
# executing DST (e.g. claude-watchdog polling claude-mount every 30s, relevant when
# re-running add-user against an existing user) never observes a partially-written file.
atomic_install() {
    local mode="$1" src="$2" dst="$3" owner="${4:-}" group="${5:-}" tmp="${3}.new.$$"
    if [ -n "$owner" ]; then
        install -m "$mode" -o "$owner" -g "$group" "$src" "$tmp" || return 1
    else
        install -m "$mode" "$src" "$tmp" || return 1
    fi
    mv -f "$tmp" "$dst"
}

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

# cursorauth group: group-read access to /etc/cursor-auth/golden/{auth.json,machine-id.txt,
# state-keys.json,exported-at} so cursor-auth-laptop.ps1's plain (non-root) SSH probes can
# actually read the golden Cursor auth bundle. Without this every laptop's "Syncing Cursor
# auth" step always reports golden_missing (permission-denied indistinguishable from absent),
# even when cursor-auth-export has run and the bundle is fully present and fresh.
getent group cursorauth >/dev/null 2>&1 || groupadd cursorauth
usermod -aG cursorauth "$USERNAME"
ok "user $USERNAME added to cursorauth group (Cursor golden-auth read access)"

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
    atomic_install 755 /usr/local/lib/claude-mount "/home/$USERNAME/.local/bin/claude-mount" "$USERNAME" "$USERNAME"
    ok "~/.local/bin/claude-mount installed"
else
    warn "/usr/local/lib/claude-mount not found - run: sudo claude-server install"
fi

if [ -x /usr/local/bin/claude-git-setup ]; then
    atomic_install 755 /usr/local/bin/claude-git-setup "/home/$USERNAME/.local/bin/claude-git-setup" "$USERNAME" "$USERNAME"
    ok "~/.local/bin/claude-git-setup installed"
fi
if [ -x /usr/local/bin/claude-automount ]; then
    atomic_install 755 /usr/local/bin/claude-automount "/home/$USERNAME/.local/bin/claude-automount" "$USERNAME" "$USERNAME"
    ok "~/.local/bin/claude-automount installed"
fi
if [ -x /usr/local/bin/claude-self-heal ]; then
    atomic_install 755 /usr/local/bin/claude-self-heal "/home/$USERNAME/.local/bin/claude-self-heal" "$USERNAME" "$USERNAME"
    ok "~/.local/bin/claude-self-heal installed"
fi
if [ -x /usr/local/bin/laptop-exec ]; then
    atomic_install 755 /usr/local/bin/laptop-exec "/home/$USERNAME/.local/bin/laptop-exec" "$USERNAME" "$USERNAME"
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
# Plan-flow skills (heavy-task-plan family) — golden copies under system skills/
for _plan_skill in heavy-task-plan evidence-gated-stages parallel-phased-execution writing-plans; do
    _psrc="/usr/local/lib/claude-server/skills/$_plan_skill"
    if [ -d "$_psrc" ] && [ -f "$_psrc/SKILL.md" ]; then
        mkdir -p "/home/$USERNAME/.cursor/skills"
        rm -rf "/home/$USERNAME/.cursor/skills/$_plan_skill"
        cp -a "$_psrc" "/home/$USERNAME/.cursor/skills/$_plan_skill"
        chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/skills/$_plan_skill"
        ok "~/.cursor/skills/$_plan_skill installed"
    fi
done
unset _plan_skill _psrc
# Figma write-to-canvas skills (official + Smart router)
_REPO_SKILLS="$(cd "$(dirname "$0")/.." && pwd)/skills"
for _figma_skill in figma-use figma-generate-design figma-create-new-file figma-designer; do
    _fsrc="/usr/local/lib/claude-server/skills/$_figma_skill"
    if [ ! -f "$_fsrc/SKILL.md" ] && [ -f "$_REPO_SKILLS/$_figma_skill/SKILL.md" ]; then
        _fsrc="$_REPO_SKILLS/$_figma_skill"
    fi
    if [ -d "$_fsrc" ] && [ -f "$_fsrc/SKILL.md" ]; then
        mkdir -p "/home/$USERNAME/.cursor/skills"
        rm -rf "/home/$USERNAME/.cursor/skills/$_figma_skill"
        cp -a "$_fsrc" "/home/$USERNAME/.cursor/skills/$_figma_skill"
        chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/skills/$_figma_skill"
        ok "~/.cursor/skills/$_figma_skill installed"
    fi
done
unset _figma_skill _fsrc _REPO_SKILLS
# Figma + MCP cursor rules (parity with install.sh user loop)
for _rule in figma-design backend-agent; do
    _rsrc="/usr/local/lib/claude-server/cursor-rules/${_rule}.mdc"
    if [ ! -f "$_rsrc" ]; then
        _rsrc="$(cd "$(dirname "$0")/.." && pwd)/cursor-rules/${_rule}.mdc"
    fi
    if [ -f "$_rsrc" ]; then
        mkdir -p "/home/$USERNAME/.cursor/rules"
        install -m 644 "$_rsrc" "/home/$USERNAME/.cursor/rules/${_rule}.mdc"
        chown "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/rules/${_rule}.mdc"
        ok "~/.cursor/rules/${_rule}.mdc installed"
    fi
done
unset _rule _rsrc
if [ -f "/usr/local/lib/claude-server/skills/context7/SKILL.md" ] || [ -f "$(cd "$(dirname "$0")/.." && pwd)/skills/context7/SKILL.md" ]; then
    _c7="/usr/local/lib/claude-server/skills/context7/SKILL.md"
    [ -f "$_c7" ] || _c7="$(cd "$(dirname "$0")/.." && pwd)/skills/context7/SKILL.md"
    mkdir -p "/home/$USERNAME/.cursor/skills/context7"
    install -m 644 "$_c7" "/home/$USERNAME/.cursor/skills/context7/SKILL.md"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/skills/context7"
    ok "~/.cursor/skills/context7 installed"
    unset _c7
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
PLAN_GATE_SRC="/usr/local/lib/claude-server/cursor-rules/plan-gate.mdc"
if [ -f "$PLAN_GATE_SRC" ]; then
    mkdir -p "/home/$USERNAME/.cursor/rules"
    install -m 644 "$PLAN_GATE_SRC" "/home/$USERNAME/.cursor/rules/plan-gate.mdc"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.cursor/rules/plan-gate.mdc"
    ok "~/.cursor/rules/plan-gate.mdc installed (alwaysApply)"
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
    "headroom": {
      "type": "stdio",
      "command": "headroom",
      "args": ["mcp"]
    },
    "sqlserver": {
      "type": "stdio",
      "command": "/usr/bin/mcp-sqlserver",
      "args": []
    },
    "figma": {
      "type": "http",
      "url": "https://mcp.figma.com/mcp"
    },
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    }
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "ecc@ecc": true,
    "figma@claude-plugins-official": true
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

step "4b - codebase-memory-mcp"
runuser -l "$USERNAME" -c "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash" > "/tmp/cbm-install-$USERNAME.log" 2>&1 \
    && ok "codebase-memory-mcp installed for $USERNAME" \
    || warn "codebase-memory-mcp install failed for $USERNAME - see /tmp/cbm-install-$USERNAME.log, or run manually: runuser -l $USERNAME -c \"curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash\""

# Guard: never leave a CRLF-corrupted ELF (fleet BAD size 270249937 = good after CR strip).
_cbm_bin="/home/$USERNAME/.local/bin/codebase-memory-mcp"
_cbm_good_ref="/home/smart/.local/bin/codebase-memory-mcp"
_cbm_good_size=270253064
if [ -f "$_cbm_bin" ]; then
    _cbm_sz=$(stat -c%s "$_cbm_bin" 2>/dev/null || echo 0)
    _cbm_magic=$(head -c4 "$_cbm_bin" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    _cbm_help_ec=0
    runuser -l "$USERNAME" -c "timeout 5 $_cbm_bin --help >/dev/null 2>&1" || _cbm_help_ec=$?
    if [ "$_cbm_sz" != "$_cbm_good_size" ] || [ "$_cbm_magic" != "7f454c46" ] || [ "$_cbm_help_ec" = "132" ]; then
        if [ -f "$_cbm_good_ref" ] && [ "$(stat -c%s "$_cbm_good_ref" 2>/dev/null)" = "$_cbm_good_size" ]; then
            install -m 755 -o "$USERNAME" -g "$USERNAME" "$_cbm_good_ref" "$_cbm_bin"
            warn "codebase-memory-mcp for $USERNAME looked corrupt (size=$_cbm_sz magic=$_cbm_magic help_ec=$_cbm_help_ec) - copied good binary from smart"
        else
            warn "codebase-memory-mcp for $USERNAME looks corrupt (size=$_cbm_sz magic=$_cbm_magic help_ec=$_cbm_help_ec) - no good reference at $_cbm_good_ref"
        fi
    else
        ok "codebase-memory-mcp ELF/size/--help gate passed for $USERNAME"
    fi
fi

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

if [ -x /usr/local/bin/cursor-mcp-sync ]; then
    cursor-mcp-sync --user "$USERNAME" || warn "cursor-mcp-sync failed for $USERNAME (non-fatal)"
else
    warn "cursor-mcp-sync not installed - run: sudo claude-server install"
fi

if [ -x /usr/local/bin/cursor-remote-proxy-sync ]; then
    cursor-remote-proxy-sync --user "$USERNAME" || warn "cursor-remote-proxy-sync failed for $USERNAME (non-fatal)"
else
    warn "cursor-remote-proxy-sync not installed - run: sudo claude-server install"
fi

if [ -f /usr/local/lib/claude-server/commands/fix-cursor-ecc-hooks.sh ]; then
    bash /usr/local/lib/claude-server/commands/fix-cursor-ecc-hooks.sh "$USERNAME" \
        || warn "fix-cursor-ecc-hooks failed for $USERNAME (non-fatal)"
elif [ -f "$(dirname "$0")/fix-cursor-ecc-hooks.sh" ]; then
    bash "$(dirname "$0")/fix-cursor-ecc-hooks.sh" "$USERNAME" \
        || warn "fix-cursor-ecc-hooks failed for $USERNAME (non-fatal)"
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
