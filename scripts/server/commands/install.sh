#!/bin/bash
# commands/install.sh - full Claude Code Server install from scratch
# Usage: sudo claude-server install
# Idempotent - safe to run again after updates to hooks or scripts.

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# Resolve the real repo root, in priority order:
#   1. $CLAUDE_SERVER_REPO (explicit override, e.g. from update-server.sh)
#   2. repo mode: this script is at <repo>/scripts/server/commands/install.sh,
#      so 3 levels up is <repo> - only valid when actually run from a checkout
#   3. canonical server-side clone used by update-server.sh (/opt/claude-code-server)
# Do NOT trust step 2's relative math once this script is deployed flat/nested
# under /usr/local/lib/claude-server/ (via `sudo claude-server install` step 13's
# self-deploy) - there, 3-levels-up lands under /usr or /usr/local, which is not
# a repo at all, and every "$SERVER_DIR/..." lookup below silently breaks.
REPO_DIR="${CLAUDE_SERVER_REPO:-}"
if [ -z "$REPO_DIR" ] || [ ! -f "$REPO_DIR/scripts/server/commands/install.sh" ]; then
    _candidate="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)"
    if [ -n "$_candidate" ] && [ -f "$_candidate/scripts/server/commands/install.sh" ]; then
        REPO_DIR="$_candidate"
    elif [ -f /opt/claude-code-server/scripts/server/commands/install.sh ]; then
        REPO_DIR=/opt/claude-code-server
    else
        REPO_DIR="$_candidate"
    fi
    unset _candidate
fi
SERVER_DIR="$REPO_DIR/scripts/server"

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
# executing DST (e.g. claude-watchdog polling claude-mount every 30s) never observes
# a partially-written file.
atomic_install() {
    local mode="$1" src="$2" dst="$3" owner="${4:-}" group="${5:-}" tmp="${3}.new.$$"
    if [ -n "$owner" ]; then
        install -m "$mode" -o "$owner" -g "$group" "$src" "$tmp" || return 1
    else
        install -m "$mode" "$src" "$tmp" || return 1
    fi
    mv -f "$tmp" "$dst"
}

[ "$EUID" -ne 0 ] && fail "must run as root: sudo claude-server install"

if [ ! -f "$SERVER_DIR/commands/add-user.sh" ]; then
    fail "repo not found at $REPO_DIR (SERVER_DIR=$SERVER_DIR) - set CLAUDE_SERVER_REPO=/path/to/checkout or clone/refresh /opt/claude-code-server"
fi

echo ""
echo -e "${BOLD}Claude Code Server - Full Install${NC}"
echo "repo: $REPO_DIR"
echo ""

# --- Step 1: System prerequisites -------------------------------------------
step "1 - system update + prerequisites"
apt-get update -q
apt-get install -y -q sshfs curl git python3 jq
ok "prerequisites installed"

if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" >> /etc/fuse.conf
    ok "user_allow_other enabled in /etc/fuse.conf"
else
    ok "user_allow_other: already set"
fi

# --- Step 2: Node.js ---------------------------------------------------------
step "2 - Node.js LTS"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - 2>/dev/null
    apt-get install -y -q nodejs
    ok "Node.js $(node --version) installed"
else
    ok "Node.js already installed: $(node --version)"
fi

# --- Step 3: Claude Code CLI -------------------------------------------------
step "3 - Claude Code CLI"
npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null || \
    npm install -g @anthropic-ai/claude-code 2>&1 | tail -5

CLAUDE_BIN=$(find /usr/lib/node_modules /usr/local/lib/node_modules \
    -name "claude.exe" -path "*claude-code*" 2>/dev/null | head -1)
[ -z "$CLAUDE_BIN" ] && fail "Claude binary not found after install"
ln -sf "$CLAUDE_BIN" /usr/local/bin/claude-real
ok "claude-real -> $CLAUDE_BIN"
/usr/local/bin/claude-real --version >/dev/null && ok "claude-real works"

# --- Step 4: wrapper + hooks -------------------------------------------------
step "4 - wrapper + hooks"

