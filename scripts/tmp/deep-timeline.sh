#!/bin/bash
set -euo pipefail
DAY=20260719
USERS="farzadb aminb hosseinb zahrak smart nimaz"
for u in $USERS; do
  f="/home/$u/.claude/logs/connect-$DAY.log"
  echo "========== $u =========="
  if [[ ! -r "$f" ]]; then
    echo "NO_LOG readable=$(test -r "$f" && echo y || echo n) exists=$(test -e "$f" && echo y || echo n)"
    # try via ls
    ls -la "/home/$u/.claude/logs/" 2>/dev/null | head -8 || echo "no dir"
    continue
  fi
  echo "size=$(wc -c < "$f") lines=$(wc -l < "$f")"
  echo "--- event counts ---"
  grep -cE 'TUNNEL_DROP|CLEAR_MOUNT|connection dropped|RECOVERY_BEGIN|ORPHAN_TUNNEL|ENSURE_TUNNEL ok|Opening Cursor|session end|TUNNEL_SYNC ok=0|bg_alive_forward_dead|MaxStartups|STALE_FORWARD|TUNNEL_STOP|SESSION: disconnect' "$f" 2>/dev/null || true
  for pat in 'TUNNEL_DROP' 'CLEAR_MOUNT' 'connection dropped' 'RECOVERY_BEGIN' 'ORPHAN_TUNNEL' 'ENSURE_TUNNEL ok' 'Opening Cursor' 'session end' 'bg_alive_forward_dead' 'MaxStartups' 'TUNNEL_STOP' 'SESSION: disconnect' 'TUNNEL: recovering'; do
    c=$(grep -cF "$pat" "$f" 2>/dev/null || echo 0)
    echo "  $c  $pat"
  done
  echo "--- chronological key events (last 80) ---"
  grep -E 'TUNNEL_DROP|CLEAR_MOUNT|connection dropped|RECOVERY_BEGIN|ORPHAN_TUNNEL|ENSURE_TUNNEL ok=|Opening Cursor|session end|bg_alive_forward_dead|TUNNEL_STOP|SESSION: disconnect|TUNNEL: recovering|RECOVERY_END|cursor|Mounting|MOUNT_UP|EIO|Connection refused' "$f" 2>/dev/null | tail -80
  echo
done
