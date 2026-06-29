#!/bin/bash
# diagnose-auth.sh — find why Claude / SSH keeps asking to log in
# Usage: sudo bash diagnose-auth.sh
#        (or: sudo claude-server diagnose-auth  after install)

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
GRAY='\033[0;37m'
NC='\033[0m'

ok()   { printf "  ${GREEN}OK${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}WARN${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; }
info() { printf "  ${GRAY}--${NC}    %s\n" "$1"; }
step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

ISSUES=0
note_fail() { ISSUES=$((ISSUES + 1)); }

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

token_from_file() {
    local f="$1"
    [ -f "$f" ] || return 1
    # shellcheck disable=SC1090
    local val
    val="$(grep -E '^[[:space:]]*(export[[:space:]]+)?CLAUDE_CODE_OAUTH_TOKEN=' "$f" 2>/dev/null | tail -1 \
        | sed -E 's/^[[:space:]]*(export[[:space:]]+)?CLAUDE_CODE_OAUTH_TOKEN=//; s/^["'\'' ]//; s/["'\'' ]$//')"
    [ -n "$val" ] || return 1
    printf '%s' "$val"
}

token_fingerprint() {
    local t="$1"
    [ -n "$t" ] || { printf 'empty'; return; }
    printf 'len=%d prefix=%s...' "${#t}" "${t:0:8}"
}

echo ""
echo -e "${BOLD}Claude Code Server — Auth / Login Diagnostics${NC}"
echo -e "${GRAY}$(date -Is 2>/dev/null || date)  host=$(hostname -f 2>/dev/null || hostname)${NC}"

# ─── 1. Claude OAuth token (most common "please log in" cause) ───────────────
step "Claude OAuth token"

AUTH_FILE="/etc/profile.d/claude-auth.sh"
ENV_FILE="/etc/environment"

token_profile=""
token_env=""

if [ -f "$AUTH_FILE" ]; then
    token_profile="$(token_from_file "$AUTH_FILE" || true)"
    ok "found $AUTH_FILE"
    info "$(token_fingerprint "$token_profile")"
else
    fail "missing $AUTH_FILE"
    note_fail
    info "Fix: claude setup-token on a laptop, then on server as root:"
    info "  echo 'export CLAUDE_CODE_OAUTH_TOKEN=<token>' > $AUTH_FILE"
    info "  chmod 644 $AUTH_FILE"
fi

if [ -f "$ENV_FILE" ]; then
    token_env="$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$ENV_FILE" 2>/dev/null | tail -1 \
        | sed -E 's/^CLAUDE_CODE_OAUTH_TOKEN=//; s/^["'\'' ]//; s/["'\'' ]$//')"
    if [ -n "$token_env" ]; then
        ok "found CLAUDE_CODE_OAUTH_TOKEN in $ENV_FILE"
        info "$(token_fingerprint "$token_env")"
    else
        fail "CLAUDE_CODE_OAUTH_TOKEN not in $ENV_FILE"
        note_fail
        info "VS Code / Cursor Remote SSH uses non-login shells — token MUST be in $ENV_FILE"
        info "Fix: echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> $ENV_FILE"
    fi
else
    fail "missing $ENV_FILE"
    note_fail
fi

if [ -n "$token_profile" ] && [ -n "$token_env" ] && [ "$token_profile" != "$token_env" ]; then
    fail "token mismatch between $AUTH_FILE and $ENV_FILE"
    note_fail
    info "Both files must contain the same token"
fi

if [ -z "$token_profile" ] && [ -z "$token_env" ]; then
    fail "no OAuth token configured anywhere"
    note_fail
fi

if [ -f "$AUTH_FILE" ]; then
    perms="$(stat -c '%a %U:%G' "$AUTH_FILE" 2>/dev/null || stat -f '%OLp %Su:%Sg' "$AUTH_FILE" 2>/dev/null || echo '?')"
    info "permissions: $perms"
    case "$perms" in
        644|640|600) ok "auth file permissions look fine" ;;
        *) warn "auth file permissions may block login shells: $perms (use chmod 644)" ;;
    esac
fi

