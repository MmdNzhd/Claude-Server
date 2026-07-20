#!/bin/bash
echo '=== farzadb home claude ==='
ls -la /home/farzadb/.claude 2>/dev/null || echo 'no .claude'
ls -la /home/farzadb/.claude/logs 2>/dev/null || echo 'no logs dir'
# maybe root-owned empty?
find /home/farzadb -name 'connect-*.log' 2>/dev/null | head
echo '=== smart UPDATE lines / versions timeline ==='
grep -E 'UPDATE |session start|up_to_date|CONNECT_VERSION=' /home/smart/.claude/logs/connect-20260719.log | sed -n '1,20p'
echo '...'
grep -E 'UPDATE |session start|up_to_date|CONNECT_VERSION=' /home/smart/.claude/logs/connect-20260719.log | tail -30
echo '=== bundle vs what clients saw ==='
echo -n 'bundle: '; cat /usr/local/share/claude-client/connect-version.txt; echo
echo '=== last log mtime vs server time ==='
stat -c '%y %n' /home/smart/.claude/logs/connect-20260719.log
date
echo '=== other users .claude/logs existence ==='
for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak; do
  if [ -d /home/$u/.claude/logs ]; then
    echo "$u logs:"; ls -la /home/$u/.claude/logs | tail -5
  else
    echo "$u: no logs dir"
  fi
done
