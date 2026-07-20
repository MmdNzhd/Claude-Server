$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
# files already on /tmp from previous upload? re-scp to be sure
& scp -o BatchMode=yes -o ControlMaster=no 'D:\Smart\Claude-Code-Server\scripts\server\commands\add-user.sh' 'sepidz@192.168.250.70:/tmp/add-user.sh'
& scp -o BatchMode=yes -o ControlMaster=no 'D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-client-bundle.sh' 'sepidz@192.168.250.70:/tmp/deploy-client-bundle.sh'
& scp -o BatchMode=yes -o ControlMaster=no 'D:\Smart\Claude-Code-Server\scripts\server\commands\install-client-bundle.sh' 'sepidz@192.168.250.70:/tmp/install-client-bundle.sh'
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
install -m 755 /tmp/add-user.sh /usr/local/lib/claude-server/add-user.sh
install -m 755 /tmp/deploy-client-bundle.sh /usr/local/lib/claude-server/deploy-client-bundle.sh
install -m 755 /tmp/install-client-bundle.sh /usr/local/lib/claude-server/commands/install-client-bundle.sh
# also flat copy if used
install -m 755 /tmp/install-client-bundle.sh /usr/local/lib/claude-server/install-client-bundle.sh 2>/dev/null || true
grep -c "timeout 10" /usr/local/lib/claude-server/add-user.sh
grep -c "_sync_sepidz_update_keys" /usr/local/lib/claude-server/deploy-client-bundle.sh
grep -c "_sync_sepidz_update_keys" /usr/local/lib/claude-server/commands/install-client-bundle.sh
echo INSTALLED_OK
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'ic2.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
