#!/bin/bash
# deploy-client-bundle.sh - publish client scripts for laptop auto-update
# Usage: sudo claude-server deploy-client-bundle
# Installs to /usr/local/share/claude-client/ (client scripts only; no server/ tree).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    fail "run as root: sudo claude-server deploy-client-bundle"
fi

# Honor server freeze marker (Sepidz: /usr/local/share/claude-client.FROZEN).
# Smart has no marker => deploy continues. Override: FORCE_UNFREEZE=1
if [ -f /usr/local/share/claude-client.FROZEN ] && [ "${FORCE_UNFREEZE:-0}" != "1" ]; then
    fail "client bundle FROZEN (/usr/local/share/claude-client.FROZEN). Set FORCE_UNFREEZE=1 to override."
fi

SELF="$(readlink -f "$0")"
COMMANDS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
REPO_DIR="${CLAUDE_SERVER_REPO:-$(cd "$COMMANDS_DIR/../../.." && pwd 2>/dev/null)}"
CLIENT_DIR="$REPO_DIR/scripts/client"


_stage_repo_from_laptop() {
    local stage="/var/tmp/claude-code-server-staging" rel dst
    STAGE_USER="${LAPTOP_EXEC_STAGE_USER:-smart}"
    rm -rf "$stage"
    mkdir -p "$stage"
    if ! sudo -u "$STAGE_USER" laptop-exec status >/dev/null 2>&1; then
        return 1
    fi
    _pull() {
        rel="$1"
        dst="$stage/$rel"
        mkdir -p "$(dirname "$dst")"
        if ! sudo -u "$STAGE_USER" laptop-exec read -p claude-code-server "$rel" > "$dst" 2>/dev/null; then
            return 1
        fi
        [ -s "$dst" ] || { rm -f "$dst"; return 1; }
    }
    local paths=(
        scripts/client/windows/connect.bat
        scripts/client/windows/connect-hide-relaunch.vbs
        scripts/client/windows/connect-hide-console.ps1
        scripts/client/windows/connect-version.txt
        scripts/client/windows/connect.ps1
        scripts/client/windows/connect-rider.bat
        scripts/client/windows/connect-update.ps1
        scripts/client/windows/cursor-proxy-sidecar.ps1
        scripts/client/windows/connect-boot.ps1
        scripts/client/windows/connect-heal.ps1
        scripts/client/windows/connect-bootstrap.ps1
        scripts/client/windows/connect-preflight.ps1
        scripts/client/connect-ui.ps1
        scripts/client/connect-diagnostic.ps1
        scripts/client/editor-launch.ps1
        scripts/client/git-mode.ps1
        scripts/client/cursor-auth-laptop.ps1
        scripts/client/windows/windows-mcp-laptop.ps1
        scripts/client/mac/connect.sh
        scripts/client/mac/connect-update.sh
        scripts/client/mac/cursor-proxy-sidecar.sh
        scripts/client/connect-ui.sh
        scripts/client/editor-launch.sh
        scripts/client/git-mode.sh
        scripts/server/claude-mount.sh
        scripts/server/claude-git-setup.sh
        scripts/server/laptop-exec.sh
        scripts/server/laptop-exec-setup.sh
        scripts/server/cursor-rules/laptop-exec.mdc
        scripts/server/skills/laptop-exec/SKILL.md
        scripts/server/cursor-hooks/laptop-exec-guard.sh
        scripts/server/cursor-hooks/hooks-user.json
        scripts/server/client-update-policy.json
    )
    for rel in "${paths[@]}"; do
        _pull "$rel" || warn "staging skip $rel"
    done
    [ -f "$stage/scripts/client/windows/connect.ps1" ] || return 1
    REPO_DIR="$stage"
    CLIENT_DIR="$REPO_DIR/scripts/client"
    ok "repo staged from laptop -> $stage"
    return 0
}


# On-server copies (/opt, SSHFS mounts) are often STALE vs laptop disk (source of truth).
# Only used when laptop-exec staging is unavailable.
_resolve_repo_fallback() {
    local d
    for d in \
        "${CLAUDE_SERVER_REPO:-}" \
        "/home/smart/mounts/claude-code-server" \
        "$REPO_DIR" \
        "/opt/claude-code-server"; do
        [ -n "$d" ] || continue
        # Never treat the staging dir as a "fallback" - that is laptop-sourced only.
        case "$d" in
            /var/tmp/claude-code-server-staging) continue ;;
        esac
        [ -f "$d/scripts/client/windows/connect.ps1" ] || continue
        [ -f "$d/scripts/client/windows/connect-version.txt" ] || continue
        REPO_DIR="$d"
        CLIENT_DIR="$REPO_DIR/scripts/client"
        return 0
    done
    return 1
}

