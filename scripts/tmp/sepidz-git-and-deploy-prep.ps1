$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Matches[1]))

$bash = @"
#!/bin/bash
set +e
PW=`$(printf '%s' '$pwB64' | base64 -d)
sudo_run() { printf '%s\n' "`$PW" | sudo -S -p '' bash -lc "`$1"; }
echo '=== git binary ==='
sudo_run 'su - hosseinm -c "command -v git; git --version; type git"'
echo '=== nested git under sepidz-web (no find mounts hang - limited) ==='
sudo_run 'for d in /home/hosseinm/mounts/sepidz-web/Backend /home/hosseinm/mounts/sepidz-web/Frontend /home/hosseinm/mounts/sepidz-web/Extra /home/hosseinm/mounts/sepidz-web; do echo -- `$d; ls -ld `$d/.git `$d/.git.server-session 2>&1 | head -2; done'
echo '=== cursor workspace git setting ==='
sudo_run 'ls /home/hosseinm/mounts/sepidz-web/.vscode 2>&1; ls /home/hosseinm/mounts/sepidz-web/.cursor 2>&1 | head'
echo '=== sudoers client deploy ==='
sudo_run 'ls -la /etc/sudoers.d/ 2>&1 | head -20; grep -l claude /etc/sudoers.d/* 2>/dev/null; cat /etc/sudoers.d/*claude* 2>/dev/null | head -20'
echo DONE
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -i $key -o BatchMode=yes -o ConnectTimeout=20 $target "echo $b64 | base64 -d > /tmp/gcheck.sh && bash /tmp/gcheck.sh"
