#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location 'D:\Smart\Claude-Code-Server'
$raw = Get-Content -LiteralPath 'publish\sepidz-deploy.local.ps1' -Raw
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$sshUser = [regex]::Match($raw, '(?m)^\s*\$SepidzSshUser\s*=\s*''([^'']*)''').Groups[1].Value
if (-not $sshUser) { $sshUser = 'sepidz' }
if (-not $pw) { throw 'empty password' }
Write-Output ("ssh_user=$sshUser pw_len=" + $pw.Length)
$target = "$sshUser@192.168.250.70"
$remoteSh = "/home/$sshUser/sepidz-sudo-run.sh"
$localSh = Join-Path $env:TEMP ('sepidz-mcp-' + [guid]::NewGuid().ToString('n') + '.sh')
$script = @'
#!/bin/bash
set +e
echo ===HOST===
hostname; date; whoami; id
echo ===LE===
ls -la /usr/local/bin/laptop-exec; wc -c /usr/local/bin/laptop-exec
grep -c _le_audit /usr/local/bin/laptop-exec || echo audit=0
echo ===HOOKS===
ls /usr/local/lib/claude-server/cursor-hooks/ 2>&1
ls /home/sepidz/.cursor/hooks/ 2>&1
ls /home/smart/.cursor/hooks/ 2>&1
echo ===TODAY===
for u in smart sepidz; do
  for f in connect-20260722.log laptop-exec-20260722.log; do
    p=/home/$u/.claude/logs/$f
    if [ -f "$p" ]; then echo HAS $p $(wc -c <"$p"); else echo NO $p; fi
  done
done
echo ===LOGS_SEPIDZ===
ls -la /home/sepidz/.claude/logs/ 2>&1 | tail -20
echo ===LOGS_SMART===
ls -la /home/smart/.claude/logs/ 2>&1 | tail -12
echo ===WARN_SEPIDZ===
f=$(ls -1t /home/sepidz/.claude/logs/connect-*.log 2>/dev/null | head -1)
[ -n "$f" ] && { echo FILE=$f; grep -E '\[ERROR\]|\[WARN\]' "$f" | tail -15; } || echo none
echo ===WARN_SMART===
f=$(ls -1t /home/smart/.claude/logs/connect-*.log 2>/dev/null | head -1)
[ -n "$f" ] && { echo FILE=$f; grep -E '\[ERROR\]|\[WARN\]' "$f" | tail -15; } || echo none
echo ===TUNNELS===
ss -lnt 2>/dev/null | grep -E ':200[0-9]{2}' | head -15
echo __DONE__
'@
[IO.File]::WriteAllText($localSh, $script.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding $false))
& scp -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no -q $localSh "${target}:${remoteSh}"
if ($LASTEXITCODE -ne 0) { throw "scp failed" }
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
if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; throw 'timeout' }
Write-Output $out
foreach ($line in ($err -split "`n")) {
  if ($line -and ($line -notmatch '(?i)password')) { Write-Output ("ERR: " + $line) }
}
if ($out -notmatch '__DONE__') { throw ("no DONE exit=" + $p.ExitCode) }
Remove-Item -Force $localSh -EA SilentlyContinue
