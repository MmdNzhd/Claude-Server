#!/bin/bash
# commands/verify.sh - verify all Claude Code Server components
# Usage: claude-server verify
#        sudo claude-server verify   (required to read other users' home dirs)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
GRAY='\033[0;37m'
NC='\033[0m'

FAILURES=0

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; FAILURES=$((FAILURES+1)); }
info() { printf "  ${GRAY}--${NC}    %s\n" "$1"; }

# Read another user's home file (needs root or sudo for mode-700 homes).
_user_readable() {
    local f="$1"
    [ -f "$f" ] && [ -r "$f" ] && return 0
    [ "$EUID" -eq 0 ] && [ -f "$f" ] && return 0
    command -v sudo >/dev/null 2>&1 && sudo test -r "$f" 2>/dev/null
}

_user_grep() {
    local f="$1" pattern="$2"
    if [ -f "$f" ] && [ -r "$f" ]; then
        grep -q "$pattern" "$f" 2>/dev/null
    elif [ "$EUID" -eq 0 ] && [ -f "$f" ]; then
        grep -q "$pattern" "$f" 2>/dev/null
    elif command -v sudo >/dev/null 2>&1 && sudo test -r "$f" 2>/dev/null; then
        sudo grep -q "$pattern" "$f" 2>/dev/null
    else
        return 1
    fi
}

echo ""
echo -e "${BOLD}=== Claude Code Server - Verify ===${NC}"
echo ""

# --- System binaries ---
echo -e "${BOLD}System${NC}"

CLAUDE_VER=$(claude --version 2>/dev/null | head -1)
[ -n "$CLAUDE_VER" ] && ok "claude: $CLAUDE_VER" || fail "claude: not in PATH"

[ -L /usr/local/bin/claude-real ] && \
    ok "claude-real -> $(readlink /usr/local/bin/claude-real)" || \
    fail "claude-real: symlink missing"

[ -f /usr/local/bin/claude ] && ok "claude wrapper: exists" || fail "claude wrapper: missing"

for h in claude-hook-pre claude-hook-stop claude-hook-logout-block; do
    [ -x "/usr/local/bin/$h" ] && ok "$h: installed" || fail "$h: missing or not executable"
done

for b in claude-automount claude-auth-sync claude-git-setup cursor-auth-sync cursor-auth-export cursor-auth-refresh cursor-mcp-sync cursor-remote-proxy-sync; do
    [ -x "/usr/local/bin/$b" ] && ok "$b: installed" || warn "$b: missing"
done

# Cursor MCP golden secrets (Figma OAuth + SQL)
if [ -f /etc/claude-code/figma-mcp.env ]; then
    _mode=$(stat -c '%a' /etc/claude-code/figma-mcp.env 2>/dev/null || echo '?')
    [ "$_mode" = "600" ] && ok "figma-mcp.env mode 600" || warn "figma-mcp.env mode $_mode (want 600)"
    grep -q '^FIGMA_MCP_ACCESS_TOKEN=figu_' /etc/claude-code/figma-mcp.env && ok "figma-mcp.env has figu_ token" || warn "figma-mcp.env missing figu_ access token"
else
    warn "figma-mcp.env missing (Figma golden OAuth)"
fi
if [ -f /etc/claude-code/sqlserver.env ]; then
    _mode=$(stat -c '%a' /etc/claude-code/sqlserver.env 2>/dev/null || echo '?')
    [ "$_mode" = "600" ] && ok "sqlserver.env mode 600" || warn "sqlserver.env mode $_mode (want 600)"
    grep -q '^SQLSERVER_USER=Claude_Ai' /etc/claude-code/sqlserver.env && ok "sqlserver.env user Claude_Ai" || warn "sqlserver.env user not Claude_Ai"
else
    warn "sqlserver.env missing"
fi


[ -f /usr/local/lib/claude-server/cursor-mcp-template.json ] && ok "cursor-mcp-template.json: installed" || warn "cursor-mcp-template.json: missing"

[ -f /usr/local/lib/claude-mount ] && ok "claude-mount: installed" || warn "claude-mount: missing"
if [ -f /usr/local/lib/claude-mount ]; then
    grep -q 'GIT_MODE' /usr/local/lib/claude-mount && ok "claude-mount: GIT_MODE support" || warn "claude-mount: outdated (no GIT_MODE - run claude-server install)"
