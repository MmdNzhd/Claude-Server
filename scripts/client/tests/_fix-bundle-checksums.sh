#!/bin/bash
set -euo pipefail
B=/usr/local/share/claude-client
cd "$B"
tmp="$(mktemp)"
if [ -f manifest.txt ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$f" in checksums.txt|manifest.txt) continue ;; esac
    sha256sum "$f"
  done < manifest.txt > "$tmp"
else
  find . -type f ! -name checksums.txt ! -name manifest.txt | sed 's|^\./||' | sort | while read -r f; do
    sha256sum "$f"
  done > "$tmp"
fi
install -m 644 "$tmp" checksums.txt
rm -f "$tmp"
echo "VER=$(cat connect-version.txt)"
echo "CHECKSUM_LINES=$(wc -l < checksums.txt)"
grep 'connect-update.ps1$' checksums.txt || true
grep 'connect-version.txt$' checksums.txt || true
# verify one hash matches
u=$(sha256sum connect-update.ps1 | awk '{print $1}')
g=$(awk '/connect-update\.ps1$/{print $1}' checksums.txt)
if [ "$u" = "$g" ]; then echo CHECKSUM_OK; else echo CHECKSUM_MISMATCH; exit 1; fi
