#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw=Get-Content 'publish\sepidz-deploy.local.ps1' -Raw
$pw=[regex]::Match($raw,'(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$target='sepidz@192.168.250.70'
$remote='/home/sepidz/golden-deep.sh'
$local=Join-Path $env:TEMP ('gd-'+[guid]::NewGuid().ToString('n')+'.sh')
$sh=@'
#!/bin/bash
set +e
echo ===GOLDEN===
ls -la /etc/cursor-auth /etc/cursor-auth/golden 2>&1
echo ===GROUP===
getent group cursorauth; grep cursorauth /etc/group
echo ===IDS===
for u in farzadb hosseinb sepidz smart aminb; do id "$u" 2>&1; done
echo ===READ_AS_FARZADB===
sudo -u farzadb bash -c 'test -r /etc/cursor-auth/golden/machine-id.txt && echo READ_OK || echo READ_FAIL; cat /etc/cursor-auth/golden/machine-id.txt 2>&1 | wc -c'
echo ===READ_AS_SEPIDZ===
sudo -u sepidz bash -c 'test -r /etc/cursor-auth/golden/machine-id.txt && echo READ_OK || echo READ_FAIL'
echo ===INSTALL_MARKERS===
# when was install last? 
stat /usr/local/lib/claude-server/commands/install.sh 2>&1 | head -5
grep -n cursorauth /usr/local/lib/claude-server/commands/install.sh 2>/dev/null | head -10
echo ===PROXY_FROM_LOG_FARZADB===
grep -E 'PROXY_HEALTH ok=0|machineid|SIDECAR_ENSURE|CURSOR_PROXY' /home/farzadb/.claude/logs/connect-20260722.log | head -30
echo __DONE__
'@
[IO.File]::WriteAllText($local,$sh.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding $false))
scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $local ($target+':'+$remote)
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='ssh.exe'
$psi.Arguments="-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no $target `"sudo -S -p '' bash $remote; rm -f $remote`""
$psi.UseShellExecute=$false; $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
$p=[Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine($pw); $p.StandardInput.Close()
$out=$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(90000)
Write-Output $out
Remove-Item $local -Force -EA SilentlyContinue
