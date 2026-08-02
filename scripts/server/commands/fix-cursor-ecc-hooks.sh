#!/bin/bash
# fix-cursor-ecc-hooks.sh — neutralize Claude-format ECC hooks inside Cursor plugin trees.
#
# Why: ECC ships hooks/hooks.json (Claude PreToolUse schema) into ~/.cursor/plugins/.
# Cursor loads those as preToolUse; observe-runner echoes stdin instead of
# {"permission":"allow"} → "Hook preToolUse returned stdout that is not valid JSON".
#
# Scope: ONLY ~/.cursor/plugins/{cache,marketplaces}/**/hooks/hooks.json
# Does NOT touch ~/.claude/plugins (Claude Code ecc@ecc stays intact).
# Does NOT modify ~/.cursor/hooks.json (laptop-exec wrap stays authoritative).
#
# Usage:
#   sudo claude-server fix-cursor-ecc-hooks
#   sudo claude-server fix-cursor-ecc-hooks USER
#   sudo bash scripts/server/commands/fix-cursor-ecc-hooks.sh [--dry-run] [user]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; exit 1; }

DRY_RUN=0
USER_FILTER=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            fail "unknown option: $arg"
            ;;
        *)
            USER_FILTER="$arg"
            ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    fail "run as root: sudo claude-server fix-cursor-ecc-hooks"
fi

MARKER="disabled-claude-on-cursor"
# Backup suffix keeps the Claude graph recoverable if someone needs it under Cursor.
BAK_SUFFIX=".${MARKER}.bak"

is_claude_hooks_file() {
    local f="$1"
    python3 - "$f" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(1)
s = json.dumps(d)
hooks = d.get("hooks") or {}
# Claude schema markers (capital-case lifecycle / observe bootstrap)
if any(k in hooks for k in ("PreToolUse", "PostToolUse", "SessionStart", "PreCompact", "PostToolUseFailure")):
    sys.exit(0)
if "pre:observe" in s or "observe-runner.js" in s or "plugin-hook-bootstrap.js" in s:
    sys.exit(0)
if "$schema" in d and "claude-code" in str(d.get("$schema", "")):
    sys.exit(0)
sys.exit(1)
PY
}

disable_file() {
    local f="$1"
    local bak="${f}${BAK_SUFFIX}"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY  would disable: $f"
        return 0
    fi
    # Idempotent: already disabled → ok
    if [ -f "$bak" ] && [ ! -f "$f" ]; then
        return 0
    fi
    if [ -f "$f" ]; then
        # Replace live file with empty Cursor-safe stub so reinstallers that
        # rewrite the path still do not reintroduce Claude PreToolUse until
        # the next full plugin extract (we also leave .bak).
        mv -f "$f" "$bak"
        printf '%s\n' '{"version":1,"hooks":{},"_comment":"Claude-format ECC hooks disabled for Cursor; see '"$(basename "$bak")"'"}' >"$f"
        chmod --reference="$bak" "$f" 2>/dev/null || chmod 644 "$f"
        # ownership follow parent
        local owner
        owner="$(stat -c '%U:%G' "$(dirname "$f")" 2>/dev/null || true)"
        if [ -n "$owner" ]; then
            chown "$owner" "$f" "$bak" 2>/dev/null || true
        fi
    fi
}

process_user() {
    local u="$1"
    local home="/home/$u"
    local plugins="$home/.cursor/plugins"
    [ -d "$plugins" ] || return 0

    local     found=0 disabled=0 skipped=0
    # Only ECC Cursor plugin trees (cache + marketplace). Other plugins
    # (e.g. superpowers) may also ship Claude-format hooks/hooks.json; we
    # neutralize those too when they carry observe/bootstrap (same Cursor break).
    while IFS= read -r -d '' f; do
        found=$((found + 1))
        # Skip our own stub if already rewritten without Claude markers
        if ! is_claude_hooks_file "$f"; then
            skipped=$((skipped + 1))
            continue
        fi
        disable_file "$f"
        disabled=$((disabled + 1))
        ok "$u: disabled $(echo "$f" | sed "s|^$home/||")"
    done < <(find "$plugins/cache" "$plugins/marketplaces" \
        \( -path '*/hooks/hooks.json' \) -type f -print0 2>/dev/null)

    # Also catch already-backed-up trees where a fresh plugin write restored Claude hooks
    if [ "$found" -eq 0 ]; then
        return 0
    fi
    if [ "$disabled" -eq 0 ] && [ "$skipped" -gt 0 ]; then
        ok "$u: already clean ($skipped hooks/hooks.json under .cursor/plugins)"
    elif [ "$disabled" -eq 0 ]; then
        warn "$u: scanned $found file(s), nothing matched Claude schema"
    fi
}

echo ""
echo -e "${BOLD}=== fix-cursor-ecc-hooks ===${NC}"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "  mode: ${YELLOW}dry-run${NC}"
fi
echo -e "  scope: ~/.cursor/plugins only (Claude ~/.claude/plugins untouched)"
echo ""

users=()
if [ -n "$USER_FILTER" ]; then
    [ -d "/home/$USER_FILTER" ] || fail "no such home: /home/$USER_FILTER"
    users=("$USER_FILTER")
else
    while IFS= read -r u; do
        [ -d "/home/$u" ] || continue
        users+=("$u")
    done < <(awk -F: '$3>=1000 {print $1}' /etc/passwd | sort)
fi

total_users=0
for u in "${users[@]}"; do
    if [ -d "/home/$u/.cursor/plugins" ]; then
        total_users=$((total_users + 1))
        process_user "$u"
    fi
done

echo ""
ok "scanned users with ~/.cursor/plugins: $total_users"
echo -e "  ${BOLD}next${NC}: Reload Window in Cursor (Remote SSH) so plugin hooks refresh"
echo ""
