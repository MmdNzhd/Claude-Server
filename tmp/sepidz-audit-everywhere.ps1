#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw=Get-Content 'publish\sepidz-deploy.local.ps1' -Raw
$pw=[regex]::Match($raw,'(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$target='sepidz@192.168.250.70'
$remote='/home/sepidz/chk.sh'
$local=Join-Path $env:TEMP ('chk-'+[guid]::NewGuid().ToString('n')+'.sh')
$sh=@'
#!/bin/bash
set +e
echo === SEPIDZ audit install ===
ls -la /usr/local/bin/laptop-exec /usr/local/lib/claude-server/cursor-hooks/laptop-exec-audit-log.sh
grep -c _le_audit /usr/local/bin/laptop-exec
echo === per-user ===
for h in /home/*; do
  u=$(basename "$h"); [ -d "$h" ] || continue
  a=0; [ -f "$h/.cursor/hooks/laptop-exec-audit-log.sh" ] && a=1
  le=0; [ -f "$h/.local/bin/laptop-exec" ] && grep -q _le_audit "$h/.local/bin/laptop-exec" 2>/dev/null && le=1
  echo "user=$u audit_helper=$a le_audit=$le"
done
echo === farzadb first/last today ===
f=/home/farzadb/.claude/logs/connect-20260722.log
head -2 "$f"; echo ...; tail -2 "$f"
echo === note: multiagent only after 08:56Z smoke ===
grep -c multiagent /home/sepidz/.claude/logs/connect-20260722.log 2>/dev/null
grep -c multiagent /home/farzadb/.claude/logs/connect-20260722.log 2>/dev/null
echo __DONE__
'@
[IO.File]::WriteAllText($local,$sh.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding $false))
scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $local ($target+':'+$remote) | Out-Null
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='ssh.exe'
$psi.Arguments="-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no $target `"sudo -S -p '' bash $remote; rm -f $remote`""
$psi.UseShellExecute=$false; $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
$p=[Diagnostics.Process]::Start($psi); $p.StandardInput.WriteLine($pw); $p.StandardInput.Close()
$out=$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(60000)
Write-Output $out
Remove-Item $local -Force -EA SilentlyContinue
