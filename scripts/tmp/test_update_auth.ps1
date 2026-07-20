$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
cat >/tmp/ua.sh <<'INNER'
#!/bin/bash
echo "=== sepidz authorized_keys count ==="
wc -l /home/sepidz/.ssh/authorized_keys 2>/dev/null || echo none
echo "=== farzadb pubkey ==="
cat /home/farzadb/.ssh/authorized_keys 2>/dev/null
echo "=== is farzad key in sepidz authorized? ==="
fk=$(awk '{print $2}' /home/farzadb/.ssh/authorized_keys 2>/dev/null | head -1)
if [ -n "$fk" ] && grep -q "$fk" /home/sepidz/.ssh/authorized_keys 2>/dev/null; then echo YES_IN_SEPIDZ; else echo NO_NOT_IN_SEPIDZ; fi
echo "=== can farzadb read bundle path? ==="
sudo -u farzadb test -r /usr/local/share/claude-client/connect-version.txt && echo farzadb_can_read_bundle || echo farzadb_NO_read
ls -la /usr/local/share/claude-client/connect-version.txt
# sshd Match for sepidz?
grep -n "sepidz\|claude-client\|ForceCommand" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null | head -30
INNER
printf '%s\n' "$PW" | sudo -S -p '' bash /tmp/ua.sh
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'ua.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/ua0.sh && bash /tmp/ua0.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
