#!/bin/bash
# install-client-bundle.sh - install publish-built bundle for laptop auto-update
# Usage: sudo claude-server install-client-bundle /path/to/bundle.zip
# Installs to /usr/local/share/claude-client/ (world-readable, no secrets).

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
    fail "run as root: sudo claude-server install-client-bundle <bundle.zip>"
fi

# Honor server freeze marker (Sepidz: /usr/local/share/claude-client.FROZEN).
# Smart has no marker => deploy continues. Override: FORCE_UNFREEZE=1
if [ -f /usr/local/share/claude-client.FROZEN ] && [ "${FORCE_UNFREEZE:-0}" != "1" ]; then
    fail "client bundle FROZEN (/usr/local/share/claude-client.FROZEN). Set FORCE_UNFREEZE=1 to override."
fi

ZIP="${1:-}"
[ -n "$ZIP" ] || fail "usage: sudo claude-server install-client-bundle <bundle.zip>"
[ -f "$ZIP" ] || fail "bundle not found: $ZIP"

BUNDLE_ROOT="/usr/local/share/claude-client"
STAGE="/var/tmp/claude-client-bundle-staging.$$"

cleanup() {
    if [ -d "$STAGE" ]; then
        rm -rf "$STAGE"
    fi
}
trap cleanup EXIT

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's/\r$//' "$f"
}

_extract_zip() {
    local zip="$1" dest="$2"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$zip" -d "$dest"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$zip" "$dest" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
        return 0
    fi
    fail "need unzip or python3 to extract bundle.zip"
}

echo ""
echo -e "${BOLD}Install client bundle from ZIP${NC}"
echo -e "  ${BOLD}source${NC}  $ZIP"
echo -e "  ${BOLD}target${NC}  $BUNDLE_ROOT"
echo ""

rm -rf "$STAGE"
mkdir -p "$STAGE"
_extract_zip "$ZIP" "$STAGE"

[ -f "$STAGE/connect.ps1" ] || fail "bundle missing connect.ps1"
[ -f "$STAGE/connect-boot.ps1" ] || fail "bundle missing connect-boot.ps1"
[ -f "$STAGE/connect-version.txt" ] || fail "bundle missing connect-version.txt"
[ -f "$STAGE/mac/connect.sh" ] || fail "bundle missing mac/connect.sh"

for mount_script in "$STAGE/mac/claude-mount.sh" "$STAGE/server/claude-mount.sh"; do
    if [ -f "$mount_script" ]; then
        if ! bash -n "$mount_script" 2>/dev/null; then
            fail "syntax error in $(basename "$mount_script") (bash -n failed)"
        fi
        ok "bash -n $(basename "$mount_script")"
    fi
done

while IFS= read -r -d '' f; do
    case "$f" in
        *.bat) ;;  # Windows batch needs CRLF
        *.exe|*.EXE) ;;  # binary SFX / PE - never sed CRLF
        *) _strip_crlf "$f" ;;
    esac
done < <(find "$STAGE" -type f -print0)

# Fail install if Claude-Connect.exe present but not valid PE.
if [ -f "$STAGE/Claude-Connect.exe" ]; then
  if ! python3 - "$STAGE/Claude-Connect.exe" <<"ENDPE"
import struct, sys
f=open(sys.argv[1], "rb")
assert f.read(2)==b"MZ"
f.seek(0x3C)
o=struct.unpack("<I", f.read(4))[0]
f.seek(o)
assert f.read(4)==b"PE"+bytes(2)
ENDPE
  then
    fail "Claude-Connect.exe is corrupt (not a valid PE) - refusing install"
  fi
  ok "Claude-Connect.exe PE header valid"
fi

# Rename-swap: never rm -rf live while clients may be downloading.
OLD_BUNDLE="/var/tmp/claude-client-bundle-old.$$"
rm -rf "$OLD_BUNDLE"
if [ -e "$BUNDLE_ROOT" ]; then
    mv "$BUNDLE_ROOT" "$OLD_BUNDLE" || fail "could not move live bundle aside"
fi
mv "$STAGE" "$BUNDLE_ROOT" || {
    if [ -e "$OLD_BUNDLE" ]; then
        mv "$OLD_BUNDLE" "$BUNDLE_ROOT" 2>/dev/null || true
    fi
    fail "could not promote staged bundle"
}
rm -rf "$OLD_BUNDLE"
trap - EXIT