if [ -f "$SERVER_DIR/claude-wrapper.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-wrapper.sh" /usr/local/bin/claude
    ok "claude wrapper -> /usr/local/bin/claude"
else
    warn "claude-wrapper.sh not found - using claude-real directly"
    [ -f /usr/local/bin/claude-real ] && ln -sf /usr/local/bin/claude-real /usr/local/bin/claude
fi

for hook in claude-hook-logout-block claude-hook-pre claude-hook-stop; do
    src="$SERVER_DIR/hooks/${hook}.sh"
    if [ -f "$src" ]; then
        install -m 755 "$src" "/usr/local/bin/${hook}.sh"
        install -m 755 "$src" "/usr/local/bin/${hook}"
        ok "$hook -> /usr/local/bin/ (with and without .sh)"
    else
        warn "$hook not found in hooks/"
    fi
done

# --- Step 5: helper scripts --------------------------------------------------
step "5 - helper scripts"

if [ -f "$SERVER_DIR/claude-automount.sh" ]; then
    atomic_install 755 "$SERVER_DIR/claude-automount.sh" /usr/local/bin/claude-automount
    ok "claude-automount -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/claude-auth-sync.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-auth-sync.sh" /usr/local/bin/claude-auth-sync
    ok "claude-auth-sync -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/claude-auth-lib.py" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 644 "$SERVER_DIR/claude-auth-lib.py" /usr/local/lib/claude-server/claude-auth-lib.py
    ok "claude-auth-lib.py -> /usr/local/lib/claude-server/"
fi
if [ -f "$SERVER_DIR/claude-auth-probe.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-auth-probe.sh" /usr/local/bin/claude-auth-probe
    ok "claude-auth-probe -> /usr/local/bin/"
fi

touch /var/log/claude-auth.log
chmod 600 /var/log/claude-auth.log
ok "/var/log/claude-auth.log ready (0600 root-only)"

if [ -x /usr/local/bin/claude-auth-probe ]; then
    cat > /etc/cron.d/claude-auth-probe <<'CRON'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/30 * * * * root /usr/local/bin/claude-auth-probe cron >> /var/log/claude-auth.log 2>&1
CRON
    chmod 644 /etc/cron.d/claude-auth-probe
    ok "claude-auth-probe cron -> every 30 min"
fi
if [ -f "$SERVER_DIR/claude-mount.sh" ]; then
    if ! bash -n "$SERVER_DIR/claude-mount.sh" 2>/dev/null; then
        fail "claude-mount.sh syntax error (bash -n failed)"
    fi
    mkdir -p /usr/local/lib/claude-server
    install -m 644 "$SERVER_DIR/claude-mount.sh" /usr/local/lib/claude-server/claude-mount.sh
    [ -f "$SERVER_DIR/claude-automount.sh" ] && install -m 644 "$SERVER_DIR/claude-automount.sh" /usr/local/lib/claude-server/claude-automount.sh
    atomic_install 755 "$SERVER_DIR/claude-mount.sh" /usr/local/lib/claude-mount
    ok "claude-mount -> /usr/local/lib/claude-mount"
    ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount 2>/dev/null || true
    for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
        [ -d "/home/$u" ] || continue
        mkdir -p "/home/$u/.local/bin"
        atomic_install 755 /usr/local/lib/claude-mount "/home/$u/.local/bin/claude-mount" "$u" "$u"
    done
    ok "claude-mount -> all users ~/.local/bin/"
    if [ -x /usr/local/bin/claude-automount ]; then
        for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
            [ -d "/home/$u" ] || continue
            mkdir -p "/home/$u/.local/bin"
            atomic_install 755 /usr/local/bin/claude-automount "/home/$u/.local/bin/claude-automount" "$u" "$u"
            br="/home/$u/.bashrc"
            if [ -f "$br" ] && grep -q 'claude-automount' "$br" && ! grep -q '.local/bin/claude-automount' "$br"; then
                sed -i 's|/usr/local/bin/claude-automount 2>/dev/null|"$HOME/.local/bin/claude-automount" 2>/dev/null \|\| /usr/local/bin/claude-automount 2>/dev/null|' "$br"
            fi
        done
        ok "claude-automount -> all users ~/.local/bin/ + bashrc"
    fi
fi
if [ -f "$SERVER_DIR/claude-git-setup.sh" ]; then
    atomic_install 755 "$SERVER_DIR/claude-git-setup.sh" /usr/local/bin/claude-git-setup
    ok "claude-git-setup -> /usr/local/bin/"
    for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
        [ -d "/home/$u" ] || continue
        mkdir -p "/home/$u/.local/bin"
        atomic_install 755 /usr/local/bin/claude-git-setup "/home/$u/.local/bin/claude-git-setup" "$u" "$u"
    done
    ok "claude-git-setup -> all users ~/.local/bin/"
fi
if [ -f "$SERVER_DIR/laptop-exec.sh" ]; then
    install -m 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/bin/laptop-exec
    if [ -f "$SERVER_DIR/windows-mcp-forward.sh" ]; then
        install -m 755 "$SERVER_DIR/windows-mcp-forward.sh" /usr/local/bin/windows-mcp-forward
        ok "windows-mcp-forward -> /usr/local/bin/"
    fi
    if [ -f "$SERVER_DIR/windows-mcp-seed-agent-tools.sh" ]; then
        install -m 755 "$SERVER_DIR/windows-mcp-seed-agent-tools.sh" /usr/local/bin/windows-mcp-seed-agent-tools
        ok "windows-mcp-seed-agent-tools -> /usr/local/bin/"
    fi
    ok "laptop-exec -> /usr/local/bin/"
    if [ -f "$SERVER_DIR/skills/laptop-exec/SKILL.md" ]; then
        mkdir -p /usr/local/lib/claude-server/skills/laptop-exec
        install -m 644 "$SERVER_DIR/skills/laptop-exec/SKILL.md" \
            /usr/local/lib/claude-server/skills/laptop-exec/SKILL.md
        ok "laptop-exec skill -> /usr/local/lib/claude-server/skills/"
    fi
    if [ -f "$SERVER_DIR/cursor-rules/laptop-exec.mdc" ]; then
        mkdir -p /usr/local/lib/claude-server/cursor-rules
        install -m 644 "$SERVER_DIR/cursor-rules/laptop-exec.mdc" \
            /usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc
        ok "laptop-exec cursor rule -> /usr/local/lib/claude-server/cursor-rules/"
    fi
    if [ -d "$SERVER_DIR/cursor-hooks" ]; then
        mkdir -p /usr/local/lib/claude-server/cursor-hooks
        for _hf in laptop-exec-audit-log.sh laptop-exec-guard.sh laptop-exec-guard-wrap.sh laptop-exec-shell-scan.py laptop-exec-session.sh; do
            [ -f "$SERVER_DIR/cursor-hooks/$_hf" ] || continue
            install -m 755 "$SERVER_DIR/cursor-hooks/$_hf" \
                "/usr/local/lib/claude-server/cursor-hooks/$_hf"
        done
        install -m 644 "$SERVER_DIR/cursor-hooks/hooks-user.json" \
            /usr/local/lib/claude-server/cursor-hooks/hooks-user.json
        install -m 644 "$SERVER_DIR/cursor-hooks/hooks-project.json" \
            /usr/local/lib/claude-server/cursor-hooks/hooks-project.json
        ok "laptop-exec cursor hooks -> /usr/local/lib/claude-server/cursor-hooks/"
    fi
    for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
        [ -d "/home/$u" ] || continue
        mkdir -p "/home/$u/.local/bin"
        chown "$u:$u" "/home/$u/.local/bin" 2>/dev/null || true
        install -m 755 /usr/local/bin/laptop-exec "/home/$u/.local/bin/laptop-exec"
        chown "$u:$u" "/home/$u/.local/bin/laptop-exec"
        if [ -f "$SERVER_DIR/skills/laptop-exec/SKILL.md" ]; then
            mkdir -p "/home/$u/.cursor/skills/laptop-exec"
            install -m 644 "$SERVER_DIR/skills/laptop-exec/SKILL.md" \
                "/home/$u/.cursor/skills/laptop-exec/SKILL.md"
            chown -R "$u:$u" "/home/$u/.cursor/skills/laptop-exec"
            chown "$u:$u" "/home/$u/.cursor/skills" 2>/dev/null || true
        fi
        if [ -f "$SERVER_DIR/cursor-rules/laptop-exec.mdc" ]; then
            mkdir -p "/home/$u/.cursor/rules"
            install -m 644 "$SERVER_DIR/cursor-rules/laptop-exec.mdc" \
                "/home/$u/.cursor/rules/laptop-exec.mdc"
            chown "$u:$u" "/home/$u/.cursor/rules/laptop-exec.mdc"
            chown "$u:$u" "/home/$u/.cursor/rules" 2>/dev/null || true
        fi
    done
    ok "laptop-exec + skill + rule -> all users ~/.local/bin/ + ~/.cursor/"
    install -m 755 "$SERVER_DIR/laptop-exec.sh" /usr/local/lib/claude-server/laptop-exec.sh 2>/dev/null || true
    if [ -f "$SERVER_DIR/tests/test-laptop-exec.sh" ]; then
        mkdir -p /usr/local/lib/claude-server/tests
        install -m 755 "$SERVER_DIR/tests/test-laptop-exec.sh" /usr/local/lib/claude-server/tests/test-laptop-exec.sh
        ok "test-laptop-exec.sh -> /usr/local/lib/claude-server/tests/"
    fi
fi
if [ -f "$SERVER_DIR/laptop-exec-setup.sh" ]; then
    install -m 755 "$SERVER_DIR/laptop-exec-setup.sh" /usr/local/bin/laptop-exec-setup
    ok "laptop-exec-setup -> /usr/local/bin/"
    for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
        [ -d "/home/$u" ] || continue
        chown -R "$u:$u" "/home/$u/.cursor" 2>/dev/null || true
        sudo -u "$u" /usr/local/bin/laptop-exec-setup --user 2>/dev/null || true
        sudo -u "$u" /usr/local/bin/laptop-exec-setup --all-projects 2>/dev/null || true
    done
    ok "laptop-exec-setup --user + --all-projects -> all users"
fi
if [ -f "$SERVER_DIR/sudo-from-laptop.sh" ]; then
    install -m 755 "$SERVER_DIR/sudo-from-laptop.sh" /usr/local/bin/sudo-from-laptop
    install -m 755 "$SERVER_DIR/sudo-from-laptop.sh" /usr/local/lib/claude-server/sudo-from-laptop.sh 2>/dev/null || true
    ok "sudo-from-laptop -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/sudoers.d/claude-client-deploy" ]; then
    install -m 440 "$SERVER_DIR/sudoers.d/claude-client-deploy" /etc/sudoers.d/claude-client-deploy
    if visudo -cf /etc/sudoers.d/claude-client-deploy >/dev/null 2>&1; then
        ok "sudoers claude-client-deploy (NOPASSWD bundle install)"
    else
        rm -f /etc/sudoers.d/claude-client-deploy
        warn "sudoers claude-client-deploy invalid - skipped"
    fi
fi
if [ -f "$SERVER_DIR/commands/install-client-bundle.sh" ]; then
    mkdir -p /usr/local/lib/claude-server/commands
    install -m 755 "$SERVER_DIR/commands/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh
    ok "install-client-bundle.sh -> /usr/local/lib/claude-server/commands/"
fi
if [ -f "$SERVER_DIR/claude-watchdog.sh" ]; then
    install -m 755 "$SERVER_DIR/designer-start.sh" /usr/local/bin/designer-start
    ok "designer-start -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/check-tokens.py" ]; then
    install -m 755 "$SERVER_DIR/check-tokens.py" /usr/local/bin/claude-check-tokens
    ok "claude-check-tokens -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/cursor-auth-lib.py" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 644 "$SERVER_DIR/cursor-auth-lib.py" /usr/local/lib/claude-server/cursor-auth-lib.py
    ok "cursor-auth-lib.py -> /usr/local/lib/claude-server/"
