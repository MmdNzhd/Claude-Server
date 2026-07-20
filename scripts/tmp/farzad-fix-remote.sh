#!/bin/bash
set +e
PW="$1"
sudo_bash() { printf '%s\n' "$PW" | sudo -S -p '' bash -s; }

sudo_bash <<'INNER'
set +e
U=farzadb
echo "=== fix machineid ==="
python3 - <<'PY'
gold=open("/etc/cursor-auth/golden/machine-id.txt","rb").read().replace(b"\r",b"").replace(b"\n",b"").strip().strip(b"\"'")
import os
os.makedirs("/home/farzadb/.config/Cursor", exist_ok=True)
os.makedirs("/home/farzadb/.cursor-server/data", exist_ok=True)
for path in [
  "/home/farzadb/.config/Cursor/machineid",
  "/home/farzadb/.cursor-server/data/machineid",
]:
  open(path,"wb").write(gold)
  print(path, gold.decode())
PY
chown -R farzadb:farzadb /home/farzadb/.config/Cursor /home/farzadb/.cursor-server/data/machineid
cmp -s /home/farzadb/.config/Cursor/machineid /etc/cursor-auth/golden/machine-id.txt && echo MID_OK || echo MID_BAD
xxd /home/farzadb/.config/Cursor/machineid | head -2

echo "=== sync auth ==="
claude-server sync-cursor-auth farzadb 2>&1 | tail -30

python3 - <<'PY'
import json, sqlite3, os
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
print("db_bytes", os.path.getsize(db))
PY

echo "=== shell ==="
timeout 5 su - farzadb -c 'echo SHELL_OK'; echo shell_ec=$?
grep -nE 'sleep|claude-mount|sshfs|while |laptop-exec' /home/farzadb/.bashrc /home/farzadb/.profile 2>/dev/null | head -40 || echo no_suspects

echo "=== remount ==="
cat > /home/farzadb/.claude-connect.conf <<'CONF'
LAPTOP_USER=f.bahadorifar
TUNNEL_PORT=21006
GIT_MODE=off
LAPTOP_OS=windows
ACTIVE_MOUNT=frontend
CONF
chown farzadb:farzadb /home/farzadb/.claude-connect.conf
chmod 600 /home/farzadb/.claude-connect.conf
su - farzadb -c 'claude-mount status' 2>&1 | head -40
su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up frontend' 2>&1 | tail -40
su - farzadb -c 'CLAUDE_TRUSTED_TUNNEL=1 claude-mount up backend' 2>&1 | tail -40
mountpoint /home/farzadb/mounts/frontend || true
mountpoint /home/farzadb/mounts/backend || true
ls /home/farzadb/mounts/frontend 2>&1 | head -8
ls /home/farzadb/mounts/backend 2>&1 | head -8
echo DONE
INNER
