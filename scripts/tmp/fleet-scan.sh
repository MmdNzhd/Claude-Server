#!/bin/bash
PW='sepidz@Admin'
for u in aminb farzadb hosseinb smart zahrak; do
  echo "==== USER=$u ===="
  echo "$PW" | sudo -S -p '' bash -lc "
f=/home/$u/.claude/logs/connect-20260719.log
if [ ! -f \"\$f\" ]; then echo NO_LOG; exit 0; fi
echo SIZE=\$(stat -c%s \"\$f\")
echo VER_STARTS=\$(grep -c 'session start v' \"\$f\" || true)
echo SYNTAX=\$(grep -c 'syntax error near unexpected token' \"\$f\" || true)
echo CLEAR=\$(grep -c 'CLEAR_MOUNT project=' \"\$f\" || true)
echo QUIT_Q=\$(grep -c 'session_key=action=q' \"\$f\" || true)
echo KEYCHAR_Q=\$(grep -c 'keychar=q' \"\$f\" || true)
echo DAD=\$(grep -c 'keychar=' \"\$f\" | head -1; grep 'keychar=' \"\$f\" | sed -n 's/.*keychar=\\(.\\).*/\\1/p' | sort | uniq -c | sort -rn | head -8)
echo UPDATE26=\$(grep -c '20260719.26' \"\$f\" || true)
echo UPDATE24=\$(grep -c '20260719.24' \"\$f\" || true)
echo UPDATE21=\$(grep -c '20260719.21' \"\$f\" || true)
echo AM_MIS=\$(grep -c 'ACTIVE_MOUNT server_conf=' \"\$f\" || true)
echo SOFT=\$(grep -c soft_fail \"\$f\" || true)
echo RECSKIP=\$(grep -c RECOVERY_SKIP_CLEAR_MOUNT \"\$f\" || true)
echo MENUWARN=\$(grep -c 'Enter a number or a/e/d/c/g/q' \"\$f\" || true)
echo LAST=\$(tail -n 1 \"\$f\" | cut -c1-180)
"
done