# Prefer laptop staging ALWAYS when the tunnel is up. Falling back to /opt first was the
# bug that kept publishing ancient connect-version.txt / git-mode.ps1 while laptop had fixes.
BUNDLE_SOURCE_KIND=""
if _stage_repo_from_laptop; then
    BUNDLE_SOURCE_KIND="laptop"
elif _resolve_repo_fallback; then
    BUNDLE_SOURCE_KIND="server-fallback"
    warn "laptop staging unavailable - using on-server tree $REPO_DIR (may be STALE)"
else
    fail "client scripts not found (start connect on laptop so laptop-exec can stage, or set CLAUDE_SERVER_REPO)"
fi

BUNDLE_ROOT="/usr/local/share/claude-client"
WIN_SRC="$CLIENT_DIR/windows"
MAC_SRC="$CLIENT_DIR/mac"

[ -f "$WIN_SRC/connect-version.txt" ] || fail "missing $WIN_SRC/connect-version.txt"
[ -f "$WIN_SRC/connect.ps1" ] || fail "missing $WIN_SRC/connect.ps1"
[ -f "$MAC_SRC/connect.sh" ] || fail "missing $MAC_SRC/connect.sh"

_strip_crlf() {
    # Portable CR strip. NEVER use sed 's/\r$//' — on BusyBox/some sed builds
    # \r is a literal letter "r", which truncates identifiers ending in r
    # ($uidStr->$uidSt, Get-InteractiveLaptopUser->...Use). That shipped a
    # corrupted connect.ps1 in 20260727.03 and breaks update consumers.
    local f="$1"
    [ -f "$f" ] || return 0
    if command -v perl >/dev/null 2>&1; then
        perl -pi -e 's/\r$//' "$f"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
data = open(p, 'rb').read().replace(b'\r\n', b'\n').replace(b'\r', b'')
open(p, 'wb').write(data)
PY
        return 0
    fi
    # GNU sed with explicit CR byte (ANSI-C quoting). Still prefer perl/python3.
    local cr
    cr=$(printf '\r')
    sed -i "s/${cr}$//" "$f"
}

echo ""
echo -e "${BOLD}Deploy client bundle (laptop auto-update)${NC}"
echo -e "  ${BOLD}source${NC}  $CLIENT_DIR  (${BUNDLE_SOURCE_KIND:-unknown})"
echo -e "  ${BOLD}target${NC}  $BUNDLE_ROOT"
echo ""

# Stage into a temp dir, then rename-swap into live (never rm -rf live while clients download).
STAGE_BUNDLE="/var/tmp/claude-client-bundle-new.$$"
OLD_BUNDLE="/var/tmp/claude-client-bundle-old.$$"
rm -rf "$STAGE_BUNDLE" "$OLD_BUNDLE"
mkdir -p "$STAGE_BUNDLE/mac"
BUNDLE_LIVE="$BUNDLE_ROOT"
BUNDLE_ROOT="$STAGE_BUNDLE"

win_files=(
    connect.bat
    connect-hide-relaunch.vbs
    connect-hide-console.ps1
    connect-boot.ps1
    connect-heal.ps1
    connect-bootstrap.ps1
    connect-preflight.ps1
    connect-version.txt
    connect.ps1
    connect-rider.bat
    connect-update.ps1
    cursor-proxy-sidecar.ps1
    connect-ui.ps1
    connect-diagnostic.ps1
    editor-launch.ps1
    git-mode.ps1
    cursor-auth-laptop.ps1
    windows-mcp-laptop.ps1
    Claude-Connect.exe
)

