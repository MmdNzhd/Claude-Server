#!/bin/bash
day=$(date +%Y%m%d)
echo "DAY=$day HOST=$(hostname)"
echo '=== log inventory ==='
ls -la /home/*/.claude/logs/connect-"$day".log 2>/dev/null || true
find /home -maxdepth 3 -path '*/.claude/logs/connect-*.log' -mtime -1 2>/dev/null | sort

echo '=== per-user key lines ==='
for f in /home/*/.claude/logs/connect-"$day".log; do
  [ -f "$f" ] || continue
  u=$(echo "$f" | cut -d/ -f3)
  sz=$(wc -c < "$f" | tr -d ' ')
  lines=$(wc -l < "$f" | tr -d ' ')
  echo "===== $u size=$sz lines=$lines ====="
  grep -E 'session start|ConnectVersion|CONNECT_VERSION|v2026|UPDATE |PUSH_CONF|SESSION_KEY|CLEAR_MOUNT|elif|syntax error|user_quit|fallthrough|ORPHAN|soft_fail|applied_ok|need_relaunch|ACTIVE_MOUNT|PUSH_CONF_RESULT' "$f" 2>/dev/null | tail -100
  echo
done

echo '=== farzad last 40 lines ==='
ff=/home/farzadb/.claude/logs/connect-"$day".log
if [ -f "$ff" ]; then
  tail -40 "$ff"
else
  # try alternate usernames
  for alt in farzad f.bahadorifar bahadorifar; do
    af=/home/$alt/.claude/logs/connect-"$day".log
    if [ -f "$af" ]; then echo "FOUND $af"; tail -40 "$af"; fi
  done
  ls /home | grep -i farz || true
fi
