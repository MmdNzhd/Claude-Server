#!/bin/bash
set -eu
fail=0
ok() { echo "OK  $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }

echo "=== Sepidz mount verification ==="

bash -n /usr/local/lib/claude-mount && ok "lib claude-mount syntax" || bad "lib claude-mount syntax"
bash -n /usr/local/share/claude-client/server/claude-mount.sh && ok "bundle claude-mount syntax" || bad "bundle claude-mount syntax"

ver=$(tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt 2>/dev/null || true)
[ -n "$ver" ] && ok "bundle version v$ver" || bad "bundle version"

grep -q '192.168.250.70' /usr/local/share/claude-client/connect.ps1 && ok "bundle IP" || bad "bundle IP"
grep -q '_load_active_mount' /usr/local/bin/claude-watchdog && ok "watchdog guard" || bad "watchdog guard"

echo ""
for home in /home/*/; do
  u=$(basename "$home")
  [ "$u" = "lost+found" ] && continue
  m="$home/.local/bin/claude-mount"
  if [ ! -x "$m" ]; then bad "$u mount missing"; continue; fi
  if bash -n "$m" 2>/dev/null; then
    if cmp -s "$m" /usr/local/lib/claude-mount; then ok "$u syntax + matches lib"; else ok "$u syntax" ; bad "$u differs from lib"; fi
  else
    bad "$u syntax"
  fi
done

echo ""
if sudo -u farzadb /home/farzadb/.local/bin/claude-mount list >/tmp/farzadb-list.out 2>/tmp/farzadb-list.err; then
  ok "farzadb claude-mount list exit 0"
else
  rc=$?
  err=$(head -1 /tmp/farzadb-list.err 2>/dev/null || true)
  if echo "$err" | grep -qi 'syntax error'; then bad "farzadb list" "$err"; else ok "farzadb list exit $rc (no syntax error)"; fi
fi

echo ""
if [ "$fail" -eq 0 ]; then echo "RESULT: ALL CHECKS PASSED"; exit 0; fi
echo "RESULT: $fail CHECK(S) FAILED"; exit 1
