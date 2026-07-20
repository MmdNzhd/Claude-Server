#!/bin/bash
# Correlate sshd with tunnel death window (local wall clock assumed ≈ laptop log TZ)
# Window: 2026-07-19 12:37:50 .. 12:38:20
echo "=== auth.log / journal around drop (smart reverse + local) ==="
for f in /var/log/auth.log /var/log/secure /var/log/auth.log.1; do
  if [[ -r "$f" ]]; then
    echo "-- $f --"
    grep -E '2026-07-19T12:3[78]|Jul 19 12:3[78]' "$f" 2>/dev/null | grep -E 'smart|21002|reverse|disconnected|Accepted|session closed|MaxStartups|refused' | tail -80
  fi
done
# journalctl without sudo may fail
journalctl -u ssh --since '2026-07-19 12:37:00' --until '2026-07-19 12:39:00' --no-pager 2>/dev/null | grep -E 'smart|21002|Disconnected|Accepted|MaxStartups' | tail -60 || true
journalctl --since '2026-07-19 12:37:00' --until '2026-07-19 12:39:00' --no-pager 2>/dev/null | grep -iE 'sshd.*(smart|disconnect|maxstartup|21002)' | tail -60 || true

echo "=== current reverse listeners ==="
ss -lntp 2>/dev/null | grep -E '2100[0-9]' || netstat -lnt | grep 2100

echo "=== last connect version markers in log ==="
grep -E 'v202607|connect.version|CLIENT_VERSION|bundle=|VERSION=' /home/smart/.claude/logs/connect-20260719.log 2>/dev/null | sort -u | head -20
grep -E 'session begin|========' /home/smart/.claude/logs/connect-20260719.log 2>/dev/null | head -5
# first 30 lines of session
python3 - <<'PY'
from pathlib import Path
import re
lines=Path('/home/smart/.claude/logs/connect-20260719.log').read_text(errors='replace').splitlines()
# unique first session headerish
seen=set(); n=0
for l in lines:
    if l in seen: continue
    seen.add(l)
    if '10aa2e24986b' in l:
        print(l[:200]); n+=1
        if n>=25: break
PY
