$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$bash = @"
set +e
PW=`$(printf '%s' '$pwB64' | base64 -d)
U=farzadb
sudo_run() { printf '%s\n' "`$PW" | sudo -S -p '' bash -lc "`$1"; }

echo '=== remoteagent tail ==='
sudo_run 'tail -80 /home/farzadb/.cursor-server/data/logs/20260718T115406/remoteagent.log 2>/dev/null'
echo '=== exthost errors ==='
sudo_run 'grep -iE \"error|fail|auth|unauthorized|machine\" /home/farzadb/.cursor-server/data/logs/20260718T115406/exthost1/remoteexthost.log 2>/dev/null | tail -40'

echo '=== BEFORE ==='
sudo_run 'echo profile=`$(cat /home/farzadb/.config/Cursor/machineid 2>/dev/null || echo MISSING); echo server=`$(cat /home/farzadb/.cursor-server/data/machineid 2>/dev/null || echo MISSING)'

echo '=== sync-cursor-auth ==='
sudo_run 'claude-server sync-cursor-auth farzadb 2>&1 | tail -50'

GOLD=`$(sudo_run 'cat /etc/cursor-auth/golden/machine-id.txt' | tr -d '\r\n')
echo "GOLD=`$GOLD"

# machineid align
sudo_run "install -d -o farzadb -g farzadb -m 700 /home/farzadb/.config/Cursor; printf '%s' '`$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)' > /tmp/golden_mid.txt"
# better do all in one sudo script
sudo_run 'GOLD=`$(cat /etc/cursor-auth/golden/machine-id.txt); install -d -o farzadb -g farzadb -m 700 /home/farzadb/.config/Cursor /home/farzadb/.cursor-server/data; printf \"%s\" \"`$GOLD\" > /home/farzadb/.config/Cursor/machineid; printf \"%s\" \"`$GOLD\" > /home/farzadb/.cursor-server/data/machineid; chown farzadb:farzadb /home/farzadb/.config/Cursor/machineid /home/farzadb/.cursor-server/data/machineid; chmod 644 /home/farzadb/.config/Cursor/machineid /home/farzadb/.cursor-server/data/machineid'

# merge auth keys from golden
sudo_run 'python3 - <<'\''PY'\''
import json, sqlite3, os
u="/home/farzadb"
db=f"{u}/.config/Cursor/User/globalStorage/state.vscdb"
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
try:
  sk=json.load(open("/etc/cursor-auth/golden/state-keys.json"))
except Exception as e:
  print("no state-keys", e)
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
keys=[r[0] for r in cur.execute("select key from ItemTable where key like \"cursorAuth/%\" or key like \"cursor.%\" order by key")]
print("written", len(set(written)))
print("keys", keys)
print("db_bytes", os.path.getsize(db))
c.close()
os.system(f"chown farzadb:farzadb {db}")
PY'

echo '=== AFTER ==='
sudo_run 'echo profile=`$(cat /home/farzadb/.config/Cursor/machineid); echo server=`$(cat /home/farzadb/.cursor-server/data/machineid); echo golden=`$(cat /etc/cursor-auth/golden/machine-id.txt)'
sudo_run 'python3 - <<'\''PY'\''
import sqlite3
c=sqlite3.connect("file:/home/farzadb/.config/Cursor/User/globalStorage/state.vscdb?mode=ro", uri=True)
for k, in c.execute("select key from ItemTable where key like \"cursorAuth/%\" order by key"):
  print(" ", k)
c.close()
PY'
echo '=== mount confs ==='
sudo_run 'ls -la /home/farzadb/.claude-mounts.d/ 2>&1; for f in /home/farzadb/.claude-mounts.d/*; do echo FILE=`$f; cat `$f; echo; done'
echo 'TELL_USER: Reload Window'
echo DONE
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -o BatchMode=yes -o ConnectTimeout=30 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