fi
if [ -f "$SERVER_DIR/cursor-auth-export.sh" ]; then
    install -m 755 "$SERVER_DIR/cursor-auth-export.sh" /usr/local/bin/cursor-auth-export
    ok "cursor-auth-export -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/cursor-auth-sync.sh" ]; then
    install -m 755 "$SERVER_DIR/cursor-auth-sync.sh" /usr/local/bin/cursor-auth-sync
    ok "cursor-auth-sync -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/mcp-via-xray.sh" ]; then
    install -m 755 "$SERVER_DIR/mcp-via-xray.sh" /usr/local/bin/mcp-via-xray
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/mcp-via-xray.sh" /usr/local/lib/claude-server/mcp-via-xray.sh
    ok "mcp-via-xray -> /usr/local/bin/ (server-side HTTP MCP via xray)"
fi
if [ -f "$SERVER_DIR/xray-ensure-single.sh" ]; then
    install -m 755 "$SERVER_DIR/xray-ensure-single.sh" /usr/local/bin/xray-ensure-single
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/xray-ensure-single.sh" /usr/local/lib/claude-server/xray-ensure-single.sh
    ok "xray-ensure-single -> /usr/local/bin/ (single-instance helper)"
fi
if [ -f "$SERVER_DIR/xray.service" ]; then
    install -m 644 "$SERVER_DIR/xray.service" /etc/systemd/system/xray.service
    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1 || true
    if command -v xray-ensure-single >/dev/null 2>&1; then
        xray-ensure-single || true
    fi
    ok "xray.service -> /etc/systemd/system/ (ExecStartPre single-instance)"
