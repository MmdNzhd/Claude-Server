#!/bin/bash
set -u
echo "HOST=$(hostname) NOW=$(date '+%F %T')"
echo '=== users home ==='
ls /home
echo '=== farzadb logs dir ==='
ls -la /home/farzadb/.claude/logs/ 2>/dev/null | tail -30 || echo 'no farzadb logs dir'
echo '=== all connect logs last 3 days ==='
find /home -path '*/.claude/logs/connect-*.log' -mtime -3 2>/dev/null -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' | sort
echo '=== any .31 / .29 / .30 session anywhere today+yesterday ==='
grep -R --include='connect-2026071*.log' -l 'v20260719\.3[0-9]\|v20260719\.29\|PUSH_CONF ok\|PUSH_CONF begin\|SESSION_KEY ignore' /home/*/ 2>/dev/null | head -40
echo '=== counts of new markers across all today logs ==='
for f in /home/*/.claude/logs/connect-20260719.log; do
  [ -f "$f" ] || continue
  u=$(basename $(dirname $(dirname "$f")))
  echo "-- $u --"
  echo -n "session_start: "; grep -c 'session start' "$f" || true
  echo -n "v20260719.31: "; grep -c '20260719.31' "$f" || true
  echo -n "v20260719.29: "; grep -c '20260719.29' "$f" || true
  echo -n "v20260719.9: "; grep -c '20260719.9' "$f" || true
  echo -n "PUSH_CONF begin: "; grep -c 'PUSH_CONF begin' "$f" || true
  echo -n "PUSH_CONF ok: "; grep -c 'PUSH_CONF ok' "$f" || true
  echo -n "syntax error elif: "; grep -c 'syntax error near unexpected token.*elif' "$f" || true
  echo -n "SESSION_KEY ignore: "; grep -c 'SESSION_KEY ignore' "$f" || true
  echo -n "keychar=ض: "; grep -c 'keychar=ض' "$f" || true
done
echo '=== farzadb latest log file ==='
latest=$(ls -1t /home/farzadb/.claude/logs/connect-*.log 2>/dev/null | head -1 || true)
if [ -n "${latest:-}" ]; then
  echo "LATEST=$latest"
  ls -la "$latest"
  echo '--- last session starts ---'
  grep -E 'session start|CONNECT_VERSION|UPDATE |PUSH_CONF|SESSION_KEY|syntax error|user_quit|keychar' "$latest" | tail -60
  echo '--- tail ---'
  tail -25 "$latest"
else
  echo 'NO farzadb connect logs'
  ls -la /home/farzadb/.claude/ 2>/dev/null || true
fi
echo '=== other users with logs ==='
for u in /home/*; do
  bn=$(basename "$u")
  n=$(ls "$u/.claude/logs"/connect-*.log 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && echo "$bn: $n log files; newest=$(ls -1t "$u/.claude/logs"/connect-*.log 2>/dev/null | head -1)"
done
