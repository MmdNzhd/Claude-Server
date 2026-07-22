#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw=Get-Content 'publish\sepidz-deploy.local.ps1' -Raw
$pw=[regex]::Match($raw,'(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$target='sepidz@192.168.250.70'
$remote='/home/sepidz/golden-prove.sh'
$local=Join-Path $env:TEMP ('gp-'+[guid]::NewGuid().ToString('n')+'.sh')
$sh=@'
#!/bin/bash
set +e
echo === GOLDEN ===
ls -la /etc/cursor-auth /etc/cursor-auth/golden 2>&1
ls -la /etc/cursor-auth/golden/ 2>&1
getent group cursorauth 2>&1 || echo NO_GROUP
echo === IDS ===
id farzadb; id hosseinb; id sepidz; id smart 2>&1
echo === READ AS farzadb ===
sudo -u farzadb bash -c 'test -r /etc/cursor-auth/golden/machine-id.txt; echo mid_readable=$?; wc -c </etc/cursor-auth/golden/machine-id.txt 2>&1; head -c 8 /etc/cursor-auth/golden/machine-id.txt 2>&1 | od -An -tx1'
sudo -u farzadb bash -c 'test -r /etc/cursor-auth/golden/auth.json; echo auth_readable=$?'
echo === READ AS sepidz ===
sudo -u sepidz bash -c 'test -r /etc/cursor-auth/golden/machine-id.txt; echo mid_readable=$?'
echo === INSTALL MARKERS ===
grep -n cursorauth /usr/local/lib/claude-server/commands/install.sh 2>/dev/null | head -5 || grep -n cursorauth /usr/local/lib/claude-server/install.sh 2>/dev/null | head -5
ls -la /usr/local/lib/claude-server/commands/install.sh 2>&1 | head -2
stat -c '%y %n' /etc/cursor-auth/golden/machine-id.txt 2>&1
echo __DONE__
'@
[IO.File]::WriteAllText($local,$sh.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding $false))
scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $local ($target+':'+$remote)
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='ssh.exe'
$psi.Arguments="-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no $target `"sudo -S -p '' bash $remote; rm -f $remote`""
$psi.UseShellExecute=$false; $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
$p=[Diagnostics.Process]::Start($psi); $p.StandardInput.WriteLine($pw); $p.StandardInput.Close()
$out=$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(90000)
Write-Output $out
Remove-Item $local -Force -EA SilentlyContinue
