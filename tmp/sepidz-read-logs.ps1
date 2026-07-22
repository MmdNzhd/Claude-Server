#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw = Get-Content -LiteralPath 'publish\sepidz-deploy.local.ps1' -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$sshUser = [regex]::Match($raw, '(?m)^\s*\$SepidzSshUser\s*=\s*''([^'']*)''').Groups[1].Value
if (-not $sshUser) { $sshUser = 'sepidz' }
$target = "$sshUser@192.168.250.70"
$remoteSh = "/home/$sshUser/sepidz-log-read.sh"
$localSh = Join-Path $env:TEMP ('sepidz-log-' + [guid]::NewGuid().ToString('n') + '.sh')
$script = @'
#!/bin/bash
set +e
echo ======== SEPIDZ HOST ========
hostname; date -u; whoami; id
echo --- tunnels ---
ss -lnt 2>/dev/null | grep -E '127\.0\.0\.1:20[0-9]{3}' | head -20
echo --- laptop-exec binary ---
wc -c /usr/local/bin/laptop-exec
grep -c _le_audit /usr/local/bin/laptop-exec || echo audit=0
ls /usr/local/lib/claude-server/cursor-hooks/laptop-exec-audit-log.sh 2>&1
echo --- today logs all users ---
for u in sepidz smart designer aminb hosseinb hosseinm farzadb zahrak alit nimaz; do
  for f in connect-20260722.log laptop-exec-20260722.log; do
    p=/home/$u/.claude/logs/$f
    if [ -f "$p" ]; then echo "HAS $p bytes=$(wc -c <"$p") lines=$(wc -l <"$p")"; fi
  done
done
echo --- sepidz connect WARN/ERROR/multiagent ---
f=/home/sepidz/.claude/logs/connect-20260722.log
if [ -f "$f" ]; then grep -E '\[ERROR\]|\[WARN\]|\[multiagent\]' "$f" | tail -40; else echo NO_SEPIDZ_CONNECT; fi
echo --- sepidz laptop-exec tail ---
f=/home/sepidz/.claude/logs/laptop-exec-20260722.log
if [ -f "$f" ]; then tail -40 "$f"; echo --- counts ---; awk '{print $3,$4,$5}' "$f" | sort | uniq -c | sort -rn | head -25; else echo NO_SEPIDZ_LE; fi
echo --- smart@sepidz connect WARN/ERROR/multiagent ---
f=/home/smart/.claude/logs/connect-20260722.log
if [ -f "$f" ]; then grep -E '\[ERROR\]|\[WARN\]|\[multiagent\]' "$f" | tail -40; else echo NO_SMART_CONNECT_TODAY; ls -lt /home/smart/.claude/logs/connect-*.log 2>/dev/null | head -5; fi
echo --- smart@sepidz laptop-exec ---
f=/home/smart/.claude/logs/laptop-exec-20260722.log
if [ -f "$f" ]; then echo bytes=$(wc -c <"$f"); tail -30 "$f"; else echo NO_SMART_LE_TODAY; fi
echo --- recent connect any user ---
for u in sepidz smart; do
  latest=$(ls -1t /home/$u/.claude/logs/connect-*.log 2>/dev/null | head -1)
  echo USER=$u LATEST=$latest
  [ -n "$latest" ] && { echo size=$(wc -c <"$latest"); grep -E '\[ERROR\]|\[WARN\]' "$latest" | tail -15; }
done
echo --- mux/slots sample ---
ls -la /home/sepidz/.cache/laptop-exec/ 2>&1 | head -20
ls -la /home/smart/.cache/laptop-exec/ 2>&1 | head -20
echo __DONE__
'@
[IO.File]::WriteAllText($localSh, $script.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding $false))
& scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $localSh ($target + ':' + $remoteSh)
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }
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
if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {}; throw 'timeout' }
Write-Output $out
foreach ($line in ($err -split "`n")) {
  if ($line -and ($line -notmatch '(?i)password')) { Write-Output ("ERR: " + $line) }
}
if ($out -notmatch '__DONE__') { throw ("no DONE exit=" + $p.ExitCode) }
Remove-Item -Force $localSh -EA SilentlyContinue