fi
if [ -f /usr/local/share/claude-client/git-mode.ps1 ]; then
    grep -q 'Clear-ServerStaleTunnelForward' /usr/local/share/claude-client/git-mode.ps1 \
        && ok "client bundle: stale tunnel self-healing (Windows)" \
        || warn "client bundle: outdated git-mode.ps1 (run: sudo claude-server deploy-client-bundle)"
    grep -q 'stop_session_tunnel_cleanup' /usr/local/share/claude-client/mac/git-mode.sh 2>/dev/null \
        && ok "client bundle: stale tunnel self-healing (Mac)" \
        || warn "client bundle: outdated mac/git-mode.sh"
else
    warn "client bundle: missing (/usr/local/share/claude-client/)"
fi
[ -x /usr/local/bin/claude-server ] && grep -q 'deploy-client-bundle' /usr/local/bin/claude-server \
    && ok "claude-server CLI: deploy-client-bundle" \
    || warn "claude-server CLI outdated (run: sudo claude-server install)"
[ -f /etc/claude-limits.conf ] && ok "claude-limits.conf: exists" || warn "claude-limits.conf: missing (default limit=2)"
[ -d /var/run/claude-active ] && ok "/var/run/claude-active: exists" || fail "/var/run/claude-active: missing"
[ -f /var/log/claude-activity.jsonl ] && ok "activity log: exists" || warn "activity log: missing (created on first use)"

if [ -f /etc/claude-code/oauth.env ] && grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/claude-code/oauth.env 2>/dev/null; then
    perms="$(stat -c '%a' /etc/claude-code/oauth.env 2>/dev/null || echo '?')"
    ok "server OAuth token: /etc/claude-code/oauth.env (mode $perms)"
    if [ "$perms" != "600" ] && [ "$perms" != "0600" ]; then
        warn "oauth.env should be mode 600 (root-only)"
    fi
elif grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment 2>/dev/null; then
    warn "OAuth token still in world-readable /etc/environment — run: sudo claude-server deploy-auth <token>"
else
    fail "server OAuth token missing from /etc/claude-code/oauth.env"
fi

if [ -f /etc/cursor-auth/golden/auth.json ]; then
    ok "Cursor golden auth: /etc/cursor-auth/golden/"
else
    warn "Cursor golden auth not configured (optional until Cursor IDE is used)"
fi

echo ""

# --- Designer ---
echo -e "${BOLD}Designer${NC}"

for bin in Xvfb x11vnc websockify fluxbox; do
    command -v "$bin" &>/dev/null && ok "$bin: installed" || fail "$bin: not found"
done

command -v google-chrome-stable &>/dev/null && \
    ok "Chrome: $(google-chrome-stable --version 2>/dev/null | head -1)" || \
    fail "Chrome: not found"

id designer &>/dev/null && ok "designer user: exists" || warn "designer user: missing"
[ -x /usr/local/bin/designer-start ] && ok "designer-start: installed" || warn "designer-start: missing"

echo ""


# --- Laptop exec (Windows-MCP first; LE fallback) ---
echo -e "${BOLD}Laptop Exec (Windows-MCP first; LE fallback)${NC}"
[ -x /usr/local/bin/laptop-exec ] && ok "laptop-exec: installed" || fail "laptop-exec: missing"
if [ -x /usr/local/bin/laptop-exec ]; then
    grep -q 'mount-status' /usr/local/bin/laptop-exec && ok "laptop-exec: mount-status/write/health" || fail "laptop-exec: outdated (run: sudo claude-server deploy-laptop-exec)"
    grep -q 'ControlPersist' /usr/local/bin/laptop-exec && ok "laptop-exec: multiplex SSH (fast)" || warn "laptop-exec: old (no ControlPersist)"
    grep -q 'git grep' /usr/local/bin/laptop-exec && ok "laptop-exec: git-grep search (accurate)" || warn "laptop-exec: old rg (findstr)"
    grep -qE 'Windows-MCP first|Parallel MCP' /usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc 2>/dev/null && ok "cursor rule: Windows-MCP first" || warn "cursor rule outdated"
    grep -q '\-w' /usr/local/lib/claude-server/cursor-rules/laptop-exec.mdc 2>/dev/null && ok "cursor rule: -w workspace" || warn "cursor rule: missing -w flag docs"
    grep -q 'Read|Write' /usr/local/lib/claude-server/cursor-hooks/laptop-exec-guard.sh 2>/dev/null && ok "cursor hook: blocks Read/Write on /mounts/" || warn "cursor hook outdated"
    [ -x /usr/local/bin/laptop-exec-setup ] && ok "laptop-exec-setup: installed" || warn "laptop-exec-setup missing"
    [ -x /usr/local/lib/claude-server/tests/test-laptop-exec.sh ] && ok "test-laptop-exec.sh: installed" || warn "test-laptop-exec.sh missing"
fi
echo ""