fi
if [ -f "$SERVER_DIR/cursor-mcp-template.json" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 644 "$SERVER_DIR/cursor-mcp-template.json" /usr/local/lib/claude-server/cursor-mcp-template.json
    ok "cursor-mcp-template.json -> /usr/local/lib/claude-server/"
fi
if [ -f "$SERVER_DIR/cursor-mcp-sync.sh" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/cursor-mcp-sync.sh" /usr/local/bin/cursor-mcp-sync
    install -m 755 "$SERVER_DIR/cursor-mcp-sync.sh" /usr/local/lib/claude-server/cursor-mcp-sync.sh
    ok "cursor-mcp-sync -> /usr/local/bin/ + /usr/local/lib/claude-server/"
fi
if [ -f "$SERVER_DIR/cursor-remote-proxy-sync.sh" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/cursor-remote-proxy-sync.sh" /usr/local/bin/cursor-remote-proxy-sync
    install -m 755 "$SERVER_DIR/cursor-remote-proxy-sync.sh" /usr/local/lib/claude-server/cursor-remote-proxy-sync.sh
    ok "cursor-remote-proxy-sync -> /usr/local/bin/ + /usr/local/lib/claude-server/"
fi
if [ -f "$SERVER_DIR/skills/context7/SKILL.md" ]; then
    mkdir -p /usr/local/lib/claude-server/skills/context7
    install -m 644 "$SERVER_DIR/skills/context7/SKILL.md"         /usr/local/lib/claude-server/skills/context7/SKILL.md
    ok "context7 skill -> /usr/local/lib/claude-server/skills/"
fi
for rule in figma-design backend-agent plan-gate; do
    if [ -f "$SERVER_DIR/cursor-rules/${rule}.mdc" ]; then
        mkdir -p /usr/local/lib/claude-server/cursor-rules
        install -m 644 "$SERVER_DIR/cursor-rules/${rule}.mdc"             "/usr/local/lib/claude-server/cursor-rules/${rule}.mdc"
        ok "${rule} cursor rule -> /usr/local/lib/claude-server/cursor-rules/"
    fi
done
# Plan-flow skills (heavy-task-plan family)
for _plan_skill in heavy-task-plan evidence-gated-stages parallel-phased-execution writing-plans; do
    if [ -f "$SERVER_DIR/skills/$_plan_skill/SKILL.md" ]; then
        mkdir -p "/usr/local/lib/claude-server/skills/$_plan_skill"
        rm -rf "/usr/local/lib/claude-server/skills/$_plan_skill"
        cp -a "$SERVER_DIR/skills/$_plan_skill" "/usr/local/lib/claude-server/skills/$_plan_skill"
        find "/usr/local/lib/claude-server/skills/$_plan_skill" -type f -exec chmod 644 {} +
        find "/usr/local/lib/claude-server/skills/$_plan_skill" -type d -exec chmod 755 {} +
        ok "$_plan_skill skill -> /usr/local/lib/claude-server/skills/"
    fi
done
unset _plan_skill
# Figma write-to-canvas skills (official + Smart router)
for _figma_skill in figma-use figma-generate-design figma-create-new-file figma-designer; do
    if [ -f "$SERVER_DIR/skills/$_figma_skill/SKILL.md" ]; then
        mkdir -p "/usr/local/lib/claude-server/skills/$_figma_skill"
        rm -rf "/usr/local/lib/claude-server/skills/$_figma_skill"
        cp -a "$SERVER_DIR/skills/$_figma_skill" "/usr/local/lib/claude-server/skills/$_figma_skill"
        find "/usr/local/lib/claude-server/skills/$_figma_skill" -type f -exec chmod 644 {} +
        find "/usr/local/lib/claude-server/skills/$_figma_skill" -type d -exec chmod 755 {} +
        ok "$_figma_skill skill -> /usr/local/lib/claude-server/skills/"
    fi
done
unset _figma_skill
if [ -f "$SERVER_DIR/skills/FIGMA-SKILLS-VENDOR.md" ]; then
    install -m 644 "$SERVER_DIR/skills/FIGMA-SKILLS-VENDOR.md" \
        /usr/local/lib/claude-server/skills/FIGMA-SKILLS-VENDOR.md
    ok "FIGMA-SKILLS-VENDOR.md -> /usr/local/lib/claude-server/skills/"
fi
if [ -f "$SERVER_DIR/skills/context7/SKILL.md" ] || [ -f "$SERVER_DIR/cursor-rules/figma-design.mdc" ] || [ -f "$SERVER_DIR/cursor-rules/backend-agent.mdc" ] || [ -f "$SERVER_DIR/skills/heavy-task-plan/SKILL.md" ] || [ -f "$SERVER_DIR/skills/figma-use/SKILL.md" ]; then
    for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
        [ -d "/home/$u" ] || continue
        [ "$u" = "designer" ] && continue
        if [ -f "$SERVER_DIR/skills/context7/SKILL.md" ]; then
            mkdir -p "/home/$u/.cursor/skills/context7"
            install -m 644 "$SERVER_DIR/skills/context7/SKILL.md"                 "/home/$u/.cursor/skills/context7/SKILL.md"
            chown -R "$u:$u" "/home/$u/.cursor/skills/context7"
            chown "$u:$u" "/home/$u/.cursor/skills" 2>/dev/null || true
        fi
        for rule in figma-design backend-agent plan-gate; do
            if [ -f "$SERVER_DIR/cursor-rules/${rule}.mdc" ]; then
                mkdir -p "/home/$u/.cursor/rules"
                install -m 644 "$SERVER_DIR/cursor-rules/${rule}.mdc"                     "/home/$u/.cursor/rules/${rule}.mdc"
                chown "$u:$u" "/home/$u/.cursor/rules/${rule}.mdc"
                chown "$u:$u" "/home/$u/.cursor/rules" 2>/dev/null || true
            fi
        done
        for _plan_skill in heavy-task-plan evidence-gated-stages parallel-phased-execution writing-plans; do
            if [ -f "$SERVER_DIR/skills/$_plan_skill/SKILL.md" ]; then
                mkdir -p "/home/$u/.cursor/skills"
                rm -rf "/home/$u/.cursor/skills/$_plan_skill"
                cp -a "$SERVER_DIR/skills/$_plan_skill" "/home/$u/.cursor/skills/$_plan_skill"
                chown -R "$u:$u" "/home/$u/.cursor/skills/$_plan_skill"
            fi
        done
        unset _plan_skill
        for _figma_skill in figma-use figma-generate-design figma-create-new-file figma-designer; do
            if [ -f "$SERVER_DIR/skills/$_figma_skill/SKILL.md" ]; then
                mkdir -p "/home/$u/.cursor/skills"
                rm -rf "/home/$u/.cursor/skills/$_figma_skill"
                cp -a "$SERVER_DIR/skills/$_figma_skill" "/home/$u/.cursor/skills/$_figma_skill"
                chown -R "$u:$u" "/home/$u/.cursor/skills/$_figma_skill"
            fi
        done
        unset _figma_skill
    done
    ok "context7 + plan skills + figma skills + MCP cursor rules -> all users ~/.cursor/"
fi
if [ -f "$SERVER_DIR/cursor-auth-refresh.sh" ]; then
    install -m 755 "$SERVER_DIR/cursor-auth-refresh.sh" /usr/local/bin/cursor-auth-refresh
    ok "cursor-auth-refresh -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/cursor-auth-source-path.sh" ]; then
    install -m 755 "$SERVER_DIR/cursor-auth-source-path.sh" /usr/local/bin/cursor-auth-source-path
    ok "cursor-auth-source-path -> /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/audit-cursor-golden-deep.py" ]; then
    mkdir -p /usr/local/lib/claude-server
    install -m 755 "$SERVER_DIR/audit-cursor-golden-deep.py" /usr/local/lib/claude-server/audit-cursor-golden-deep.py
    ok "audit-cursor-golden-deep.py -> /usr/local/lib/claude-server/"
fi

# Connect client logs on server only (1-day retention)
if [ -f "$SERVER_DIR/claude-connect-logs-cleanup.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-connect-logs-cleanup.sh" /usr/local/bin/claude-connect-logs-cleanup
    cat > /etc/cron.d/claude-connect-logs <<'CRON'
# Clean per-user ~/.claude/logs older than 1 day (hourly)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 * * * * root /usr/local/bin/claude-connect-logs-cleanup >/dev/null 2>&1
CRON
    chmod 644 /etc/cron.d/claude-connect-logs
    ok "claude-connect-logs-cleanup + cron"
else
    warn "claude-connect-logs-cleanup.sh missing in repo (skip cron; sync server checkout)"
fi

# Stuck sshfs/sftp mount-helper reaper (every 10 min) - see script header for why
# these can survive for days without this: `timeout 30` on the foreground sshfs
# call does not bound the persistent `-o reconnect` background daemon it forks.
if [ -f "$SERVER_DIR/claude-mount-reaper.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-mount-reaper.sh" /usr/local/bin/claude-mount-reaper
    touch /var/log/claude-mount-reaper.log
    chmod 600 /var/log/claude-mount-reaper.log
    cat > /etc/cron.d/claude-mount-reaper <<'CRON'
# Kill sshfs/sftp mount helpers stuck for 10+ minutes (every 10 min)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/10 * * * * root /usr/local/bin/claude-mount-reaper >/dev/null 2>&1
CRON
    chmod 644 /etc/cron.d/claude-mount-reaper
    ok "claude-mount-reaper cron -> /etc/cron.d/claude-mount-reaper (every 10 min, log: /var/log/claude-mount-reaper.log)"
else
    warn "claude-mount-reaper.sh missing in repo (skip cron; sync server checkout)"
fi

# Idle old Cursor Remote server-main reaper (hourly). Default cron uses --apply.
# Protects builds with live TCP clients; skips trees younger than 1h. See script header.
if [ -f "$SERVER_DIR/cursor-server-reaper.sh" ]; then
    install -m 755 "$SERVER_DIR/cursor-server-reaper.sh" /usr/local/bin/cursor-server-reaper
    touch /var/log/cursor-server-reaper.log
    chmod 600 /var/log/cursor-server-reaper.log
    cat > /etc/cron.d/cursor-server-reaper <<'CRON'
# Reap idle old cursor-server server-main trees (estab=0, age>=1h)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
15 * * * * root /usr/local/bin/cursor-server-reaper --apply >/dev/null 2>&1
CRON
    chmod 644 /etc/cron.d/cursor-server-reaper
    ok "cursor-server-reaper cron -> /etc/cron.d/cursor-server-reaper (hourly :15, log: /var/log/cursor-server-reaper.log)"
else
    warn "cursor-server-reaper.sh missing in repo (skip cron; sync server checkout)"
fi


mkdir -p /etc/cursor-auth/golden
# cursorauth group: every developer needs to read auth.json/machine-id.txt/
# state-keys.json/exported-at over their own unprivileged SSH session so
# cursor-auth-laptop.ps1's laptop-side sync can actually work - a plain 0700
# root-only tree (the old default) makes every single probe indistinguishable
# from "golden bundle missing", even when it's present and fresh (this was a
# real, ~9-day-long outage of the laptop auth-sync feature on both Smart and
# Sepidz before anyone noticed). source-host/storage.json stay 600 root-only -
# the client only needs auth.json/machine-id.txt/state-keys.json/exported-at.
getent group cursorauth >/dev/null 2>&1 || groupadd cursorauth
chgrp cursorauth /etc/cursor-auth /etc/cursor-auth/golden 2>/dev/null || true
chmod 750 /etc/cursor-auth /etc/cursor-auth/golden
# Harden any pre-existing secret files (legacy 644 from older installs/refresh),
# then re-open exactly the 3 files the laptop sync needs via the group.
chmod 600 /etc/cursor-auth/golden/* 2>/dev/null || true
if [ -f /etc/cursor-auth/golden/auth.json ]; then
    chgrp cursorauth /etc/cursor-auth/golden/auth.json /etc/cursor-auth/golden/machine-id.txt /etc/cursor-auth/golden/state-keys.json /etc/cursor-auth/golden/exported-at 2>/dev/null || true
    chmod 640 /etc/cursor-auth/golden/auth.json /etc/cursor-auth/golden/machine-id.txt /etc/cursor-auth/golden/state-keys.json 2>/dev/null || true
    chmod 644 /etc/cursor-auth/golden/exported-at 2>/dev/null || true
fi
ok "/etc/cursor-auth/golden ready (0750 + cursorauth group; source-host/storage.json stay 0600)"

touch /var/log/cursor-auth-refresh.log
chmod 644 /var/log/cursor-auth-refresh.log
ok "/var/log/cursor-auth-refresh.log ready"

if [ -x /usr/local/bin/cursor-auth-refresh ]; then
    cat > /etc/cron.d/cursor-auth-refresh <<'CRON'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 */6 * * * root /usr/local/bin/cursor-auth-refresh >> /var/log/cursor-auth-refresh.log 2>&1
CRON
    chmod 644 /etc/cron.d/cursor-auth-refresh
    ok "cursor-auth-refresh cron -> /etc/cron.d/cursor-auth-refresh (every 6h)"
fi

# --- Step 6: config + runtime dirs ------------------------------------------
step "6 - config + runtime dirs"

if [ -f "$SERVER_DIR/claude-limits.conf" ]; then
    install -m 644 "$SERVER_DIR/claude-limits.conf" /etc/claude-limits.conf
    ok "/etc/claude-limits.conf installed"
fi

mkdir -p /var/run/claude-active
chmod 1777 /var/run/claude-active
ok "/var/run/claude-active ready (sticky 1777)"

touch /var/log/claude-activity.jsonl
chmod 666 /var/log/claude-activity.jsonl
ok "/var/log/claude-activity.jsonl ready"

# --- Step 7: SSH forwarding --------------------------------------------------
step "7 - SSH forwarding"

if grep -qiE "^[[:space:]]*AllowTcpForwarding[[:space:]]+no" /etc/ssh/sshd_config 2>/dev/null; then
    sed -i -E 's/^[[:space:]]*AllowTcpForwarding[[:space:]]+no/AllowTcpForwarding yes/I' /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "AllowTcpForwarding enabled"
else
    ok "AllowTcpForwarding: ok (default yes)"
fi

# --- Step 8: designer dependencies ------------------------------------------
step "8 - designer dependencies (Xvfb, x11vnc, noVNC, Chrome)"

for pkg in xvfb x11vnc fluxbox autocutsel; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        ok "$pkg: already installed"
    else
        apt-get install -y -q "$pkg" && ok "$pkg installed"
    fi
done

# websockify
if command -v websockify &>/dev/null; then
    ok "websockify: installed"
else
    apt-get install -y -q python3-websockify 2>/dev/null && ok "websockify installed" || \
    pip3 install websockify --quiet 2>/dev/null && ok "websockify installed via pip" || \
    warn "websockify: install manually (apt install python3-websockify)"
fi

# noVNC
if [ ! -d /opt/novnc ]; then
    NOVNC_SHARE=$(find /usr /opt -name "vnc.html" 2>/dev/null | head -1 | xargs -r dirname 2>/dev/null || true)
    if [ -n "$NOVNC_SHARE" ]; then
        ln -sf "$NOVNC_SHARE" /opt/novnc
        ok "noVNC -> /opt/novnc (system)"
    else
        git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc 2>/dev/null && ok "noVNC cloned to /opt/novnc" || \
        warn "noVNC: install manually (git clone https://github.com/novnc/noVNC.git /opt/novnc)"
    fi
else
    ok "noVNC: /opt/novnc exists"
fi

# Chrome
if command -v google-chrome-stable &>/dev/null; then
    ok "Chrome: $(google-chrome-stable --version 2>/dev/null | head -1)"
else
    curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/chrome.deb 2>/dev/null && \
    apt-get install -y /tmp/chrome.deb 2>/dev/null && \
    ok "Chrome installed" || \
    warn "Chrome install failed - install manually"
    rm -f /tmp/chrome.deb
fi

# --- Step 10: Headroom (context compression MCP) -----------------------------
step "10 - Headroom"
if command -v headroom &>/dev/null; then
    ok "Headroom: already installed"
else
    pip3 install "headroom-ai[mcp]" --quiet && ok "headroom-ai[mcp] installed" || \
        warn "headroom-ai install failed - run manually: pip3 install 'headroom-ai[mcp]'"
fi

# --- Step 10a: Cursor CLI (optional bootstrap for agent login) ----------------
step "10a - Cursor CLI"

if command -v agent &>/dev/null; then
    ok "Cursor CLI: already installed ($(agent --version 2>/dev/null | head -1 || echo ok))"
else
    if curl -fsSL https://cursor.com/install -o /tmp/cursor-install.sh 2>/dev/null; then
        bash /tmp/cursor-install.sh 2>/dev/null && ok "Cursor CLI installed" || \
            warn "Cursor CLI install failed - run manually: curl https://cursor.com/install -fsS | bash"
        rm -f /tmp/cursor-install.sh
    else
        warn "Cursor CLI download failed - install manually for bootstrap login"
    fi
fi

# --- Step 10b: mcp-sqlserver --------------------------------------------------
step "10b - mcp-sqlserver"
if command -v mcp-sqlserver &>/dev/null; then
    ok "mcp-sqlserver: already installed"
else
    npm install -g @bilims/mcp-sqlserver --quiet && ok "mcp-sqlserver installed" || \
        warn "mcp-sqlserver install failed - run manually: npm install -g @bilims/mcp-sqlserver"
fi

# --- Step 11: designer user ---------------------------------------------------
step "11 - designer user"

if ! id designer &>/dev/null; then
    useradd -m -s /bin/bash designer
    passwd -l designer
    ok "designer user created (password locked)"
else
    ok "designer user: exists"
fi

mkdir -p /opt/chrome-design-profile/Default /home/designer/.designer /home/designer/.local/share
chown -R designer:designer /opt/chrome-design-profile /home/designer/.designer /home/designer/.local
chmod -R 755 /opt/chrome-design-profile

# Use Chrome managed policy so Chrome can never overwrite the download directory setting.
POLICY_DIR="/etc/opt/chrome/policies/managed"
POLICY_FILE="$POLICY_DIR/designer-download.json"
DOWNLOAD_PATH="/home/designer/mounts/laptop"
mkdir -p "$POLICY_DIR"
cat > "$POLICY_FILE" <<EOF
{
  "DownloadDirectory": "${DOWNLOAD_PATH}",
  "PromptForDownloadLocation": false
}
EOF
chmod 644 "$POLICY_FILE"
ok "Chrome managed policy -> ${DOWNLOAD_PATH}"
ok "designer directories ready"

# --- Step 10: admin user smart -----------------------------------------------
step "12 - admin user: smart"

if ! id smart &>/dev/null; then
    useradd -m -s /bin/bash -G sudo smart
    echo "  Set password for smart:"
    passwd smart
    ok "user smart created"
else
    ok "user smart: exists"
fi
chmod 755 /home/smart

# run full user setup for smart (idempotent)
bash "$SERVER_DIR/commands/add-user.sh" smart --no-password-change

# --- Step 11: install claude-server CLI --------------------------------------
step "13 - install claude-server CLI"

install -m 755 "$SERVER_DIR/claude-server" /usr/local/bin/claude-server

mkdir -p /usr/local/lib/claude-server
for cmd_file in "$SERVER_DIR/commands/"*.sh; do
    [ -f "$cmd_file" ] || continue
    install -m 755 "$cmd_file" /usr/local/lib/claude-server/
done
ok "claude-server -> /usr/local/bin/claude-server"
ok "commands -> /usr/local/lib/claude-server/"

# OAuth store: root-only dir + file (never leave token in world-readable /etc/environment 644).
mkdir -p /etc/claude-code

# Remind ops: MCP golden secrets are not in git — place before sync is useful
#   /etc/claude-code/sqlserver.env   (SQLSERVER_HOST/USER/PASSWORD, mode 0600)
#   /etc/claude-code/figma-mcp.env   (FIGMA_MCP_ACCESS_TOKEN=figu_..., mode 0600)
chmod 700 /etc/claude-code
if [ -f /etc/claude-code/oauth.env ]; then
    chmod 600 /etc/claude-code/oauth.env
fi
# Migrate legacy token from /etc/environment into oauth.env (0600) and strip environment.
if grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment 2>/dev/null; then
    if [ -f /usr/local/lib/claude-server/claude-auth-lib.py ]; then
        if python3 <<'PYMIG'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cal", "/usr/local/lib/claude-server/claude-auth-lib.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
tok = mod.read_env_token()
if tok:
    mod.write_env_token(tok)
sys.exit(0)
PYMIG
        then
            ok "OAuth migrated to /etc/claude-code/oauth.env (0600); stripped from /etc/environment"
        else
            echo "WARN: OAuth migrate from /etc/environment failed (manual: claude-server deploy-auth)" >&2
        fi
    fi
fi

if { [ -f /etc/claude-code/oauth.env ] && grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/claude-code/oauth.env 2>/dev/null; } \
    || grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment 2>/dev/null; then
    if [ -x /usr/local/bin/claude-auth-sync ]; then
        claude-auth-sync --all
        ok "OAuth token synced to all users"
    fi
fi

if [ -f /etc/cursor-auth/golden/auth.json ] && [ -x /usr/local/bin/cursor-auth-sync ]; then
    cursor-auth-sync --all
    ok "Cursor golden identity synced to all users"
fi

if [ -x /usr/local/bin/cursor-mcp-sync ]; then
    cursor-mcp-sync --all || warn "cursor-mcp-sync --all failed (non-fatal)"
    ok "Cursor MCP pack synced to all users"
fi

if [ -x /usr/local/bin/cursor-remote-proxy-sync ]; then
    cursor-remote-proxy-sync --all || warn "cursor-remote-proxy-sync --all failed (non-fatal)"
    ok "Cursor remote Machine proxy synced to all users"
fi

DEPLOY_BUNDLE=""
for _dcb in "$SERVER_DIR/deploy-client-bundle.sh" "$SERVER_DIR/commands/deploy-client-bundle.sh"; do
    [ -f "$_dcb" ] && DEPLOY_BUNDLE="$_dcb" && break
done
if [ -n "$DEPLOY_BUNDLE" ]; then
    bash "$DEPLOY_BUNDLE"
    ok "client bundle deployed for laptop auto-update"
fi

# --- Done --------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  Install complete!${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Set Claude auth token:"
echo "     On a laptop with a browser: claude setup-token"
echo "     Then on this server as root:"
echo "       sudo claude-server deploy-auth <token>"
echo "     (stores root-only /etc/claude-code/oauth.env mode 0600; syncs per-user settings)"
echo ""
echo "  2. Add developers:"
echo "       sudo claude-server add-user <username>"
echo ""
echo "  3. Verify:"
echo "       sudo claude-server verify"
echo ""
echo "  After OAuth token change:"
echo "       sudo claude-server sync-auth"
echo ""
echo "  Cursor golden auth (one-time bootstrap):"
echo "       agent login   # or connect once via Remote SSH to populate ~/.config/Cursor/"
echo "       sudo cursor-auth-export --from-user smart"
echo "       sudo claude-server sync-cursor-auth"
echo ""
echo "  Cursor MCP pack (figma, context7, playwright, sqlserver, ...):"
echo "       sudo claude-server sync-cursor-mcp"
echo ""


