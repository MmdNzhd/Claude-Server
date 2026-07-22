#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw = Get-Content -LiteralPath 'publish\sepidz-deploy.local.ps1' -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$target = 'sepidz@192.168.250.70'
$remoteSh = '/home/sepidz/sepidz-log-users.sh'
$localSh = Join-Path $env:TEMP ('sepidz-u-' + [guid]::NewGuid().ToString('n') + '.sh')
$script = @'
#!/bin/bash
set +e
echo === farzadb connect WARN/ERROR last 25 ===
grep -E '\[ERROR\]|\[WARN\]' /home/farzadb/.claude/logs/connect-20260722.log | tail -25
echo === farzadb tail 15 ===
tail -15 /home/farzadb/.claude/logs/connect-20260722.log
echo === hosseinb WARN/ERROR last 20 ===
grep -E '\[ERROR\]|\[WARN\]' /home/hosseinb/.claude/logs/connect-20260722.log | tail -20
echo === hosseinb tail 10 ===
tail -10 /home/hosseinb/.claude/logs/connect-20260722.log
echo === multiagent any user today ===
for u in sepidz smart designer aminb hosseinb hosseinm farzadb zahrak alit nimaz; do
  f=/home/$u/.claude/logs/connect-20260722.log
  [ -f "$f" ] || continue
  n=$(grep -c '\[multiagent\]' "$f" 2>/dev/null || echo 0)
  echo "user=$u multiagent_lines=$n"
done
echo === who has laptop-exec audit today ===
for u in sepidz smart designer aminb hosseinb hosseinm farzadb zahrak alit nimaz; do
  f=/home/$u/.claude/logs/laptop-exec-20260722.log
  [ -f "$f" ] && echo "HAS $u $(wc -l <"$f") lines"
done
echo __DONE__
'@
[IO.File]::WriteAllText($localSh, $script.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding $false))
& scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $localSh ($target + ':' + $remoteSh)
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh.exe'
$psi.Arguments = "-o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no $target `"sudo -S -p '' bash $remoteSh; rm -f $remoteSh`""
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [Diagnostics.Process]::Start($psi)
$p.StandardInput.WriteLine($pw)
$p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
[void]$p.WaitForExit(60000)
Write-Output $out
Remove-Item -Force $localSh -EA SilentlyContinue