for name in "${win_files[@]}"; do
    src=""
    case "$name" in
        # Flat Desktop\Claude-Connect layout has no scripts/client/ parent — ship CANON
        # bodies here. windows/*.ps1 shadows (STALE-SHADOW wrappers) are repo-dev only.
        connect-ui.ps1|connect-diagnostic.ps1|editor-launch.ps1|git-mode.ps1|cursor-auth-laptop.ps1)
            src="$CLIENT_DIR/$name"
            ;;
        *)
            src="$WIN_SRC/$name"
            ;;
    esac
    # Keep the already-published EXE when this deploy does not rebuild it
    # (scripts-only / laptop-exec stage). Never drop Claude-Connect.exe from the live share.
    if [ ! -f "$src" ] && [ "$name" = "Claude-Connect.exe" ] && [ -f "$BUNDLE_LIVE/Claude-Connect.exe" ]; then
        src="$BUNDLE_LIVE/Claude-Connect.exe"
        warn "reusing live Claude-Connect.exe (no new EXE in source)"
    fi
    if [ ! -f "$src" ]; then
        if [ "$name" = "Claude-Connect.exe" ]; then
            fail "Claude-Connect.exe missing from source and live bundle - refuse to publish a stub-less client share"
        fi
        warn "skip missing: $name"
        continue
    fi
    # Fail closed: never publish a repo-dev STALE-SHADOW wrapper into the flat client share.
    # That made Desktop\Claude-Connect\connect-diagnostic.ps1 look for Desktop\connect-diagnostic.ps1.
    case "$name" in
        connect-ui.ps1|connect-diagnostic.ps1)
            if grep -q 'STALE-SHADOW REPLACED' "$src" 2>/dev/null; then
                fail "$name source is a STALE-SHADOW wrapper ($src) - refuse to publish (use scripts/client/$name canon)"
            fi
            ;;
    esac
    install -m 644 "$src" "$BUNDLE_ROOT/$name"
    case "$name" in
        connect.bat|connect-rider.bat|connect-hide-relaunch.vbs) ;;  # Windows batch/VBS need CRLF
        Claude-Connect.exe) ;;  # binary SFX
        *) _strip_crlf "$BUNDLE_ROOT/$name" ;;
    esac
    ok "$name"
done

mac_files=(
    connect.sh
    connect-update.sh
    connect-version.txt
    cursor-proxy-sidecar.sh
    git-mode.sh
    connect-ui.sh
    editor-launch.sh
    claude-mount.sh
)

for name in "${mac_files[@]}"; do
    src=""
    case "$name" in
        git-mode.sh|connect-ui.sh|editor-launch.sh)
            src="$CLIENT_DIR/$name"
            ;;
        connect-version.txt)
            src="$WIN_SRC/connect-version.txt"
            ;;
        claude-mount.sh)
            src="$REPO_DIR/scripts/server/claude-mount.sh"
            ;;
        *)
            src="$MAC_SRC/$name"
            ;;
    esac
    if [ ! -f "$src" ]; then
        if [ "$name" = "connect-ui.sh" ] || [ "$name" = "editor-launch.sh" ] || [ "$name" = "git-mode.sh" ]; then
            fail "required mac file missing: $name (src=$src)"
        fi
        warn "skip missing mac/$name"
        continue
    fi
    install -m 644 "$src" "$BUNDLE_ROOT/mac/$name"
    _strip_crlf "$BUNDLE_ROOT/mac/$name"
    ok "mac/$name"
done

SERVER_DIR="$REPO_DIR/scripts/server"
if [ -d "$SERVER_DIR" ]; then
    mkdir -p "$BUNDLE_ROOT/server/cursor-rules" "$BUNDLE_ROOT/server/skills/laptop-exec" "$BUNDLE_ROOT/server/cursor-hooks"
    server_files=(
        laptop-exec.sh
        laptop-exec-setup.sh
        claude-mount.sh
        claude-git-setup.sh
        cursor-rules/laptop-exec.mdc
        skills/laptop-exec/SKILL.md
        cursor-hooks/laptop-exec-guard.sh
        cursor-hooks/hooks-user.json
    )
    for rel in "${server_files[@]}"; do
        src="$SERVER_DIR/$rel"
        if [ ! -f "$src" ]; then
            warn "skip missing server/$rel"
            continue
        fi
        install -m 644 "$src" "$BUNDLE_ROOT/server/$rel"
        _strip_crlf "$BUNDLE_ROOT/server/$rel"
        ok "server/$rel"
    done
    chmod 755 "$BUNDLE_ROOT/server/laptop-exec.sh" "$BUNDLE_ROOT/server/laptop-exec-setup.sh" \
        "$BUNDLE_ROOT/server/claude-mount.sh" "$BUNDLE_ROOT/server/claude-git-setup.sh" \
        "$BUNDLE_ROOT/server/cursor-hooks/laptop-exec-guard.sh" 2>/dev/null || true
