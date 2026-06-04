#!/bin/bash
# check-users.sh - show setup status for every user on the server
# Usage: sudo bash check-users.sh
# No changes made -- read-only.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
miss() { printf "  ${RED}miss${NC}  %s\n" "$1"; }
info() { printf "  ${GRAY}--${NC}    %s\n" "$1"; }

echo ""
echo -e "${BOLD}=== System ===${NC}"
CLAUDE_VER=$(claude --version 2>/dev/null | head -1)
[ -n "$CLAUDE_VER" ] && ok "claude: $CLAUDE_VER" || miss "claude: not found"
[ -L /usr/local/bin/claude-real ] && ok "claude-real: symlink -> $(readlink /usr/local/bin/claude-real)" || miss "claude-real: not a symlink"
[ -f /etc/claude-limits.conf ] && ok "claude-limits.conf: exists" || warn "claude-limits.conf: missing (default limit=2)"
[ -d /var/run/claude-active ] && ok "/var/run/claude-active: exists" || miss "/var/run/claude-active: missing"
for h in /usr/local/bin/claude-automount /usr/local/bin/claude-watchdog /usr/local/bin/claude-git-setup; do
    [ -x "$h" ] && ok "$(basename $h): installed" || miss "$(basename $h): missing"
done
for h in /usr/local/bin/claude-hook-pre /usr/local/bin/claude-hook-stop /usr/local/bin/claude-hook-logout-block; do
    [ -x "$h" ] && ok "$(basename $h): installed" || miss "$(basename $h): missing"
done

echo ""
echo -e "${BOLD}=== Users ===${NC}"
echo ""

SYSTEM_USERS="nobody root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats _apt"

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
    h="/home/$u"
    [ -d "$h" ] || continue

    # skip obvious non-developer system accounts
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    score=0
    total=6

    # collect status
    has_mount=false;    [ -f "$h/.local/bin/claude-mount" ]    && has_mount=true    && ((score++))
    has_gitsetup=false; [ -f "$h/.local/bin/claude-git-setup" ] && has_gitsetup=true && ((score++))
    has_settings=false; [ -f "$h/.claude/settings.json" ]       && has_settings=true
    has_hooks=false
    has_effort=false
    if $has_settings; then
        grep -q 'claude-hook-pre' "$h/.claude/settings.json" 2>/dev/null && has_hooks=true && ((score++))
        grep -q 'effortLevel'     "$h/.claude/settings.json" 2>/dev/null && has_effort=true && ((score++))
    fi
    has_bashrc=false;  grep -q 'claude-automount' "$h/.bashrc" 2>/dev/null && has_bashrc=true && ((score++))
    has_sshkey=false;  [ -f "$h/.ssh/claude_laptop" ]           && has_sshkey=true  && ((score++))
    n_mounts=$(ls "$h/.claude-mounts.d/"*.conf 2>/dev/null | wc -l)
    has_passwd=false;  chage -l "$u" 2>/dev/null | grep -q 'password must be changed' && has_passwd=true

    # header with score
    if   [ "$score" -eq "$total" ]; then color=$GREEN; tag="READY"
    elif [ "$score" -eq 0 ];        then color=$RED;   tag="EMPTY"
    else                                 color=$YELLOW; tag="PARTIAL ($score/$total)"
    fi

    printf "${BOLD}%-18s${NC} ${color}%s${NC}\n" "$u" "$tag"

    $has_mount     && ok "claude-mount"      || miss "claude-mount"
    $has_gitsetup  && ok "claude-git-setup"  || miss "claude-git-setup"
    $has_hooks     && ok "hooks in settings" || { $has_settings && miss "hooks missing" || miss "settings.json missing"; }
    $has_effort    && ok "effortLevel set"   || miss "effortLevel missing"
    $has_bashrc    && ok "automount .bashrc" || miss "automount .bashrc"
    $has_sshkey    && ok "server SSH key"    || miss "server SSH key (not connected yet)"
    [ "$n_mounts" -gt 0 ] && info "projects: $n_mounts configured" || info "projects: none"
    $has_passwd    && warn "must change password on first login"

    echo ""
done
