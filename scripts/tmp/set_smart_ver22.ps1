$ErrorActionPreference = 'Stop'
# Force Smart server client version to 20260717.22 (no spurious auto-update)
$target = '20260717.22'
$out = "$env:TEMP\smart_ver.txt"
$err = "$out.err"
$p = Start-Process ssh -ArgumentList @(
  '-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ConnectionAttempts=1',
  'smart@192.168.210.240',
  "cat /usr/local/share/claude-client/connect-version.txt"
) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $p.WaitForExit(15000)) { try{$p.Kill()}catch{}; throw 'smart version read timeout' }
$cur = if (Test-Path $out) { (Get-Content $out -Raw).Trim() } else { '' }
Write-Host "SMART_BEFORE=$cur"

if ($cur -eq $target) {
  Write-Host "SMART_ALREADY=$target"
  exit 0
}

# write via sudo if available through sudo-from-laptop path, else ssh + tee with sudo
# Prefer: echo version | ssh smart 'sudo tee ...'
# Use Start-Process to avoid hang; passwordless sudo for smart on that host for install paths
$setOut = "$env:TEMP\smart_set.txt"
$cmd = "printf '%s\n' '$target' | sudo tee /usr/local/share/claude-client/connect-version.txt >/dev/null && cat /usr/local/share/claude-client/connect-version.txt"
$p2 = Start-Process ssh -ArgumentList @(
  '-o','BatchMode=yes','-o','ConnectTimeout=8',
  'smart@192.168.210.240', $cmd
) -NoNewWindow -PassThru -RedirectStandardOutput $setOut -RedirectStandardError "$setOut.err"
if (-not $p2.WaitForExit(20000)) { try{$p2.Kill()}catch{}; throw 'smart version set timeout' }
$after = if (Test-Path $setOut) { (Get-Content $setOut -Raw).Trim() } else { '' }
Write-Host "SMART_AFTER=$after"
Write-Host "SSH_EC=$($p2.ExitCode)"
if ($after -ne $target) { throw "failed to set smart version to $target (got '$after')" }
Write-Host "SMART_SET_OK=$target"