fi

{
    for name in "${win_files[@]}"; do
        [ -f "$BUNDLE_ROOT/$name" ] && printf '%s\n' "$name"
    done
    for name in "${mac_files[@]}"; do
        [ -f "$BUNDLE_ROOT/mac/$name" ] && printf 'mac/%s\n' "$name"
    done
    if [ -d "$BUNDLE_ROOT/server" ]; then
        find "$BUNDLE_ROOT/server" -type f | sed "s|^$BUNDLE_ROOT/||" | sort
    fi
} > "$BUNDLE_ROOT/manifest.txt"
chmod 644 "$BUNDLE_ROOT/manifest.txt"
ok "manifest.txt ($(wc -l < "$BUNDLE_ROOT/manifest.txt") files)"



# SECURITY: do NOT merge developer authorized_keys into sepidz. That plus
# NOPASSWD install-client-bundle allowed any laptop key to root-install.
# Clients pull the bundle as their own REMOTE_USER (see connect-update.*).
# server/ scripts are not needed for laptop auto-update apply paths - drop
# them from the world-readable share (keep win/mac client files only).
if [ -d "$BUNDLE_ROOT/server" ]; then
    rm -rf "$BUNDLE_ROOT/server"
    # Rewrite manifest without server/* entries
    if [ -f "$BUNDLE_ROOT/manifest.txt" ]; then
        grep -v '^server/' "$BUNDLE_ROOT/manifest.txt" >"$BUNDLE_ROOT/manifest.txt.tmp" \
            || true
        mv "$BUNDLE_ROOT/manifest.txt.tmp" "$BUNDLE_ROOT/manifest.txt"
        chmod 644 "$BUNDLE_ROOT/manifest.txt"
    fi
    ok "removed server/ from world-readable client share"