chmod 755 "$BUNDLE_ROOT" "$BUNDLE_ROOT/mac" 2>/dev/null || chmod 755 "$BUNDLE_ROOT"
if [ -d "$BUNDLE_ROOT/server" ]; then
    chmod 755 "$BUNDLE_ROOT/server" \
        "$BUNDLE_ROOT/server/cursor-rules" \
        "$BUNDLE_ROOT/server/skills" \
        "$BUNDLE_ROOT/server/skills/laptop-exec" \
        "$BUNDLE_ROOT/server/cursor-hooks" 2>/dev/null || true
    chmod 755 "$BUNDLE_ROOT/server/laptop-exec.sh" \
        "$BUNDLE_ROOT/server/laptop-exec-setup.sh" \
        "$BUNDLE_ROOT/server/claude-mount.sh" \
        "$BUNDLE_ROOT/server/claude-git-setup.sh" \
        "$BUNDLE_ROOT/server/cursor-hooks/laptop-exec-guard.sh" 2>/dev/null || true
fi

find "$BUNDLE_ROOT" -type f -exec chmod 644 {} \;
find "$BUNDLE_ROOT" -type d -exec chmod 755 {} \;
chmod 755 "$BUNDLE_ROOT/server/laptop-exec.sh" \
    "$BUNDLE_ROOT/server/laptop-exec-setup.sh" \
    "$BUNDLE_ROOT/server/claude-mount.sh" \
    "$BUNDLE_ROOT/server/claude-git-setup.sh" \
    "$BUNDLE_ROOT/server/cursor-hooks/laptop-exec-guard.sh" 2>/dev/null || true

if [ ! -f "$BUNDLE_ROOT/manifest.txt" ]; then
    {
        find "$BUNDLE_ROOT" -maxdepth 1 -type f ! -name 'manifest.txt' -printf '%f\n' | sort
        if [ -d "$BUNDLE_ROOT/mac" ]; then
            find "$BUNDLE_ROOT/mac" -type f | sed "s|^$BUNDLE_ROOT/||" | sort
        fi
        if [ -d "$BUNDLE_ROOT/server" ]; then
            find "$BUNDLE_ROOT/server" -type f | sed "s|^$BUNDLE_ROOT/||" | sort
        fi
    } > "$BUNDLE_ROOT/manifest.txt"
    chmod 644 "$BUNDLE_ROOT/manifest.txt"
fi

if [ ! -f "$BUNDLE_ROOT/checksums.txt" ]; then
    (
        cd "$BUNDLE_ROOT" || exit 1
        if command -v sha256sum >/dev/null 2>&1; then
            find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 sha256sum | sed 's|  \./|  |'
        elif command -v shasum >/dev/null 2>&1; then
            find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 shasum -a 256 | sed 's|  \./|  |'
        fi
    ) > "$BUNDLE_ROOT/checksums.txt" 2>/dev/null || true
    [ -s "$BUNDLE_ROOT/checksums.txt" ] && chmod 644 "$BUNDLE_ROOT/checksums.txt" && ok "checksums.txt" || rm -f "$BUNDLE_ROOT/checksums.txt"
fi

VER="$(tr -d '\r\n' < "$BUNDLE_ROOT/connect-version.txt")"

# Merge /home/*/authorized_keys into sepidz so old Windows packages that
# SECURITY: do NOT merge developer keys into sepidz (see deploy-client-bundle.sh).
# Drop server/ from the world-readable share — clients skip server/* on apply.
if [ -d "$BUNDLE_ROOT/server" ]; then
    rm -rf "$BUNDLE_ROOT/server"
    if [ -f "$BUNDLE_ROOT/manifest.txt" ]; then
        grep -v '^server/' "$BUNDLE_ROOT/manifest.txt" >"$BUNDLE_ROOT/manifest.txt.tmp" || true
        mv "$BUNDLE_ROOT/manifest.txt.tmp" "$BUNDLE_ROOT/manifest.txt"
        chmod 644 "$BUNDLE_ROOT/manifest.txt"
    fi
    ok "removed server/ from world-readable client share"
    # Refresh checksums after dropping server/
    (
        cd "$BUNDLE_ROOT" || exit 1
        if command -v sha256sum >/dev/null 2>&1; then
            find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 sha256sum | sed 's|  \./|  |'
        elif command -v shasum >/dev/null 2>&1; then
            find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 shasum -a 256 | sed 's|  \./|  |'
        fi
    ) > "$BUNDLE_ROOT/checksums.txt" 2>/dev/null || true
    [ -s "$BUNDLE_ROOT/checksums.txt" ] && chmod 644 "$BUNDLE_ROOT/checksums.txt" || rm -f "$BUNDLE_ROOT/checksums.txt"
fi

echo ""
echo -e "${GREEN}Done.${NC} Client bundle v${VER} at $BUNDLE_ROOT"
echo "  Laptops auto-update on connect.bat / mac/connect.sh launch."
echo ""

