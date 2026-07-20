$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]

$bash = @'
#!/bin/bash
set +e
U=hosseinm
GS=/home/$U/.config/Cursor/User/globalStorage
echo "=== golden ==="
ls -la /etc/cursor-auth/golden/ 2>/dev/null
echo "exported_at=$(cat /etc/cursor-auth/golden/exported-at 2>/dev/null)"
echo "golden_mid=$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)"
echo "=== user cursor files ==="
ls -la /home/$U/.config/Cursor/ 2>/dev/null | head -30
ls -la "$GS" 2>/dev/null
echo "=== state.vscdb auth keys ==="
python3 <<PY
import sqlite3, os, json, time, base64, datetime
p="/home/hosseinm/.config/Cursor/User/globalStorage/state.vscdb"
print("size", os.path.getsize(p) if os.path.exists(p) else None)
if not os.path.exists(p):
  raise SystemExit
c=sqlite3.connect(f"file:{p}?mode=ro", uri=True)
cur=c.cursor()
tables=[r[0] for r in cur.execute("select name from sqlite_master where type='table'")]
print("tables", tables)
for t in tables:
  cols=[r[1] for r in cur.execute(f"pragma table_info({t})")]
  if "key" in cols and "value" in cols:
    rows=list(cur.execute(f"select key, length(value) from {t} where key like '%cursorAuth%' or key like '%email%' or key like '%shouldLogout%' or key like '%membership%' or key like '%subscription%'"))
    print("authish", rows)
    for k,v in cur.execute(f"select key, value from {t} where key like '%cursorAuth/accessToken%' or key like '%cursorAuth/refreshToken%' or key like '%cursorAuth/cachedEmail%' or key like '%cursorAuth/cachedSignUpType%'"):
      if isinstance(v, bytes):
        try: v=v.decode("utf-8","replace")
        except: v=repr(v)[:80]
      if "Token" in k:
        print(k, "len", len(v) if v else 0, "prefix", (v[:20]+"...") if v and len(v)>20 else v)
        # jwt exp
        if v and v.count(".")==2:
          try:
            payload=v.split(".")[1]; pad="="*(-len(payload)%4)
            data=json.loads(base64.urlsafe_b64decode(payload+pad))
            exp=data.get("exp")
            if exp:
              print("  exp", datetime.datetime.utcfromtimestamp(exp).isoformat()+"Z", "expired", exp<time.time())
          except Exception as e:
            print("  jwt_err", e)
      else:
        print(k, "=", (v[:120] if isinstance(v,str) and len(v)>120 else v))
c.close()
PY
echo "=== machineid paths ==="
find /home/$U/.config/Cursor -name 'machineid' 2>/dev/null
find /home/$U/.cursor-server -name 'machineid' 2>/dev/null | head -5
echo "=== cursor-server logs recent errors ==="
LOGDIR=$(ls -td /home/$U/.cursor-server/data/logs/* 2>/dev/null | head -1)
echo "LOGDIR=$LOGDIR"
if [ -n "$LOGDIR" ]; then
  find "$LOGDIR" -type f -name '*.log' -printf '%T+ %p %s\n' 2>/dev/null | sort -r | head -15
  echo "--- grepped errors ---"
  grep -RIhE 'error|Error|failed|Unauthorized|401|403|auth|Agent|unexpected|timeout' "$LOGDIR" 2>/dev/null | tail -60
fi
echo "=== folder uri / ide_state ==="
cat /home/$U/.cursor/ide_state.json 2>/dev/null
echo
ls -lt /home/$U/.cursor-server/data/User/workspaceStorage 2>/dev/null | head -8
echo "=== stale servers ==="
ps -u $U -o pid,etime,cmd | grep -E 'cursor-server|vscode-server|multiplex' | grep -v grep
echo "=== client bundle version ==="
cat /usr/local/share/claude-client/VERSION 2>/dev/null || cat /usr/local/share/claude-client/version 2>/dev/null
ls /usr/local/share/claude-client 2>/dev/null | head -10
'@

$sh = Join-Path $env:TEMP 'sepidz-hosseinm-auth.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -q $sh "${target}:/tmp/sepidz-hosseinm-auth.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-hm-auth.out'
$e = Join-Path $env:TEMP 'sepidz-hm-auth.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=25',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-hosseinm-auth.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(60000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; exit 4 }
Get-Content $o -Raw -EA 0