fi
chmod 755 "$BUNDLE_ROOT" "$BUNDLE_ROOT/mac" 2>/dev/null || chmod 755 "$BUNDLE_ROOT"
# Tighten: dirs 755, files 644 (client scripts are not secrets; no server tree).
find "$BUNDLE_ROOT" -type d -exec chmod 755 {} \;
find "$BUNDLE_ROOT" -type f -exec chmod 644 {} \;
chmod 755 "$BUNDLE_ROOT"/mac/*.sh 2>/dev/null || true

# SHA-256 checksums for client post-scp verify (exclude checksums.txt itself).
if [[ -f "${REPO_DIR:-}/scripts/server/client-update-policy.json" ]]; then
  install -m 644 "$REPO_DIR/scripts/server/client-update-policy.json" "${BUNDLE_ROOT}/client-update-policy.json" || true
  ok "client-update-policy.json"
fi
(
    cd "$BUNDLE_ROOT" || exit 1
    if command -v sha256sum >/dev/null 2>&1; then
        find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 sha256sum | sed 's|  \./|  |'
    elif command -v shasum >/dev/null 2>&1; then
        find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 shasum -a 256 | sed 's|  \./|  |'
    else
        fail "need sha256sum or shasum to write checksums.txt"
    fi
) > "$BUNDLE_ROOT/checksums.txt"
chmod 644 "$BUNDLE_ROOT/checksums.txt"
ok "checksums.txt ($(wc -l < "$BUNDLE_ROOT/checksums.txt") files)"

# Hard ship-gates (2026-07-27): refuse to promote a staged bundle that would re-break
# Mehrdad/fleet (diagnostic stub, dead 18998 sticky, AV AppLaunched heuristic EXE).
_verify_staged_client_bundle() {
    local root="$1" f
    f="$root/connect-diagnostic.ps1"
    [ -f "$f" ] || fail "ship-gate: connect-diagnostic.ps1 missing from staged bundle"
    if grep -q 'STALE-SHADOW REPLACED' "$f" 2>/dev/null; then
        fail "ship-gate: staged connect-diagnostic.ps1 is STALE-SHADOW wrapper (flat Desktop would look for parent canon)"
    fi
    grep -q 'Get-ConnectProblemVerdict' "$f" || fail "ship-gate: connect-diagnostic.ps1 missing Get-ConnectProblemVerdict"
    [ "$(wc -c < "$f")" -ge 5000 ] || fail "ship-gate: connect-diagnostic.ps1 too small ($(wc -c < "$f") bytes) - likely stub"

    f="$root/connect-ui.ps1"
    [ -f "$f" ] || fail "ship-gate: connect-ui.ps1 missing"
    if grep -q 'STALE-SHADOW REPLACED' "$f" 2>/dev/null; then
        fail "ship-gate: staged connect-ui.ps1 is STALE-SHADOW wrapper"
    fi
    grep -q 'update_manual_relaunch\|Stop-Process -Id \$PID' "$f" \
        || fail "ship-gate: connect-ui.ps1 missing hard exit after manual update (Press Enter regression)"

    f="$root/cursor-proxy-sidecar.ps1"
    [ -f "$f" ] || fail "ship-gate: cursor-proxy-sidecar.ps1 missing"
    grep -q 'CURSOR_PROXY_CLEAR force reason=backend_down' "$f" \
        || fail "ship-gate: sidecar missing backend_down force-clear (18998 blackhole regression)"
    grep -q 'stopping_fronts' "$f" \
        || fail "ship-gate: sidecar missing stop-fronts-when-backend-down"

    f="$root/Claude-Connect.exe"
    if [ -f "$f" ]; then
        if grep -a -q 'ExecutionPolicy Bypass -WindowStyle Hidden' "$f" 2>/dev/null; then
            fail "ship-gate: Claude-Connect.exe embeds powershell Bypass+Hidden AppLaunched (AV heuristic)"
        fi
    fi

    f="$root/connect-version.txt"
    [ -f "$f" ] || fail "ship-gate: connect-version.txt missing"

    # Fail closed: trailing-"r" truncation (broken CRLF strip / BusyBox sed \r).
    f="$root/connect.ps1"
    [ -f "$f" ] || fail "ship-gate: connect.ps1 missing"
    if grep -qE 'Get-InteractiveLaptopUse([^r]|$)|\$uidSt([^r]|$)|\$launchDi([^r]|$)|\$ConnectScriptDi([^r]|$)|\$OnFolde([^r]|$)|\$RemoteUse([^r]|$)|\$sshCfgUse([^r]|$)' "$f" 2>/dev/null; then
        fail "ship-gate: connect.ps1 has truncated identifiers (trailing-r strip corruption)"
    fi
    grep -q 'Get-InteractiveLaptopUser' "$f" || fail "ship-gate: connect.ps1 missing Get-InteractiveLaptopUser"
    grep -q '\$uidStr' "$f" || fail "ship-gate: connect.ps1 missing \$uidStr"
    f="$root/connect-diagnostic.ps1"
    if grep -qE '\$OnFolde([^r]|$)' "$f" 2>/dev/null; then
        fail "ship-gate: connect-diagnostic.ps1 has truncated \$OnFolder"
    fi
    grep -q '\$OnFolder' "$f" || fail "ship-gate: connect-diagnostic.ps1 missing \$OnFolder"

    ok "ship-gates passed (diagnostic canon, proxy backend_down, update hard-exit, EXE heuristic, no-r-truncation)"
}
_verify_staged_client_bundle "$BUNDLE_ROOT"

# Rename-swap: move live aside, promote stage, drop old (clients see old or new, never empty tree mid-rm).
if [ -e "$BUNDLE_LIVE" ]; then
    mv "$BUNDLE_LIVE" "$OLD_BUNDLE" || fail "could not move live bundle aside"
fi
mv "$BUNDLE_ROOT" "$BUNDLE_LIVE" || {
    if [ -e "$OLD_BUNDLE" ]; then
        mv "$OLD_BUNDLE" "$BUNDLE_LIVE" 2>/dev/null || true
    fi
    fail "could not promote staged bundle to $BUNDLE_LIVE"
}
rm -rf "$OLD_BUNDLE"
BUNDLE_ROOT="$BUNDLE_LIVE"

# Re-check live share after swap (paranoia: catch partial promote).
_verify_staged_client_bundle "$BUNDLE_ROOT"

VER="$(tr -d '\r\n' < "$BUNDLE_ROOT/connect-version.txt")"
echo ""
echo -e "${GREEN}Done.${NC} Client bundle v${VER} at $BUNDLE_ROOT"
echo "  Laptops auto-update on connect.bat / mac/connect.sh launch."
echo ""



