#!/bin/bash
# test-client-auto-update.sh - integration tests for laptop auto-update
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf "  ${GREEN}PASS${NC} %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  ${RED}FAIL${NC} %s\n" "$1"; }

TEST_BUNDLE="$REPO_ROOT/.test-client-bundle"
TEST_CLIENT="$REPO_ROOT/.test-client-local"

echo ""
echo "=== Client auto-update integration tests ==="
echo ""

rm -rf "$TEST_BUNDLE" "$TEST_CLIENT"
mkdir -p "$TEST_BUNDLE/mac" "$TEST_CLIENT/mac"

CLIENT_DIR="$REPO_ROOT/scripts/client"
WIN_SRC="$CLIENT_DIR/windows"

cp "$WIN_SRC/connect-version.txt" "$TEST_BUNDLE/connect-version.txt"
cp "$WIN_SRC/connect-version.txt" "$TEST_BUNDLE/mac/connect-version.txt"
for f in connect.bat connect.ps1 connect-update.ps1 connect-ui.ps1 connect-diagnostic.ps1 \
    editor-launch.ps1 git-mode.ps1 cursor-auth-laptop.ps1 connect-rider.bat; do
    src="$WIN_SRC/$f"; [ -f "$src" ] || src="$CLIENT_DIR/$f"
    [ -f "$src" ] && cp "$src" "$TEST_BUNDLE/$f"
done
for f in connect.sh connect-update.sh git-mode.sh connect-ui.sh editor-launch.sh; do
    src="$CLIENT_DIR/mac/$f"; [ -f "$src" ] || src="$CLIENT_DIR/$f"
    [ -f "$src" ] && cp "$src" "$TEST_BUNDLE/mac/$f"
done
cp "$REPO_ROOT/scripts/server/claude-mount.sh" "$TEST_BUNDLE/mac/claude-mount.sh"
find "$TEST_BUNDLE" -type f ! -name manifest.txt | sed "s|^$TEST_BUNDLE/||" | sort > "$TEST_BUNDLE/manifest.txt"

CURRENT_VER="$(tr -d '\r\n' < "$TEST_BUNDLE/connect-version.txt")"
pass "built test bundle v$CURRENT_VER ($(wc -l < "$TEST_BUNDLE/manifest.txt") files)"

PS1_VER="$(grep -oP "ConnectVersion = '\K[^']+" "$WIN_SRC/connect.ps1" | head -1)"
SH_VER="$(grep -oP "CONNECT_VERSION='\K[^']+" "$CLIENT_DIR/mac/connect.sh" | head -1)"
FILE_VER="$(tr -d '\r\n' < "$WIN_SRC/connect-version.txt")"
if [ "$PS1_VER" = "$FILE_VER" ] && [ "$SH_VER" = "$FILE_VER" ]; then
    pass "version sync: all match ($FILE_VER)"
else
    fail "version mismatch: txt=$FILE_VER ps1=$PS1_VER sh=$SH_VER"
fi

ver_gt() {
    python3 -c "r='$1'.split('.'); l='$2'.split('.'); rd,rb=int(r[0]),int(r[1]); ld,lb=int(l[0]),int(l[1]); import sys; sys.exit(0 if (rd>ld or (rd==ld and rb>lb)) else 1)"
}

if ver_gt "20260713.26" "20260713.25"; then pass "version compare: .26 > .25"; else fail ".26 > .25"; fi
if ! ver_gt "20260713.9" "20260713.10"; then pass "version compare: .9 not > .10"; else fail ".9 vs .10"; fi
if ! ver_gt "20260713.26" "20260713.26"; then pass "version compare: equal"; else fail "equal"; fi

for req in connect-version.txt connect-update.ps1 connect.ps1 connect.bat mac/connect.sh mac/connect-update.sh; do
    if grep -qxF "$req" "$TEST_BUNDLE/manifest.txt"; then pass "manifest has $req"; else fail "manifest missing $req"; fi
done

OLD_VER="20260701.1"
printf '%s\n' "$OLD_VER" > "$TEST_CLIENT/connect-version.txt"
if ver_gt "$CURRENT_VER" "$OLD_VER"; then
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        mkdir -p "$TEST_CLIENT/$(dirname "$rel")"
        cp -f "$TEST_BUNDLE/$rel" "$TEST_CLIENT/$rel"
    done < "$TEST_BUNDLE/manifest.txt"
    NEW_LOCAL="$(tr -d '\r\n' < "$TEST_CLIENT/connect-version.txt")"
    [ "$NEW_LOCAL" = "$CURRENT_VER" ] && pass "simulated update $OLD_VER -> $NEW_LOCAL" || fail "update got $NEW_LOCAL"
else
    fail "should detect newer remote"
fi

grep -q 'connect-update.ps1' "$WIN_SRC/connect.bat" && pass "connect.bat hook" || fail "connect.bat hook"
grep -q 'connect-update.sh' "$CLIENT_DIR/mac/connect.sh" && pass "connect.sh hook" || fail "connect.sh hook"

for f in deploy-client-bundle.sh connect-update.sh connect.sh; do
    bash -n "$REPO_ROOT/scripts/server/commands/$f" 2>/dev/null || bash -n "$CLIENT_DIR/mac/$f" 2>/dev/null
    pass "bash -n $f"
done

rm -rf "$TEST_BUNDLE" "$TEST_CLIENT"
echo ""
[ "$FAIL" -eq 0 ] && printf "${GREEN}All %d tests passed.${NC}\n\n" "$PASS" && exit 0
printf "${RED}%d failed, %d passed.${NC}\n\n" "$FAIL" "$PASS" && exit 1
