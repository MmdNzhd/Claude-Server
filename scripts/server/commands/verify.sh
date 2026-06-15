#!/bin/bash
# commands/verify.sh - verify all Claude Code Server components
# Usage: claude-server verify

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

echo ""
echo -e "${BOLD}=== Claude Code Server — Verify ===${NC}"
echo ""

# --- System binaries ---
echo -e "${BOLD}System${NC}"

CLAUDE_VER=$(claude --version 2>/dev/null | head -1)
[ -n "$CLAUDE_VER" ] && ok "claude: $CLAUDE_VER" || fail "claude: not in PATH"

[ -L /usr/local/bin/claude-real ] && \
    ok "claude-real → $(readlink /usr/local/bin/claude-real)" || \
    fail "claude-real: symlink missing"

[ -f /usr/local/bin/claude ] && ok "claude wrapper: exists" || fail "claude wrapper: missing"

for h in claude-hook-pre claude-hook-stop claude-hook-logout-block; do
    [ -x "/usr/local/bin/$h" ] && ok "$h: installed" || fail "$h: missing or not executable"
done

for b in claude-automount claude-git-setup; do
    [ -x "/usr/local/bin/$b" ] && ok "$b: installed" || warn "$b: missing"
done

[ -f /usr/local/lib/claude-mount ] && ok "claude-mount: installed" || warn "claude-mount: missing"
[ -f /etc/claude-limits.conf ] && ok "claude-limits.conf: exists" || warn "claude-limits.conf: missing (default limit=2)"
[ -d /var/run/claude-active ] && ok "/var/run/claude-active: exists" || fail "/var/run/claude-active: missing"
[ -f /var/log/claude-activity.jsonl ] && ok "activity log: exists" || warn "activity log: missing (created on first use)"

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

# --- Users ---
echo -e "${BOLD}Users${NC}"
echo ""

SYSTEM_USERS="nobody root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats _apt designer administrator"

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
    h="/home/$u"
    [ -d "$h" ] || continue
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    score=0; total=4
    has_mount=false
    [ -f "$h/.local/bin/claude-mount" ] && has_mount=true && ((score++))

    has_hooks=false
    has_effort=false
    if [ -f "$h/.claude/settings.json" ]; then
        grep -q 'claude-hook-pre' "$h/.claude/settings.json" 2>/dev/null && has_hooks=true && ((score++))
        grep -q 'effortLevel'     "$h/.claude/settings.json" 2>/dev/null && has_effort=true && ((score++))
    fi

    has_bashrc=false
    grep -q 'claude-automount' "$h/.bashrc" 2>/dev/null && has_bashrc=true && ((score++))

    if   [ "$score" -eq "$total" ]; then tag="${GREEN}READY${NC}"
    elif [ "$score" -eq 0 ];        then tag="${RED}EMPTY${NC}"
    else                                 tag="${YELLOW}PARTIAL ($score/$total)${NC}"
    fi

    printf "  ${BOLD}%-16s${NC} " "$u"
    echo -e "$tag"
    $has_mount   && ok "claude-mount"      || fail "claude-mount missing"
    $has_hooks   && ok "hooks configured"  || fail "hooks missing in settings.json"
    $has_effort  && ok "effortLevel set"   || warn "effortLevel missing"
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