[ -x /usr/local/bin/claude-auth-sync ] && ok "claude-auth-sync installed" || warn "claude-auth-sync missing — run: sudo claude-server install"

# ─── 2. Live env check (simulates login shell vs VS Code shell) ─────────────
step "Environment visibility"

login_token=""
if [ -f "$AUTH_FILE" ]; then
    # shellcheck disable=SC1090
    source "$AUTH_FILE" 2>/dev/null || true
    login_token="${CLAUDE_CODE_OAUTH_TOKEN:-}"
fi

vscode_token=""
if [ -f "$ENV_FILE" ]; then
    vscode_token="$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$ENV_FILE" 2>/dev/null | tail -1 \
        | sed -E 's/^CLAUDE_CODE_OAUTH_TOKEN=//; s/^["'\'' ]//; s/["'\'' ]$//')"
fi

if [ -n "$login_token" ]; then
    ok "login shell would see token ($(token_fingerprint "$login_token"))"
else
    fail "login shell does NOT see CLAUDE_CODE_OAUTH_TOKEN"
    note_fail
fi

if [ -n "$vscode_token" ]; then
    ok "non-login shell (VS Code terminal) would see token"
else
    fail "non-login shell would NOT see token — Cursor/VS Code will ask to log in"
    note_fail
fi

if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
    warn "ANTHROPIC_BASE_URL is set: $ANTHROPIC_BASE_URL (may break OAuth)"
else
    ok "ANTHROPIC_BASE_URL not set"
fi

if command -v claude &>/dev/null; then
    ver="$(claude --version 2>/dev/null | head -1)"
    ok "claude CLI: ${ver:-unknown}"
else
    fail "claude not in PATH"
    note_fail
fi

# ─── 3. SSH first-login password (different "login" prompt) ─────────────────
step "SSH password / first-login flags"

SYSTEM_USERS="nobody root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats _apt designer administrator"
passwd_issues=0

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
    h="/home/$u"
    [ -d "$h" ] || continue
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    if chage -l "$u" 2>/dev/null | grep -q 'password must be changed'; then
        fail "$u — SSH will force password change on every login until you run: passwd $u"
        note_fail
        passwd_issues=$((passwd_issues + 1))
    else
        ok "$u — no forced password change"
    fi
done

[ "$passwd_issues" -eq 0 ] && info "If SSH asks for password (not Claude), check ~/.ssh/authorized_keys on server + laptop connect script"

# ─── 4. Per-user Claude setup ───────────────────────────────────────────────
step "User Claude setup"

