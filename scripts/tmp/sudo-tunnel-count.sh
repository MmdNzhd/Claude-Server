#!/bin/bash
read -r PW
export SUDO_ASKPASS=/bin/false
echo "$PW" | sudo -S -p "" bash -lc '
for u in farzadb smart alit aminb hosseinb hosseinm nimaz zahrak; do
  for d in 20260719 20260718 20260717; do
    f=/home/$u/.claude/logs/connect-$d.log
    if [ -f "$f" ]; then
      echo "FILE|$u|$d|$(wc -c < "$f")|$(wc -l < "$f")"
      echo -n "CNT|$u|$d|start="; grep -c "session start" "$f" || true
      echo -n "CNT|$u|$d|end="; grep -c "session end" "$f" || true
      echo -n "CNT|$u|$d|DROP="; grep -c "TUNNEL_DROP" "$f" || true
      echo -n "CNT|$u|$d|soft="; grep -c "TUNNEL_SYNC soft_fail" "$f" || true
      echo -n "CNT|$u|$d|SYNC="; grep -c "TUNNEL_SYNC" "$f" || true
      echo -n "CNT|$u|$d|ENSURE="; grep -c "ENSURE_TUNNEL" "$f" || true
      echo -n "CNT|$u|$d|ORPHAN="; grep -c "ORPHAN_TUNNEL" "$f" || true
      echo -n "CNT|$u|$d|RECOV="; grep -cE "RECOVERY_BEGIN|fallthrough_recover" "$f" || true
      echo -n "CNT|$u|$d|tdown="; grep -cE "tunnel_down|alreadyDown" "$f" || true
      echo -n "CNT|$u|$d|quit="; grep -c "user_quit" "$f" || true
    fi
  done
done
'