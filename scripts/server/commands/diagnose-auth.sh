#!/bin/bash
# diagnose-auth.sh - find why Claude / SSH keeps asking to log in
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
echo -e "${BOLD}Claude Code Server - Auth / Login Diagnostics${NC}"
echo -e "${GRAY}$(date -Is 2>/dev/null || date)  host=$(hostname -f 2>/dev/null || hostname)${NC}"

# --- 1. Claude OAuth token (most common "please log in" cause) ---------------
step "Claude OAuth token"

TOKEN_FILE="/etc/claude-code/oauth.env"
AUTH_FILE="/etc/profile.d/claude-auth.sh"
ENV_FILE="/etc/environment"

token_secure=""
token_legacy=""

if [ -f "$TOKEN_FILE" ]; then
    token_secure="$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$TOKEN_FILE" 2>/dev/null | tail -1 \
        | sed -E 's/^CLAUDE_CODE_OAUTH_TOKEN=//; s/^["'\'' ]//; s/["'\'' ]$//')"
    perms="$(stat -c '%a %U:%G' "$TOKEN_FILE" 2>/dev/null || echo '?')"
    mode="${perms%% *}"
    if [ -n "$token_secure" ]; then
        ok "found CLAUDE_CODE_OAUTH_TOKEN in $TOKEN_FILE"
        info "$(token_fingerprint "$token_secure") mode=$perms"
        case "$mode" in
            600|0600) ok "oauth.env is root-only (600)" ;;
            *) fail "oauth.env should be chmod 600 (got $mode)"; note_fail ;;
        esac
    else
        fail "$TOKEN_FILE exists but token empty"
        note_fail
    fi
else
    fail "missing $TOKEN_FILE (root-only token store)"
    note_fail
    info "Fix: sudo claude-server deploy-auth <token>"
fi

# Legacy world-readable locations must NOT hold the token anymore.
if [ -f "$ENV_FILE" ] && grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' "$ENV_FILE" 2>/dev/null; then
    token_legacy="$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$ENV_FILE" 2>/dev/null | tail -1 \
        | sed -E 's/^CLAUDE_CODE_OAUTH_TOKEN=//; s/^["'\'' ]//; s/["'\'' ]$//')"
    fail "CLAUDE_CODE_OAUTH_TOKEN still in world-readable $ENV_FILE"
    note_fail
    info "Fix: sudo claude-server deploy-auth <token>  (migrates to $TOKEN_FILE and strips legacy)"
fi
if [ -f "$AUTH_FILE" ] && grep -qE 'CLAUDE_CODE_OAUTH_TOKEN=' "$AUTH_FILE" 2>/dev/null; then
    fail "CLAUDE_CODE_OAUTH_TOKEN still exported from $AUTH_FILE"
    note_fail
    info "Fix: sudo claude-server deploy-auth <token>"
elif [ -f "$AUTH_FILE" ]; then
    ok "found $AUTH_FILE (stub; no token export)"
else
    info "optional stub missing: $AUTH_FILE (created by deploy-auth)"
fi

if [ -z "$token_secure" ] && [ -z "$token_legacy" ]; then
    fail "no OAuth token configured anywhere"
    note_fail
fi

# For later live-env checks, prefer secure token.
token_env="$token_secure"
token_profile="$token_secure"
[ -n "$token_legacy" ] && [ -z "$token_env" ] && token_env="$token_legacy"

[ -x /usr/local/bin/claude-auth-sync ] && ok "claude-auth-sync installed" || warn "claude-auth-sync missing - run: sudo claude-server install"
[ -x /usr/local/bin/claude-auth-probe ] && ok "claude-auth-probe installed" || warn "claude-auth-probe missing - run: sudo claude-server install"
if [ -f /var/log/claude-auth.log ]; then
    ok "audit log: /var/log/claude-auth.log"
    alperms="$(stat -c '%a' /var/log/claude-auth.log 2>/dev/null || echo '?')"
    case "$alperms" in
        600|0600) ok "audit log mode 600" ;;
        *) warn "audit log should be chmod 600 (got $alperms)" ;;
    esac
else
    info "audit log not created yet - run: sudo claude-server install"
fi

if [ -f /etc/cron.d/claude-auth-probe ]; then
    ok "probe cron: /etc/cron.d/claude-auth-probe (every 30 min)"
else
    warn "probe cron missing - run: sudo claude-server install"
fi

if [ -f /var/log/claude-auth.log ]; then
    last_probe="$(grep '"event":"PROBE_' /var/log/claude-auth.log 2>/dev/null | tail -1 || true)"
    if [ -n "$last_probe" ]; then
        info "last probe: $last_probe"
    fi
fi


# --- 2. Live env check (simulates login shell vs VS Code shell) -------------
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
    fail "non-login shell would NOT see token - Cursor/VS Code will ask to log in"
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

