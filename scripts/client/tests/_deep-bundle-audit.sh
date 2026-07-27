#!/bin/bash
# Deep audit of /usr/local/share/claude-client — run as root.
set -euo pipefail
B=/usr/local/share/claude-client
cd "$B"
fail=0
pass=0
note() { echo "  $*"; }
ok() { echo "PASS  $*"; pass=$((pass+1)); }
bad() { echo "FAIL  $*"; fail=$((fail+1)); }

echo "=== BUNDLE DEEP AUDIT ==="
echo "time=$(date -Iseconds)"
echo "path=$B"

VER=$(tr -d '\r\n' < connect-version.txt)
note "connect-version.txt=$VER"
[[ "$VER" =~ ^[0-9]{8}\.[0-9]+$ ]] && ok "version format" || bad "version format ($VER)"

PS1V=$(grep -oP "ConnectVersion = '\K[^']+" connect.ps1 | head -1 || true)
note "connect.ps1 ConnectVersion=$PS1V"
[[ "$PS1V" == "$VER" ]] && ok "ps1 version matches" || bad "ps1 version mismatch ps1=$PS1V ver=$VER"

MACV=$(tr -d '\r\n' < mac/connect-version.txt)
SHV=$(grep -oP "CONNECT_VERSION='\K[^']+" mac/connect.sh | head -1 || true)
note "mac version.txt=$MACV connect.sh=$SHV"
[[ "$MACV" == "$VER" && "$SHV" == "$VER" ]] && ok "mac versions match" || bad "mac version mismatch"

# required files
for f in connect.bat connect.ps1 connect-boot.ps1 connect-update.ps1 connect-preflight.ps1 \
         connect-ui.ps1 connect-heal.ps1 connect-bootstrap.ps1 git-mode.ps1 editor-launch.ps1 \
         cursor-proxy-sidecar.ps1 windows-mcp-laptop.ps1 Claude-Connect.exe \
         checksums.txt manifest.txt client-update-policy.json; do
  if [ -f "$f" ]; then ok "present $f"; else bad "missing $f"; fi
done

# fix markers
grep -q 'versioned_apply_from_flat' connect-update.ps1 && ok "marker versioned_apply_from_flat" || bad "missing versioned_apply_from_flat"
grep -q 'flat_hybrid_swept' connect-update.ps1 && ok "marker flat_hybrid_swept" || bad "missing flat_hybrid_swept"
grep -q 'flat_migrated_at_boot' connect-boot.ps1 && ok "marker flat_migrated_at_boot" || bad "missing flat_migrated_at_boot"
grep -q 'foreign_verdir' connect-update.ps1 && ok "marker foreign_verdir" || bad "missing foreign_verdir"
# .23 leaf-name skip (not only isVerDir)
grep -q 'dirLeaf' connect-update.ps1 && ok "marker dirLeaf foreign skip" || bad "missing dirLeaf foreign skip"

# checksums: every listed file matches; every required file listed
echo "--- checksum verify ---"
while read -r hash path; do
  [ -z "${hash:-}" ] && continue
  if [ ! -f "$path" ]; then bad "checksum lists missing file: $path"; continue; fi
  actual=$(sha256sum "$path" | awk '{print $1}')
  if [ "$actual" = "$hash" ]; then ok "hash $path"; else bad "hash MISMATCH $path"; fi
done < checksums.txt

# reverse: critical files must appear in checksums
for f in connect.ps1 connect-update.ps1 connect-boot.ps1 connect-preflight.ps1 connect-version.txt \
         mac/connect.sh mac/connect-version.txt; do
  if grep -q " ${f}$" checksums.txt || grep -q " ${f}\r$" checksums.txt; then
    ok "checksums lists $f"
  else
    bad "checksums missing $f"
  fi
done

# manifest vs files
echo "--- manifest ---"
MAN_N=$(grep -c . manifest.txt || true)
note "manifest_lines=$MAN_N"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] && ok "manifest ok $f" || bad "manifest missing on disk: $f"
done < manifest.txt

# policy
if [ -f client-update-policy.json ]; then
  note "policy=$(tr -d '\n' < client-update-policy.json | head -c 200)"
  ok "policy present"
fi

# staging leftovers
if [ -e /var/tmp/claude-code-server-staging ]; then bad "staging leftover present"; else ok "no staging leftover"; fi

echo "=== RESULT pass=$pass fail=$fail ==="
[ "$fail" -eq 0 ]
