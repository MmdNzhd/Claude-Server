#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$cand = @(
  'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1',
  (Join-Path (Get-Location) 'publish\sepidz-deploy.local.ps1')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $cand) { throw 'sepidz-deploy.local.ps1 not found' }
$raw = Get-Content -LiteralPath $cand -Raw
# IMPORTANT: single-quoted regex so $Sepidz* is not expanded by PowerShell
$pw = [regex]::Match($raw, '(?m)^\s*\$SepidzSudoPassword\s*=\s*''([^'']*)''').Groups[1].Value
$sshUser = 'sepidz'
$serverIp = '192.168.250.70'
$mu = [regex]::Match($raw, '(?m)^\s*\$SepidzSshUser\s*=\s*''([^'']*)''')
$mh = [regex]::Match($raw, '(?m)^\s*\$SepidzServerIp\s*=\s*''([^'']*)''')
if ($mu.Success) { $sshUser = $mu.Groups[1].Value }
if ($mh.Success) { $serverIp = $mh.Groups[1].Value }
if ([string]::IsNullOrWhiteSpace($pw)) { throw 'empty password' }
if ($sshUser -ne 'sepidz') { throw "expected ssh user sepidz, got $sshUser" }
Write-Host "target=$sshUser@$serverIp pw_len=$($pw.Length)"
$target = "$sshUser@$serverIp"

$remoteCmd = @'
set +e
echo ===HOST===
hostname; date; whoami; id
echo ===LE===
ls -la /usr/local/bin/laptop-exec 2>&1
wc -c /usr/local/bin/laptop-exec 2>&1
grep -c _le_audit /usr/local/bin/laptop-exec 2>/dev/null || echo audit_markers=0
echo ===HOOKS_GOLDEN===
ls /usr/local/lib/claude-server/cursor-hooks/ 2>&1
echo ===SMART_HOOKS===
ls -la /home/smart/.cursor/hooks/ 2>&1
echo ===SEPIDZ_HOOKS===
ls -la /home/sepidz/.cursor/hooks/ 2>&1
echo ===LOGS_SMART===
ls -la /home/smart/.claude/logs/ 2>&1 | tail -15
echo ===LOGS_SEPIDZ===
ls -la /home/sepidz/.claude/logs/ 2>&1 | tail -15
echo ===TODAY===
for u in smart sepidz; do
  for f in connect-20260722.log laptop-exec-20260722.log; do
    p=/home/$u/.claude/logs/$f
    if [ -f "$p" ]; then echo "HAS $p $(wc -c <"$p")b"; else echo "NO $p"; fi
  done
done
echo ===RECENT_WARN_SMART===
f=/home/smart/.claude/logs/connect-20260722.log
[ -f "$f" ] || f=$(ls -1t /home/smart/.claude/logs/connect-*.log 2>/dev/null | head -1)
if [ -n "$f" ] && [ -f "$f" ]; then echo FILE=$f; grep -E '\[ERROR\]|\[WARN\]' "$f" | tail -15; else echo none; fi
echo ===RECENT_WARN_SEPIDZ===
f=/home/sepidz/.claude/logs/connect-20260722.log
[ -f "$f" ] || f=$(ls -1t /home/sepidz/.claude/logs/connect-*.log 2>/dev/null | head -1)
if [ -n "$f" ] && [ -f "$f" ]; then echo FILE=$f; grep -E '\[ERROR\]|\[WARN\]' "$f" | tail -15; else echo none; fi
echo ===TUNNELS===
ss -lnt 2>/dev/null | grep -E ':200[0-9]{2}' | head -20 || true
'@

$localSh = Join-Path $env:TEMP ('sepidz-probe-' + [guid]::NewGuid().ToString('n') + '.sh')
$remoteSh = '/home/sepidz/sepidz-sudo-run.sh'
try {
  $body = "#!/bin/bash`nset +e`n$remoteCmd`necho __DONE__`n"
  [IO.File]::WriteAllText($localSh, $body.Replace("`r`n", "`n").Replace("`r", "`n"), (New-Object Text.UTF8Encoding $false))
  & scp -o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no -o ControlPath=none -q $localSh "${target}:${remoteSh}"
  if ($LASTEXITCODE -ne 0) { throw "scp failed exit=$LASTEXITCODE" }

  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'ssh.exe'
  $psi.Arguments = "-n -o BatchMode=yes -o ConnectTimeout=20 -o ControlMaster=no -o ControlPath=none $target `"printf '%s\n' '$pw' | sudo -S -p '' bash $remoteSh; rm -f $remoteSh`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $deadline = [datetime]::UtcNow.AddSeconds(75)
  $gotDone = $false
  while ([datetime]::UtcNow -lt $deadline) {
    while (-not $p.StandardOutput.EndOfStream) {
      $line = $p.StandardOutput.ReadLine()
      if ($null -eq $line) { break }
      [Console]::Out.WriteLine($line)
      if ($line -match '__DONE__') { $gotDone = $true; break }
    }
    if ($gotDone -or $p.HasExited) { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $p.HasExited) { try { $p.Kill() } catch {} }
  $err = $p.StandardError.ReadToEnd()
  if ($err) {
    foreach ($line in ($err -split "`n")) {
      if ($line -and ($line -notmatch '(?i)password')) { [Console]::Error.WriteLine($line) }
    }
  }
  if (-not $gotDone) { exit 1 }
  exit 0
} finally {
  Remove-Item -Force -LiteralPath $localSh -ErrorAction SilentlyContinue
}