# --- 3. SSH first-login password (different "login" prompt) -----------------
step "SSH password / first-login flags"

SYSTEM_USERS="nobody root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats _apt designer administrator"
passwd_issues=0

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
    h="/home/$u"
    [ -d "$h" ] || continue
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    if chage -l "$u" 2>/dev/null | grep -q 'password must be changed'; then
        fail "$u - SSH will force password change on every login until you run: passwd $u"
        note_fail
        passwd_issues=$((passwd_issues + 1))
    else
        ok "$u - no forced password change"
    fi
done

[ "$passwd_issues" -eq 0 ] && info "If SSH asks for password (not Claude), check ~/.ssh/authorized_keys on server + laptop connect script"

# --- 4. Per-user Claude setup -----------------------------------------------
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
            warn ".credentials.json has stale OAuth data - run: sudo claude-server sync-auth $u"
        else
            ok ".credentials.json empty (will not shadow server token)"
        fi
    else
        info ".credentials.json missing (sync-auth will create it)"
    fi
    _user_grep "$h/.bashrc" 'claude-automount' && ok "automount in .bashrc" || warn "automount missing in .bashrc"
done

# --- 5. Active sessions / mounts --------------------------------------------
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

# --- 6. Designer Chrome login (designer-only "log in" prompt) ---------------
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

# --- 7. Quick Claude auth probe ---------------------------------------------
step "Claude auth probe"

if command -v claude &>/dev/null && [ -n "$login_token" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$login_token"
    unset ANTHROPIC_BASE_URL
    probe_out="$(timeout 12 claude -p 'reply with exactly: AUTH_OK' --max-turns 1 2>&1)" || probe_rc=$?
    probe_rc="${probe_rc:-0}"
    if [ "$probe_rc" -eq 0 ] && printf '%s' "$probe_out" | grep -q 'AUTH_OK'; then
        ok "Claude accepted the OAuth token (test prompt succeeded)"
    elif printf '%s' "$probe_out" | grep -qiE 'login|authenticate|oauth|unauthorized|invalid.*token|expired'; then
        fail "Claude rejected the token - token is missing, wrong, or expired"
        note_fail
        info "Re-run on a laptop: claude setup-token"
        info "Then: sudo claude-server deploy-auth '<token>'"
        info "Probe output (last 5 lines):"
        printf '%s\n' "$probe_out" | tail -5 | while read -r line; do info "  $line"; done
    else
        warn "auth probe inconclusive (exit $probe_rc) - check manually: claude -p 'hi'"
        info "Probe output (last 5 lines):"
        printf '%s\n' "$probe_out" | tail -5 | while read -r line; do info "  $line"; done
    fi
else
    info "skipped (no claude binary or no token)"
fi

# --- 8. Cursor golden auth ---------------------------------------------------
step "Cursor golden auth"

GOLDEN_DIR="/etc/cursor-auth/golden"
GOLDEN_AUTH="$GOLDEN_DIR/auth.json"
GOLDEN_MID="$GOLDEN_DIR/machine-id.txt"

if [ -f "$GOLDEN_AUTH" ]; then
    ok "golden bundle: $GOLDEN_AUTH"
    golden_mid="$(tr -d '[:space:]' < "$GOLDEN_MID" 2>/dev/null || true)"
    if [ -n "$golden_mid" ]; then
        ok "golden machineId: ${golden_mid:0:12}..."
    else
        fail "golden machine-id.txt missing or empty"
        note_fail
    fi
    if [ -f "$GOLDEN_DIR/exported-at" ]; then
        info "exported: $(tr -d '\n' < "$GOLDEN_DIR/exported-at" 2>/dev/null)"
    fi
    access_token="$(python3 - "$GOLDEN_AUTH" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get("accessToken", ""), end="")
PY
)"
    if [ -n "$access_token" ]; then
        exp_info="$(python3 - "$access_token" <<'PY' 2>/dev/null || true
import base64, json, sys, time
token = sys.argv[1]
parts = token.split(".")
if len(parts) < 2:
    print("unknown", end="")
    raise SystemExit
payload = parts[1] + "=" * (-len(parts[1]) % 4)
data = json.loads(base64.urlsafe_b64decode(payload.encode()))
exp = data.get("exp")
if exp:
    print(f"exp={exp} in={int(exp)-int(time.time())}s", end="")
else:
    print("no-exp", end="")
PY
)"
        ok "golden access token present ($exp_info)"
    else
        fail "golden accessToken missing"
        note_fail
    fi
    refresh_token="$(python3 - "$GOLDEN_AUTH" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get("refreshToken", ""), end="")
PY
)"
    if [ -n "$refresh_token" ]; then
        ok "golden refresh token present"
    else
        fail "golden refreshToken missing"
        note_fail
    fi
    if [ -f "$GOLDEN_DIR/state-keys.json" ]; then
        ok "golden state-keys.json present"
    else
        warn "golden state-keys.json missing - re-export: sudo cursor-auth-export --from-user <name>"
    fi
