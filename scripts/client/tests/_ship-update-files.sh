#!/bin/bash
# Copy key client files from laptop staging into live bundle + rebuild checksums.
set -euo pipefail
B=/usr/local/share/claude-client
STAGE=/var/tmp/cc-ship-$$
mkdir -p "$STAGE"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

pull() {
  local rel="$1" dest="$2"
  sudo -u smart laptop-exec read -p claude-code-server "$rel" > "$dest"
  test -s "$dest"
}

pull scripts/client/windows/connect-update.ps1 "$STAGE/connect-update.ps1"
pull scripts/client/windows/connect.ps1 "$STAGE/connect.ps1"
pull scripts/client/windows/connect-version.txt "$STAGE/connect-version.txt"
pull scripts/client/windows/connect-boot.ps1 "$STAGE/connect-boot.ps1"
pull scripts/client/mac/connect-version.txt "$STAGE/mac-connect-version.txt"
pull scripts/client/mac/connect.sh "$STAGE/mac-connect.sh"

install -m 644 "$STAGE/connect-update.ps1" "$B/connect-update.ps1"
install -m 644 "$STAGE/connect.ps1" "$B/connect.ps1"
install -m 644 "$STAGE/connect-version.txt" "$B/connect-version.txt"
install -m 644 "$STAGE/connect-boot.ps1" "$B/connect-boot.ps1"
install -m 644 "$STAGE/mac-connect-version.txt" "$B/mac/connect-version.txt"
install -m 644 "$STAGE/mac-connect.sh" "$B/mac/connect.sh"

# ensure preflight in manifest
if [ -f "$B/connect-preflight.ps1" ] && ! grep -qx 'connect-preflight.ps1' "$B/manifest.txt"; then
  echo 'connect-preflight.ps1' >> "$B/manifest.txt"
fi

# rebuild checksums from manifest
tmp="$(mktemp)"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$B/$f" ] || continue
  case "$f" in checksums.txt|manifest.txt) continue ;; esac
  (cd "$B" && sha256sum "$f")
done < "$B/manifest.txt" > "$tmp"
# if preflight on disk but not hashed, append
if [ -f "$B/connect-preflight.ps1" ] && ! grep -q ' connect-preflight.ps1$' "$tmp"; then
  (cd "$B" && sha256sum connect-preflight.ps1) >> "$tmp"
fi
install -m 644 "$tmp" "$B/checksums.txt"
rm -f "$tmp"

# sync policy latest
python3 - <<'PY'
import json
path="/usr/local/share/claude-client/client-update-policy.json"
ver=open("/usr/local/share/claude-client/connect-version.txt").read().strip()
obj=json.load(open(path))
obj["latest"]=ver
with open(path,"w") as f:
    json.dump(obj,f,indent=2)
    f.write("\n")
print("policy_latest", obj["latest"])
PY

echo "VER=$(cat $B/connect-version.txt)"
grep -c 'function Write-ConnectInstantLauncher' "$B/connect-update.ps1"
grep -c 'wscript.exe //B //Nologo' "$B/connect-update.ps1"
u=$(sha256sum "$B/connect-update.ps1" | awk '{print $1}')
g=$(awk '/ connect-update\.ps1$/{print $1}' "$B/checksums.txt")
test "$u" = "$g" && echo CHECKSUM_OK || { echo CHECKSUM_BAD; exit 1; }
grep -q 'connect-preflight.ps1' "$B/checksums.txt" && echo PREFLIGHT_HASHED || echo PREFLIGHT_NOT_HASHED
