$ErrorActionPreference = 'Stop'
$cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'publish\sepidz-deploy.local.ps1'
if (-not (Test-Path $cfgPath)) { $cfgPath = 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' }
$cfg = Get-Content $cfgPath -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no SepidzSudoPassword' }
$pw = $Matches[1]
$user = 'sepidz'
if ($cfg -match "SepidzSshUser\s*=\s*'([^']+)'") { $user = $Matches[1] }
$hostIp = '192.168.250.70'
if ($cfg -match "SepidzServerIp\s*=\s*'([^']+)'") { $hostIp = $Matches[1] }
$bash = @'
set -e
echo HOST=$(hostname)
echo "=== homes ==="
ls /home
echo "=== passwd azin-like ==="
getent passwd | grep -iE "azin|azeen|azhin|adin" || true
echo "=== connect logs 5d ==="
find /home -path "*/.claude/logs/connect-*.log" -mtime -5 2>/dev/null -printf "%T+ %u %p %s\n" | sort -r | head -50
echo "=== diag 5d ==="
find /home -path "*/.claude/logs/laptop-ssh*" -mtime -5 2>/dev/null -printf "%T+ %u %p %s\n" | sort -r | head -30
echo "=== connect.conf ==="
for u in /home/*; do
  if [ -f "$u/.claude-connect.conf" ]; then echo "---- $(basename $u) ----"; cat "$u/.claude-connect.conf"; fi
done
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
$remoteCmd = "printf '%s\n' $(ConvertTo-Json $pw) | sudo -S -p '' bash -c `"echo $b64 | base64 -d | bash`""
# Simpler approach with plink-style via bash -c and env
$psi = @"
pw=$(ConvertTo-Json $pw)
ssh -o BatchMode=yes -o ConnectTimeout=15 ${user}@${hostIp} `"printf '%s\n' `$pw | sudo -S -p '' bash -s`" <<'REMOTE'
$bash
REMOTE
"@
# Even simpler: write remote script then run
$tmpRemote = "/tmp/list-azin-logs.sh"
$bash | ssh -o BatchMode=yes "${user}@${hostIp}" "cat > $tmpRemote && chmod 700 $tmpRemote"
$pwJson = ConvertTo-Json $pw
ssh -o BatchMode=yes "${user}@${hostIp}" "printf '%s\n' $pwJson | sudo -S -p '' bash $tmpRemote"
