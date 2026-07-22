$ErrorActionPreference = "Stop"
. "D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1"
$pw = $SepidzSudoPassword
$sshTarget = "sepidz@192.168.250.70"
Write-Output "target=$sshTarget"

$bash = @'
set +e
echo "=== HOST ==="
hostname; whoami; date -Is
echo "=== GOLDEN ACL ==="
ls -la /etc/cursor-auth/golden/ 2>&1
echo "=== STAT ==="
stat -c "%a %U:%G %n" /etc/cursor-auth /etc/cursor-auth/golden /etc/cursor-auth/golden/* 2>&1
echo "=== GROUP cursorauth ==="
getent group cursorauth 2>&1
echo "=== IDS ==="
id farzadb 2>&1
id hosseinb 2>&1
id sepidz 2>&1
echo "=== FARZADB READ machine-id ==="
sudo -u farzadb cat /etc/cursor-auth/golden/machine-id.txt >/tmp/farzadb-machineid.out 2>/tmp/farzadb-machineid.err
ec=$?
echo "exit=$ec"
echo "stderr:"; cat /tmp/farzadb-machineid.err 2>/dev/null
echo "stdout_len=$(wc -c </tmp/farzadb-machineid.out 2>/dev/null)"
echo "=== HOSSEINB READ machine-id ==="
sudo -u hosseinb cat /etc/cursor-auth/golden/machine-id.txt >/tmp/hosseinb-machineid.out 2>/tmp/hosseinb-machineid.err
ec2=$?
echo "exit=$ec2"
echo "stderr:"; cat /tmp/hosseinb-machineid.err 2>/dev/null
echo "=== SEPIDZ READ machine-id ==="
sudo -u sepidz cat /etc/cursor-auth/golden/machine-id.txt >/tmp/sepidz-machineid.out 2>/tmp/sepidz-machineid.err
ec3=$?
echo "exit=$ec3"
echo "stderr:"; cat /tmp/sepidz-machineid.err 2>/dev/null
echo "=== PASSWD UIDs ==="
getent passwd farzadb hosseinb sepidz 2>&1
echo "=== DONE ==="
'@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
$passB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))

$remote = @"
set -euo pipefail
PASS=`$(printf '%s' '$passB64' | base64 -d)
SCRIPT=`$(printf '%s' '$b64' | base64 -d)
printf '%s\n' "`$PASS" | sudo -S -p '' bash -lc "`$SCRIPT"
"@

$out = & ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new $sshTarget $remote 2>&1
Write-Output $out
Write-Output "SSH_EXIT=$LASTEXITCODE"
