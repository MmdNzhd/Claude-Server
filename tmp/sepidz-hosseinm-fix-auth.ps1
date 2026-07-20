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
echo "=== before ==="
echo "profile_mid=$(cat /home/$U/.config/Cursor/machineid 2>/dev/null || echo MISSING)"
echo "server_mid=$(cat /home/$U/.cursor-server/data/machineid 2>/dev/null || echo MISSING)"
echo "golden_mid=$(cat /etc/cursor-auth/golden/machine-id.txt)"
echo "db_bytes=$(stat -c%s /home/$U/.config/Cursor/User/globalStorage/state.vscdb 2>/dev/null)"

# Prefer official sync if available
if command -v claude-server >/dev/null 2>&1; then
  echo "=== claude-server sync-cursor-auth $U ==="
  claude-server sync-cursor-auth "$U" 2>&1 | tail -40
else
  echo "no claude-server cmd"
fi

# Ensure profile machineid matches golden (known auth drift fix)
GOLD=$(cat /etc/cursor-auth/golden/machine-id.txt)
install -d -o $U -g $U -m 700 /home/$U/.config/Cursor
printf '%s' "$GOLD" > /home/$U/.config/Cursor/machineid
chown $U:$U /home/$U/.config/Cursor/machineid
chmod 644 /home/$U/.config/Cursor/machineid

# Align cursor-server data machineid too
if [ -d /home/$U/.cursor-server/data ]; then
  printf '%s' "$GOLD" > /home/$U/.cursor-server/data/machineid
  chown $U:$U /home/$U/.cursor-server/data/machineid
fi

# Merge missing auth identity keys from golden auth.json into state.vscdb
python3 <<'PY'
import json, sqlite3, os
u="/home/hosseinm"
db=f"{u}/.config/Cursor/User/globalStorage/state.vscdb"
auth=json.load(open("/etc/cursor-auth/golden/auth.json"))
# map golden auth.json flat keys -> cursorAuth/* in ItemTable
mapping={
  "accessToken":"cursorAuth/accessToken",
  "refreshToken":"cursorAuth/refreshToken",
  "cachedEmail":"cursorAuth/cachedEmail",
  "cachedSignUpType":"cursorAuth/cachedSignUpType",
  "stripeMembershipType":"cursorAuth/stripeMembershipType",
  "stripeSubscriptionStatus":"cursorAuth/stripeSubscriptionStatus",
}
sk=json.load(open("/etc/cursor-auth/golden/state-keys.json"))
c=sqlite3.connect(db)
cur=c.cursor()
cur.execute("create table if not exists ItemTable (key text unique, value blob)")
written=[]
for src,dst in mapping.items():
  if src in auth and auth[src] is not None:
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (dst, str(auth[src])))
    written.append(dst)
for k,v in sk.items():
  if isinstance(v,(str,int,float)):
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, str(v)))
    written.append(k)
  elif v is not None:
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, json.dumps(v)))
    written.append(k)
c.commit()
# list keys
keys=[r[0] for r in cur.execute("select key from ItemTable order by key")]
print("written_count", len(set(written)))
print("keys_now", keys)
print("db_bytes", os.path.getsize(db))
c.close()
# ownership
os.system(f"chown hosseinm:hosseinm {db}")
PY

echo "=== after ==="
echo "profile_mid=$(cat /home/$U/.config/Cursor/machineid)"
echo "server_mid=$(cat /home/$U/.cursor-server/data/machineid)"
echo "golden_mid=$(cat /etc/cursor-auth/golden/machine-id.txt)"
echo "db_bytes=$(stat -c%s /home/$U/.config/Cursor/User/globalStorage/state.vscdb)"
python3 <<'PY'
import sqlite3
c=sqlite3.connect("file:/home/hosseinm/.config/Cursor/User/globalStorage/state.vscdb?mode=ro", uri=True)
for k, in c.execute("select key from ItemTable order by key"):
  print(" ", k)
c.close()
PY
echo "=== DONE: user should Reload Window ==="
'@

$sh = Join-Path $env:TEMP 'sepidz-hm-fix.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -q $sh "${target}:/tmp/sepidz-hm-fix.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-hm-fix.out'
$e = Join-Path $env:TEMP 'sepidz-hm-fix.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=25',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-hm-fix.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(60000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; exit 4 }
Get-Content $o -Raw -EA 0
if (Test-Path $e) { $err=Get-Content $e -Raw; if ($err) { Write-Output '---stderr---'; $err } }
