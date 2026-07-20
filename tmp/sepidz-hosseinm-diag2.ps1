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
echo "=== shell startup timing ==="
sudo -u $U -H bash -lc 'TIMEFORMAT=%R; time true' 2>&1
echo "--- bashrc sizes ---"
wc -l /home/$U/.bashrc /home/$U/.profile /home/$U/.bash_profile 2>/dev/null
echo "--- bashrc suspicious ---"
grep -nE 'ssh|mount|sleep|curl|claude|nvm|conda|oh-my|compinit|fortune' /home/$U/.bashrc /home/$U/.profile 2>/dev/null | head -40
echo "=== machineid compare ==="
echo "server_data=$(cat /home/$U/.cursor-server/data/machineid 2>/dev/null)"
echo "golden=$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)"
echo "profile_exists=$(test -f /home/$U/.config/Cursor/machineid && echo yes || echo no)"
echo "=== golden auth keys vs user ==="
python3 <<'PY'
import json,sqlite3
g=json.load(open("/etc/cursor-auth/golden/auth.json"))
print("golden_keys", sorted(g.keys()))
sk=json.load(open("/etc/cursor-auth/golden/state-keys.json"))
print("golden_state_keys", sorted(sk.keys()) if isinstance(sk,dict) else type(sk))
c=sqlite3.connect("file:/home/hosseinm/.config/Cursor/User/globalStorage/state.vscdb?mode=ro", uri=True)
rows=[r[0] for r in c.execute("select key from ItemTable")]
print("user_keys", rows)
print("missing_vs_golden_state", [k for k in (sk.keys() if isinstance(sk,dict) else []) if k not in rows][:40])
c.close()
PY
echo "=== Agent Exec log tail ==="
LOG=$(ls -t /home/$U/.cursor-server/data/logs/*/exthost*/anysphere.cursor-agent-exec/"Cursor Agent Exec.log" 2>/dev/null | head -1)
echo "LOG=$LOG"
tail -80 "$LOG" 2>/dev/null
echo "=== remoteexthost agent errors ==="
grep -RIhE 'Unexpected|Timed out|unauthorized|401|403|login|sign in|Invalid|Agent' /home/$U/.cursor-server/data/logs/20260718T131123/exthost2/remoteexthost.log 2>/dev/null | tail -40
echo "=== connect-version client ==="
cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null
echo "=== git at mount ==="
ls -la "/home/$U/mounts/sepidz-web/.git" 2>&1 | head -5
ls -la "/home/$U/mounts/sepidz-web/.git.server-session" 2>&1 | head -5
sudo -u $U -H bash -lc 'cd /home/hosseinm/mounts/sepidz-web && git status -sb 2>&1 | head -20'
echo "=== storage.json ==="
cat /home/$U/.config/Cursor/User/globalStorage/storage.json 2>/dev/null
'@

$sh = Join-Path $env:TEMP 'sepidz-hm-diag2.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -q $sh "${target}:/tmp/sepidz-hm-diag2.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-hm-diag2.out'
$e = Join-Path $env:TEMP 'sepidz-hm-diag2.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=25',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-hm-diag2.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(90000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; exit 4 }
Get-Content $o -Raw -EA 0