else
    warn "no golden Cursor auth - optional until Cursor IDE is used"
    info "Bootstrap: agent login (or Remote SSH once), then sudo cursor-auth-export --from-user <name>"
    QREASON="/etc/cursor-auth/golden.quarantine-reason"
    if [ -f "$QREASON" ]; then
        q_email="$(python3 - "$QREASON" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
print(d.get("email", ""), end="")
PY
)"
        q_reason="$(python3 - "$QREASON" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
print(d.get("reason", ""), end="")
PY
)"
        fail "golden missing after personal-email quarantine (email=${q_email:-unknown} reason=${q_reason:-unknown})"
        note_fail
        info "Do NOT restore /etc/cursor-auth/golden.quarantined-personal â€” re-export from a work/team account"
        info "Override only with: sudo cursor-auth-export --from-user <name> --allow-personal"
    fi
fi

[ -x /usr/local/bin/cursor-auth-sync ] && ok "cursor-auth-sync installed" || warn "cursor-auth-sync missing - run: sudo claude-server install"
[ -x /usr/local/bin/cursor-auth-export ] && ok "cursor-auth-export installed" || warn "cursor-auth-export missing"
[ -x /usr/local/bin/cursor-auth-refresh ] && ok "cursor-auth-refresh installed" || warn "cursor-auth-refresh missing"

if [ -f /etc/cron.d/cursor-auth-refresh ]; then
    ok "refresh cron: /etc/cron.d/cursor-auth-refresh"
else
    warn "refresh cron missing - run: sudo claude-server install"
fi

if [ -f /var/log/cursor-auth-refresh.log ]; then
    last_refresh="$(grep 'OK tokens refreshed' /var/log/cursor-auth-refresh.log 2>/dev/null | tail -1 || true)"
    if [ -n "$last_refresh" ]; then
        info "last refresh: $last_refresh"
    else
        info "no successful refresh logged yet"
    fi
fi

if [ -f "$GOLDEN_AUTH" ] && [ -n "${golden_mid:-}" ]; then
    for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
        h="/home/$u"
        [ -d "$h" ] || continue
        echo "$SYSTEM_USERS" | grep -qw "$u" && continue
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
        has_tokens="$(python3 - "$h" <<'PY' 2>/dev/null || true
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
        if [ "$has_tokens" != "yes" ]; then
            warn "$u - Cursor tokens not synced (run: sudo claude-server sync-cursor-auth $u)"
            continue
        fi
        if [ -z "$user_mid" ]; then
            fail "$u - Cursor machineId missing (run: sudo claude-server sync-cursor-auth $u)"
            note_fail
        elif [ "$user_mid" = "$golden_mid" ]; then
            ok "$u - machineId matches golden"
        else
            fail "$u - machineId drift (run: sudo claude-server sync-cursor-auth $u)"
            note_fail
        fi
    done
fi

if [ -d /home/smart/.cursor-server ] || compgen -G "/home/*/.cursor-server" >/dev/null 2>&1; then
    ok "cursor-server runtime present on at least one user home"
else
    info "cursor-server not installed yet (normal until first Remote SSH connect)"
fi

# --- Summary -----------------------------------------------------------------
step "Summary"

if [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}No obvious auth problems found.${NC}"
    echo ""
    echo "  If you still see a login prompt, note WHERE it appears:"
    echo "    - SSH password prompt     -> run connect.bat/connect.sh on laptop, or: passwd <user>"
    echo "    - Cursor/VS Code -> token in ~/.claude/settings.json via claude-auth-sync (root store: /etc/claude-code/oauth.env)"
    echo "    - claude CLI in terminal  -> refresh OAuth token (claude setup-token)"
    echo "    - Designer Chrome/noVNC   -> log in to claude.ai once in server Chrome"
    echo "    - Cursor Chat/Composer    -> run: sudo claude-server sync-cursor-auth"
else
    echo -e "  ${RED}${BOLD}$ISSUES issue(s) found - see FAIL lines above.${NC}"
    echo ""
    echo "  Most common fix for 'claude keeps asking to log in':"
    echo "    1. On laptop:  claude setup-token"
    echo "    2. On server (root):  sudo claude-server deploy-auth '<paste-token>'"
    echo "    3. sudo claude-server diagnose-auth"
    echo ""
    echo "  Cursor IDE golden auth fix:"
    echo "    1. Log in once (Remote SSH or: agent login)"
    echo "    2. sudo cursor-auth-export --from-user <name>"
    echo "    3. sudo claude-server sync-cursor-auth"
    echo "    4. Reload Cursor window (Developer: Reload Window)"
fi
echo ""

exit "$([ "$ISSUES" -eq 0 ] && echo 0 || echo 1)"
