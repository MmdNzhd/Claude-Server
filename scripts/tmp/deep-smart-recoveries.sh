#!/bin/bash
f=/home/smart/.claude/logs/connect-20260719.log
echo "=== ALL auto-reconnect windows (±15 lines context) ==="
grep -n 'TUNNEL: connection dropped\|TUNNEL_SYNC ok=0\|TUNNEL_DROP\|RECOVERY_BEGIN\|CLEAR_MOUNT project\|ENSURE_TUNNEL ok\|ORPHAN_TUNNEL\|Opening Cursor\|TUNNEL_SYNC soft_fail\|bg_alive\|TUNNEL_SYNC: bg_alive\|reason=tunnel_down\|reason=reattached\|TUNNEL_STOP' "$f" | head -200

echo
echo "=== recovery count and gaps after Opening Cursor ==="
# For each connection dropped, show previous 5 key lines
python3 - <<'PY'
import re
from pathlib import Path
lines = Path("/home/smart/.claude/logs/connect-20260719.log").read_text(errors="replace").splitlines()
keys = []
for i,l in enumerate(lines):
    if any(x in l for x in [
        "TUNNEL: connection dropped","TUNNEL_DROP","TUNNEL_SYNC ok=0","RECOVERY_BEGIN",
        "CLEAR_MOUNT project","ENSURE_TUNNEL ok","ORPHAN_TUNNEL","Opening Cursor",
        "TUNNEL_SYNC soft_fail","reason=tunnel_down","reason=reattached","TUNNEL_STOP",
        "bg_alive_forward_dead","SESSION: disconnect","session end","STEP end: Opening Cursor"
    ]):
        keys.append((i,l))

# print each dropped with 8 prior key events
for i,l in keys:
    if "connection dropped" in l or "TUNNEL_DROP" in l:
        print("\n#### EVENT", l[:140])
        # find prior keys
        prior = [k for k in keys if k[0] < i][-8:]
        for pi,pl in prior:
            print("  ", pl[:160])
        print("  >>", l[:160])
        after = [k for k in keys if k[0] > i][:6]
        for ai,al in after:
            print("  ", al[:160])
PY

echo
echo "=== other users logs via sudo ==="
# try passwordless first
if sudo -n true 2>/dev/null; then
  for u in farzadb aminb hosseinb zahrak nimaz; do
    f2=/home/$u/.claude/logs/connect-20260719.log
    echo "---- $u ----"
    if sudo -n test -f "$f2"; then
      sudo -n wc -l "$f2"
      sudo -n grep -cE 'connection dropped|CLEAR_MOUNT|RECOVERY_BEGIN|ORPHAN_TUNNEL|Opening Cursor|ENSURE_TUNNEL ok' "$f2" || true
      sudo -n grep -E 'connection dropped|CLEAR_MOUNT project|RECOVERY_BEGIN|ORPHAN_TUNNEL|Opening Cursor ok|ENSURE_TUNNEL ok|session end|SESSION: disconnect' "$f2" | tail -40
    else
      echo missing
      sudo -n ls /home/$u/.claude/logs/ 2>/dev/null | head || echo no dir
    fi
  done
else
  echo "no passwordless sudo"
fi
