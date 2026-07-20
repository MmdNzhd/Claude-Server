$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$bash = @"
set +e
PW=`$(printf '%s' '$pwB64' | base64 -d)
U=farzadb
sudo_run() { printf '%s\n' "`$PW" | sudo -S -p '' bash -lc "`$1"; }
echo '=== conf ==='
sudo_run "cat /home/`$U/.claude-connect.conf 2>&1"
echo '=== mounts ==='
sudo_run "ls -la /home/`$U/mounts 2>&1; for d in /home/`$U/mounts/*; do echo DIR=`$d; mountpoint -q `$d && echo MOUNTED || echo not_mounted; ls -ld `$d/.git `$d/.git.server-session 2>&1 | head -3; done"
echo '=== machineid ==='
sudo_run "echo profile=`$(cat /home/`$U/.config/Cursor/machineid 2>/dev/null || echo MISSING); echo server=`$(cat /home/`$U/.cursor-server/data/machineid 2>/dev/null || echo MISSING); echo golden=`$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)"
echo '=== auth keys ==='
sudo_run "python3 - <<'PY'
import sqlite3, os
db='/home/farzadb/.config/Cursor/User/globalStorage/state.vscdb'
print('db_exists', os.path.exists(db), 'bytes', os.path.getsize(db) if os.path.exists(db) else 0)
if os.path.exists(db):
  c=sqlite3.connect('file:'+db+'?mode=ro', uri=True)
  keys=[r[0] for r in c.execute(\"select key from ItemTable where key like 'cursorAuth/%' order by key\")]
  print('auth_keys', keys)
  for k in keys:
    v=c.execute('select value from ItemTable where key=?',(k,)).fetchone()[0]
    s=str(v)
    print(k, 'len', len(s), 'preview', s[:24].replace(chr(10),' '))
  c.close()
PY"
echo '=== processes ==='
sudo_run "ps -u `$U -o pid,cmd --sort=-pid 2>/dev/null | head -40"
echo '=== tunnel ports ==='
sudo_run "ss -ltnp 2>/dev/null | grep -E '2100|claude|ssh' | head -20; cat /home/`$U/.claude-connect.conf"
echo '=== recent cursor logs ==='
sudo_run "ls -lt /home/`$U/.cursor-server/data/logs 2>/dev/null | head -8; ls -lt /home/`$U/.claude/logs 2>/dev/null | head -8"
echo '=== last remote ssh ==='
sudo_run "ls -lt /home/`$U/.cursor-server/.cursor-server.log /home/`$U/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null | head -10"
sudo_run "find /home/`$U/.cursor-server/data/logs -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -5 | while read t p; do echo FILE=`$p; tail -40 `$p; echo '---'; done"
echo DONE
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