# --- Users ---
echo -e "${BOLD}Users${NC}"
if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    info "Re-run as root to check other users: sudo claude-server verify"
fi
echo ""

SYSTEM_USERS="nobody root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats _apt designer administrator"

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
    h="/home/$u"
    [ -d "$h" ] || continue
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    score=0
    total=5
    has_mount=false
    _user_readable "$h/.local/bin/claude-mount" && has_mount=true && ((score++))

    has_hooks=false
    has_effort=false
    has_oauth=false
    has_cursor=false
    has_cursor_machine=false
    cursor_golden=false
    [ -f /etc/cursor-auth/golden/auth.json ] && cursor_golden=true && total=7
    if _user_readable "$h/.claude/settings.json"; then
        _user_grep "$h/.claude/settings.json" 'claude-hook-pre' && has_hooks=true && ((score++))
        _user_grep "$h/.claude/settings.json" 'effortLevel'     && has_effort=true && ((score++))
        _user_grep "$h/.claude/settings.json" 'CLAUDE_CODE_OAUTH_TOKEN' && has_oauth=true && ((score++))
    fi

    if $cursor_golden; then
        golden_mid="$(tr -d '[:space:]' < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null || true)"
        user_mid="$(python3 - "$h" <<'PY' 2>/dev/null || true
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location(
    "cal", "/usr/local/lib/claude-server/cursor-auth-lib.py"
)
cal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cal)
print(cal.user_machine_id(Path(sys.argv[1])) or "", end="")
PY
)"
        access_ok="$(python3 - "$h" <<'PY' 2>/dev/null || true
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location(
    "cal", "/usr/local/lib/claude-server/cursor-auth-lib.py"
)
cal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cal)
print("yes" if cal.user_has_tokens(Path(sys.argv[1])) else "no", end="")
PY
)"
        if [ "$access_ok" = "yes" ]; then
            has_cursor=true
            ((score++))
        fi
        if [ -n "$user_mid" ] && [ -n "$golden_mid" ] && [ "$user_mid" = "$golden_mid" ]; then
            has_cursor_machine=true
            ((score++))
        fi
    fi

    has_bashrc=false
    _user_grep "$h/.bashrc" 'claude-automount' && has_bashrc=true && ((score++))

    if   [ "$score" -eq "$total" ]; then tag="${GREEN}READY${NC}"
    elif [ "$score" -eq 0 ];        then tag="${RED}EMPTY${NC}"
    else                                 tag="${YELLOW}PARTIAL ($score/$total)${NC}"
    fi

    printf "  ${BOLD}%-16s${NC} " "$u"
    echo -e "$tag"
    $has_mount   && ok "claude-mount"      || fail "claude-mount missing"
    $has_hooks   && ok "hooks configured"  || fail "hooks missing in settings.json"
    $has_effort  && ok "effortLevel set"   || warn "effortLevel missing"
    $has_oauth   && ok "OAuth in settings" || fail "OAuth token missing in settings.json (run: sudo claude-server sync-auth)"
    if [ -f /etc/cursor-auth/golden/auth.json ]; then
        $has_cursor && ok "Cursor auth in state.vscdb" || fail "Cursor auth missing (run: sudo claude-server sync-cursor-auth $u)"
        $has_cursor_machine && ok "Cursor machineId matches golden" || warn "Cursor machineId mismatch (run: sudo claude-server sync-cursor-auth $u)"
    fi
    has_le=false; has_le_rule=false; has_le_hook=false
    _user_readable "$h/.local/bin/laptop-exec" && has_le=true
    _user_readable "$h/.cursor/rules/laptop-exec.mdc" && has_le_rule=true
    _user_readable "$h/.cursor/hooks/laptop-exec-guard.sh" && has_le_hook=true
    $has_le && ok "laptop-exec CLI" || warn "laptop-exec missing (~/.local/bin)"
    $has_le_rule && ok "laptop-exec rule" || warn "laptop-exec.mdc missing"
    $has_le_hook && ok "laptop-exec hook" || warn "laptop-exec-guard.sh missing"
    if _user_readable "$h/.cursor/skills/figma-use/SKILL.md"; then
        ok "figma-use skill (~/.cursor/skills/figma-use/SKILL.md)"
    else
        warn "figma-use skill missing (~/.cursor/skills/figma-use/SKILL.md; run: sudo claude-server install)"
    fi
    if _user_readable "$h/.cursor/skills/figma-designer/SKILL.md"; then
        ok "figma-designer skill"
    else
        warn "figma-designer skill missing"
    fi
    if _user_readable "$h/.cursor/skills/figma-designer/references/club-design-kit.md"; then
        ok "figma-designer Club kit (club-design-kit.md)"
    else
        warn "figma-designer Club kit missing (references/club-design-kit.md)"
    fi
    if _user_readable "$h/.cursor/mcp.json"; then
        for _mcp_key in figma context7 playwright sequential-thinking memory sqlserver; do
            _user_grep "$h/.cursor/mcp.json" "\"$_mcp_key\"" && ok "Cursor MCP: $_mcp_key" || warn "Cursor MCP: $_mcp_key missing in ~/.cursor/mcp.json"
        done
        unset _mcp_key
        _user_grep "$h/.cursor/mcp.json" "Bearer figu_" && ok "Cursor MCP: figma OAuth bearer" || warn "Cursor MCP: figma missing Bearer figu_ (run: sudo claude-server sync-cursor-mcp $u)"
        _user_grep "$h/.cursor/mcp.json" "Claude_Ai" && ok "Cursor MCP: sqlserver user Claude_Ai" || warn "Cursor MCP: sqlserver user not Claude_Ai"
        if _user_grep "$h/.cursor/mcp.json" "CHANGE_ME" || _user_grep "$h/.cursor/mcp.json" "\"Mohammad\""; then
            warn "Cursor MCP: stale SQL placeholder still present"
        fi
    else
        info "Cursor MCP: ~/.cursor/mcp.json not present (run: sudo claude-server sync-cursor-mcp $u)"
    fi
    # windows-mcp hybrid (Windows laptops only): per-UID forward, no shared 18000.
    _wmcp_env="$h/.config/windows-mcp/env"
    if _user_readable "$_wmcp_env"; then
        _uid=$(id -u "$u" 2>/dev/null || echo 0)
        _expect=$((28000 + _uid - 1000))
        _fport=""; _lport=""
        if [ -r "$_wmcp_env" ] || [ "$EUID" -eq 0 ]; then
            _fport=$(awk -F= '/^WINDOWS_MCP_FORWARD_PORT=/{print $2; exit}' "$_wmcp_env")
            _lport=$(awk -F= '/^WINDOWS_MCP_LOCAL_PORT=/{print $2; exit}' "$_wmcp_env")
        fi
        if [ -n "$_fport" ] && [ "$_fport" = "$_expect" ]; then
            ok "windows-mcp forward port $_fport (per-UID)"
        elif [ -n "$_fport" ]; then
            warn "windows-mcp forward port $_fport != expected $_expect (stale shared-port config; reconnect Windows client)"
        else
            warn "windows-mcp env present but FORWARD_PORT missing"
        fi
        if [ "$_fport" = "18000" ]; then
            warn "windows-mcp still on shared 18000 (multi-user collision risk)"
        fi
        if [ "$_lport" = "8000" ]; then
            info "windows-mcp laptop port 8000 (Hyper-V may block; client prefers 18765)"
        fi
        _tp=""
        if _user_readable "$h/.claude-connect.conf"; then
            if [ -r "$h/.claude-connect.conf" ] || [ "$EUID" -eq 0 ]; then
                _tp=$(awk -F= '/^TUNNEL_PORT=/{print $2; exit}' "$h/.claude-connect.conf")
            fi
        fi
        if [ -n "$_tp" ] && [ -n "$_fport" ] && nc -zw1 127.0.0.1 "$_tp" 2>/dev/null; then
            if ss -ltn "( sport = :$_fport )" 2>/dev/null | grep -q ":$_fport"; then
                ok "windows-mcp forward listening :$_fport (tunnel up)"
            else
                warn "windows-mcp forward DOWN on :$_fport while tunnel $_tp is up (watchdog should restart)"
            fi
        fi
        unset _uid _expect _fport _lport _tp
    fi
    unset _wmcp_env
    if _user_readable "$h/.claude/settings.json"; then
        _user_grep "$h/.claude/settings.json" "Bearer figu_" && ok "Claude MCP: figma OAuth bearer" || warn "Claude MCP: figma missing Bearer figu_"
        _user_grep "$h/.claude/settings.json" "\"sqlserver\"" && ok "Claude MCP: sqlserver" || warn "Claude MCP: sqlserver missing"
        _user_grep "$h/.claude/settings.json" "Claude_Ai" && ok "Claude MCP: sqlserver user Claude_Ai" || warn "Claude MCP: sqlserver user not Claude_Ai"
    else
        info "Claude settings.json not present for MCP checks"
    fi
    $has_bashrc  && ok "automount .bashrc" || fail "automount missing in .bashrc"
    echo ""
done

# --- Summary ---
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed.${NC}"
else
    echo -e "${RED}${BOLD}$FAILURES check(s) failed.${NC}"
    exit 1
fi
echo ""

