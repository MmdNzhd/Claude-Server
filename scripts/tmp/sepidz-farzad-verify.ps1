$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$cmd = @'
PW=$(echo PW_B64 | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo MID_PROFILE=$(xxd -p /home/farzadb/.config/Cursor/machineid 2>/dev/null)
echo MID_SERVER=$(xxd -p /home/farzadb/.cursor-server/data/machineid 2>/dev/null)
echo MID_GOLDEN=$(xxd -p /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)
cmp -s /home/farzadb/.config/Cursor/machineid /etc/cursor-auth/golden/machine-id.txt && echo MID_OK || echo MID_BAD
python3 -c "import sqlite3; c=sqlite3.connect(\"file:/home/farzadb/.config/Cursor/User/globalStorage/state.vscdb?mode=ro\", uri=True); print([r[0] for r in c.execute(\"select key from ItemTable where key like \\\"cursorAuth/%\\\" order by key\")])"
echo CONF:; cat /home/farzadb/.claude-connect.conf
mountpoint /home/farzadb/mounts/frontend; mountpoint /home/farzadb/mounts/backend
ls /home/farzadb/mounts/frontend 2>&1 | head -5
ls /home/farzadb/mounts/backend 2>&1 | head -5
ss -ltn | grep 21006 || true
'
'@
$cmd = $cmd.Replace('PW_B64', $pwB64)
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
& ssh -o BatchMode=yes -o ConnectTimeout=20 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
