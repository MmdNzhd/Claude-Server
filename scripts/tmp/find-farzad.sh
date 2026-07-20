#!/bin/bash
echo "HOST=$(hostname) NOW=$(date -Is)"
echo '=== home users ==='
ls /home
echo '=== any farz* / bahador* paths ==='
ls -ld /home/farz* /home/*farz* /home/*bahador* 2>/dev/null || true
getent passwd | grep -iE 'farz|bahador' || true
echo '=== ALL connect logs anywhere under /home (mtime/size) ==='
find /home -path '*/.claude/logs/connect-*.log' 2>/dev/null -printf '%TY-%Tm-%Td %TH:%TM %10s %u %p\n' | sort
echo '=== also /var/tmp /tmp buffers ==='
find /home /tmp /var/tmp -name 'connect-*.log' 2>/dev/null -printf '%TY-%Tm-%Td %TH:%TM %10s %p\n' | sort | tail -50
echo '=== search v20260719.24 across all logs ==='
grep -R --include='connect-*.log' -l '20260719\.24\|v20260719\.24' /home 2>/dev/null || echo 'no .24 in /home logs'
grep -R --include='connect-*.log' -n '20260719\.24\|session start v2026\|UPDATE ' /home 2>/dev/null | grep -iE 'farz|24|UPDATE|session start' | tail -80
echo '=== all session start versions today+yesterday ==='
grep -Rh --include='connect-2026071*.log' 'session start v' /home 2>/dev/null | sort | uniq -c | sort -rn
echo '=== all CONNECT_VERSION= unique ==='
grep -Rho --include='connect-*.log' 'CONNECT_VERSION=[0-9.]*' /home 2>/dev/null | sort | uniq -c | sort -rn
echo '=== all UPDATE lines ==='
grep -Rh --include='connect-20260719.log' 'UPDATE: ' /home 2>/dev/null | sort | uniq -c | sort -rn | head -40
echo '=== farzadb full tree shallow ==='
sudo -n ls -la /home/farzadb 2>/dev/null || ls -la /home/farzadb 2>/dev/null
sudo -n find /home/farzadb -maxdepth 3 \( -name '*.log' -o -name '.claude*' -o -name 'claude-connect*' \) 2>/dev/null | head -50
echo '=== smart log mentions of farzad / other users ==='
grep -iE 'farz|bahador|RemoteUser|REMOTE_USER=' /home/smart/.claude/logs/connect-20260719.log 2>/dev/null | grep -iE 'farz|bahador|REMOTE_USER=' | sort | uniq -c | sort -rn | head -30
echo '=== bundle history / update keys for farzad ==='
ls -la /usr/local/share/claude-client/connect-version.txt
# sepidz update keys file if any
find /usr/local/share/claude-client -name '*update*' 2>/dev/null | head
grep -i farz /usr/local/share/claude-client/* 2>/dev/null | head || true
