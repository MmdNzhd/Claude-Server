$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$remote = @'
#!/bin/bash
set -e
PW=$(echo __PWB64__ | base64 -d)
sud(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo "=== FIND ALL CONNECT LOGS ==="
sud find /home -type f -path '*/.claude/logs/connect-*.log' 2>/dev/null | sort
echo
echo "=== LIST LOG DIRS ==="
for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak sepidz smart; do
  d=/home/$u/.claude/logs
  if sud test -d "$d"; then
    echo "-- $u --"
    sud ls -lah "$d"
  else
    echo "-- $u -- NO_DIR"
  fi
done
echo
echo "=== GREP ERRORS LAST FILES ==="
sud bash -c 'for f in $(find /home -type f -path "*/.claude/logs/connect-*.log" -mtime -10 2>/dev/null | sort); do
  u=$(echo "$f" | cut -d/ -f3)
  hits=$(grep -E "ERROR|WARN|FAIL|failed|UNHANDLED|timeout|denied|exception|auth" "$f" 2>/dev/null | tail -n 25)
  if [ -n "$hits" ]; then
    echo "#### $u :: $f ####"
    echo "$hits"
    echo
  fi
done'
echo
echo "=== TAIL TODAY/YDAY PER USER ==="
DAY=$(date +%Y%m%d)
YDAY=$(date -d yesterday +%Y%m%d)
for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak sepidz smart; do
  for d in "$DAY" "$YDAY"; do
    f=/home/$u/.claude/logs/connect-$d.log
    if sud test -f "$f"; then
      echo "#### $u connect-$d.log ####"
      sud tail -n 60 "$f"
      echo
    fi
  done
done
echo "=== WHO HAS ACTIVE SESSIONS / MOUNTS ==="
sud bash -c 'for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak; do
  echo -- $u --
  ls /home/$u/mounts 2>/dev/null || true
  mount | grep -E "/home/$u/mounts" || true
  ps -u $u -o pid,etime,cmd --no-headers 2>/dev/null | head -8 || true
done'
echo "=== AUTH LATEST DISTINCT MESSAGES ==="
sud bash -c 'grep PROBE_FAIL /var/log/claude-auth.log | tail -n 5'
sud bash -c 'python3 - <<"PY"
import json
from collections import Counter
msgs=Counter(); n=0
for line in open("/var/log/claude-auth.log"):
    if "PROBE_FAIL" not in line: continue
    n+=1
    try:
        o=json.loads(line)
    except Exception:
        continue
    bp=o.get("body_preview") or ""
    if "revoked" in bp: msgs["revoked"]+=1
    elif "Invalid authentication" in bp: msgs["invalid"]+=1
    else: msgs["other"]+=1
print("probe_fail_lines", n)
print(dict(msgs))
PY'
'@
$remote = $remote.Replace('__PWB64__', $pwB64)
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($remote -replace "`r",'')))
$out = Join-Path $env:TEMP 'sep-logs.out'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d > /tmp/rl.sh && bash /tmp/rl.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(180000)){ try{$p.Kill()}catch{}; throw 'TIMEOUT' }
Write-Host (Get-Content $out -Raw)
if(Test-Path ($out+'.err')){ $e=(Get-Content ($out+'.err') -Raw); if($e.Trim()){ Write-Host 'ERR:'; Write-Host $e } }