if [ "$EUID" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
    info "Re-run as root for full per-user checks: sudo claude-server diagnose-auth"
fi

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
    h="/home/$u"
    [ -d "$h" ] || continue
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    printf "  ${BOLD}%-16s${NC}\n" "$u"
    _user_readable "$h/.local/bin/claude-mount" && ok "claude-mount" || warn "claude-mount missing (re-run: sudo claude-server add-user $u)"
    if _user_readable "$h/.claude/settings.json"; then
        ok "settings.json"
        if _user_grep "$h/.claude/settings.json" 'CLAUDE_CODE_OAUTH_TOKEN'; then
            ok "OAuth token in settings.json (VS Code extension)"
        else
            fail "OAuth token missing from settings.json"
            note_fail
            info "Fix: sudo claude-server sync-auth $u"
        fi
    else
        warn "settings.json missing or unreadable"
    fi
    if _user_readable "$h/.claude/.credentials.json"; then
        if _user_grep "$h/.claude/.credentials.json" 'oauth\|access_token\|refresh_token\|apiKey'; then
            warn ".credentials.json has stale OAuth data — run: sudo claude-server sync-auth $u"
        else
            ok ".credentials.json empty (will not shadow server token)"
        fi
    else
        info ".credentials.json missing (sync-auth will create it)"
    fi
    _user_grep "$h/.bashrc" 'claude-automount' && ok "automount in .bashrc" || warn "automount missing in .bashrc"
done

# ─── 5. Active sessions / mounts ────────────────────────────────────────────
step "Active tunnels and mounts"

if [ -d /var/run/claude-active ]; then
    active="$(ls -1 /var/run/claude-active 2>/dev/null | wc -l | tr -d ' ')"
    info "active session files: $active"
    ls -1 /var/run/claude-active 2>/dev/null | while read -r f; do info "  $f"; done
else
    warn "/var/run/claude-active missing"
fi

mount_count=0
for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
    m="/home/$u/mounts"
    [ -d "$m" ] || continue
    for d in "$m"/*; do
        [ -d "$d" ] || continue
        if mountpoint -q "$d" 2>/dev/null; then
            info "mounted: $u -> $(basename "$d")"
            mount_count=$((mount_count + 1))
        fi
    done
done
[ "$mount_count" -eq 0 ] && info "no SSHFS mounts active (normal if nobody is connected)"

# ─── 6. Designer Chrome login (designer-only "log in" prompt) ───────────────
step "Designer (Chrome / noVNC)"

if id designer &>/dev/null; then
    ok "designer user exists"
    if pgrep -u designer -f 'google-chrome' &>/dev/null; then
        ok "Chrome process running for designer"
        info "If designer sees claude.ai login page: log in once in Chrome on the server desktop"
    else
        info "Chrome not running (starts when designer connects)"
    fi
else
    info "designer user not configured"
fi

# ─── 7. Quick Claude auth probe ─────────────────────────────────────────────
step "Claude auth probe"

if command -v claude &>/dev/null && [ -n "$login_token" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$login_token"
    unset ANTHROPIC_BASE_URL
    probe_out="$(timeout 12 claude -p 'reply with exactly: AUTH_OK' --max-turns 1 2>&1)" || probe_rc=$?
    probe_rc="${probe_rc:-0}"
    if [ "$probe_rc" -eq 0 ] && printf '%s' "$probe_out" | grep -q 'AUTH_OK'; then
        ok "Claude accepted the OAuth token (test prompt succeeded)"
    elif printf '%s' "$probe_out" | grep -qiE 'login|authenticate|oauth|unauthorized|invalid.*token|expired'; then
        fail "Claude rejected the token — token is missing, wrong, or expired"
        note_fail
        info "Re-run on a laptop: claude setup-token"
        info "Then update $AUTH_FILE and $ENV_FILE with the new token"
        info "Probe output (last 5 lines):"
        printf '%s\n' "$probe_out" | tail -5 | while read -r line; do info "  $line"; done
    else
        warn "auth probe inconclusive (exit $probe_rc) — check manually: claude -p 'hi'"
        info "Probe output (last 5 lines):"
        printf '%s\n' "$probe_out" | tail -5 | while read -r line; do info "  $line"; done
    fi
else
    info "skipped (no claude binary or no token)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
step "Summary"

if [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}No obvious auth problems found.${NC}"
    echo ""
    echo "  If you still see a login prompt, note WHERE it appears:"
    echo "    - SSH password prompt     → run connect.bat/connect.sh on laptop, or: passwd <user>"
    echo "    - Cursor/VS Code terminal → token must be in /etc/environment (see above)"
    echo "    - claude CLI in terminal  → refresh OAuth token (claude setup-token)"
    echo "    - Designer Chrome/noVNC   → log in to claude.ai once in server Chrome"
else
    echo -e "  ${RED}${BOLD}$ISSUES issue(s) found — see FAIL lines above.${NC}"
    echo ""
    echo "  Most common fix for 'claude keeps asking to log in':"
    echo "    1. On laptop:  claude setup-token"
    echo "    2. On server (root):"
    echo "         echo 'export CLAUDE_CODE_OAUTH_TOKEN=<paste-token>' > /etc/profile.d/claude-auth.sh"
    echo "         chmod 644 /etc/profile.d/claude-auth.sh"
    echo "         grep -v CLAUDE_CODE_OAUTH_TOKEN /etc/environment > /tmp/env && mv /tmp/env /etc/environment"
    echo "         echo 'CLAUDE_CODE_OAUTH_TOKEN=<paste-token>' >> /etc/environment"
    echo "    3. sudo claude-server sync-auth"
    echo "    4. Disconnect and reconnect Cursor/VS Code"
fi
echo ""

exit "$([ "$ISSUES" -eq 0 ] && echo 0 || echo 1)"
