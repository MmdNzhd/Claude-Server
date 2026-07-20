$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))

$py = @'
import json, os, sqlite3, subprocess

def sh(cmd):
    print("+", cmd, flush=True)
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    if r.stdout: print(r.stdout.rstrip(), flush=True)
    if r.stderr: print(r.stderr.rstrip(), flush=True)
    return r

gold = open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
print("gold", gold, flush=True)
os.makedirs("/home/farzadb/.config/Cursor", exist_ok=True)
os.makedirs("/home/farzadb/.cursor-server/data", exist_ok=True)
for path in ["/home/farzadb/.config/Cursor/machineid", "/home/farzadb/.cursor-server/data/machineid"]:
    open(path,"wb").write(gold)
    os.chown(path, 1006, 1006)
    os.chmod(path, 0o644)
    print("wrote", path, open(path,"rb").read(), flush=True)

db="/home/farzadb/.config/Cursor/User/globalStorage/state.vscdb"
os.makedirs(os.path.dirname(db), exist_ok=True)
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
except Exception as e: print("state-keys", e)
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
print("auth", [r[0] for r in cur.execute("select key from ItemTable where key like 'cursorAuth/%' order by key")], flush=True)
c.close()
os.chown(db, 1006, 1006)

conf = "LAPTOP_USER=f.bahadorifar\nTUNNEL_PORT=21006\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=frontend\n"
open("/home/farzadb/.claude-connect.conf","w").write(conf)
os.chown("/home/farzadb/.claude-connect.conf", 1006, 1006)
os.chmod("/home/farzadb/.claude-connect.conf", 0o600)
print("conf written", flush=True)

sh("claude-server sync-cursor-auth farzadb")
sh("timeout 5 su - farzadb -c 'echo SHELL_OK'")
sh("su - farzadb -c 'claude-mount status'")
sh("su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up frontend'")
sh("su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up backend'")
sh("mountpoint /home/farzadb/mounts/frontend || true")
sh("mountpoint /home/farzadb/mounts/backend || true")
sh("ls /home/farzadb/mounts/frontend | head")
sh("ls /home/farzadb/mounts/backend | head")
print("DONE", flush=True)
'@

$pyPath = Join-Path $env:TEMP 'farzad_fix.py'
[System.IO.File]::WriteAllText($pyPath, $py)
& scp -o BatchMode=yes -o ConnectTimeout=15 -q $pyPath 'sepidz@192.168.250.70:/tmp/farzad_fix.py'
if ($LASTEXITCODE -ne 0) { throw 'scp py failed' }

# IMPORTANT: only single-quoted construction so PowerShell never expands $(...)
$wrap = 'PW=$(echo ' + $pwB64 + ' | base64 -d); printf "%s\n" "$PW" | sudo -S -p "" python3 /tmp/farzad_fix.py'
Write-Host 'running...'
& ssh -o BatchMode=yes -o ConnectTimeout=120 sepidz@192.168.250.70 $wrap
Write-Host "exit=$LASTEXITCODE"
