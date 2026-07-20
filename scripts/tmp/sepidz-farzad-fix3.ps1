$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))

# Pure bash remote - no nested PowerShell expansion traps
$remote = @'
#!/bin/bash
set +e
PW=$(printf '%s' 'PW_B64_HERE' | base64 -d)
sudo_bash() { printf '%s\n' "$PW" | sudo -S -p '' bash -s; }

sudo_bash <<'INNER'
set +e
U=farzadb
GOLD=$(tr -d '\r\n' < /etc/cursor-auth/golden/machine-id.txt)
install -d -o "$U" -g "$U" -m 700 /home/$U/.config/Cursor /home/$U/.cursor-server/data
# write machineid with python to avoid quote bugs
python3 - <<PY
gold=open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip()
# strip accidental quote bytes
gold=gold.strip(b"\"'")
for path in [
  "/home/farzadb/.config/Cursor/machineid",
  "/home/farzadb/.cursor-server/data/machineid",
]:
  open(path,"wb").write(gold)
  print(path, "bytes", gold)
PY
chown farzadb:farzadb /home/farzadb/.config/Cursor/machineid /home/farzadb/.cursor-server/data/machineid
chmod 644 /home/farzadb/.config/Cursor/machineid /home/farzadb/.cursor-server/data/machineid
echo "=== machineid verify ==="
xxd /home/farzadb/.config/Cursor/machineid
xxd /home/farzadb/.cursor-server/data/machineid
xxd /etc/cursor-auth/golden/machine-id.txt
cmp -s /home/farzadb/.config/Cursor/machineid /etc/cursor-auth/golden/machine-id.txt && echo MID_OK || echo MID_BAD

# re-sync auth fully
claude-server sync-cursor-auth farzadb 2>&1 | tail -20

python3 - <<'PY'
import json, sqlite3, os
db="/home/farzadb/.config/Cursor/User/globalStorage/state.vscdb"
auth=json.load(open("/etc/cursor-auth/golden/auth.json"))
mapping={
  "accessToken":"cursorAuth/accessToken",
  "refreshToken":"cursorAuth/refreshToken",
  "cachedEmail":"cursorAuth/cachedEmail",
  "cachedSignUpType":"cursorAuth/cachedSignUpType",
  "stripeMembershipType":"cursorAuth/stripeMembershipType",
  "stripeSubscriptionStatus":"cursorAuth/stripeSubscriptionStatus",
}
sk={}
try: sk=json.load(open("/etc/cursor-auth/golden/state-keys.json"))
except Exception: pass
c=sqlite3.connect(db); cur=c.cursor()
cur.execute("create table if not exists ItemTable (key text unique, value blob)")
for src,dst in mapping.items():
  if src in auth and auth[src] is not None:
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (dst, str(auth[src])))
for k,v in sk.items():
  if isinstance(v,(str,int,float)):
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, str(v)))
  elif v is not None:
    cur.execute("insert or replace into ItemTable(key,value) values(?,?)", (k, json.dumps(v)))
c.commit()
print("auth_keys", [r[0] for r in cur.execute("select key from ItemTable where key like 'cursorAuth/%' order by key")])
c.close()
os.system("chown farzadb:farzadb "+db)
PY

echo "=== shell probe ==="
timeout 5 su - farzadb -c 'echo SHELL_OK' ; echo shell_ec=$?
echo "=== bashrc suspects ==="
grep -nE 'sleep|claude-mount|sshfs|while |laptop-exec|nc |curl ' /home/farzadb/.bashrc /home/farzadb/.profile 2>/dev/null | head -40 || true

echo "=== remount ==="
# push active mount hint
printf 'LAPTOP_USER=f.bahadorifar\nTUNNEL_PORT=21006\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=frontend\n' > /home/farzadb/.claude-connect.conf
chown farzadb:farzadb /home/farzadb/.claude-connect.conf
chmod 600 /home/farzadb/.claude-connect.conf
su - farzadb -c 'claude-mount status' 2>&1 | head -30
su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up frontend' 2>&1 | tail -30
su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up backend' 2>&1 | tail -30
mountpoint /home/farzadb/mounts/frontend; mountpoint /home/farzadb/mounts/backend
ls /home/farzadb/mounts/frontend 2>&1 | head -10
ls /home/farzadb/mounts/backend 2>&1 | head -10
echo DONE
INNER
'@

$remote = $remote.Replace('PW_B64_HERE', $pwB64)
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
& ssh -o BatchMode=yes -o ConnectTimeout=60 sepidz@192.168.250.70 "echo $b64 | base64 -d > /tmp/farzad-fix.sh && bash /tmp/farzad-fix.sh"
