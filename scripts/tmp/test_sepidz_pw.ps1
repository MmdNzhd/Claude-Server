$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. "$root\publish\Get-DeployCredentials.ps1"

$fail = 0
function OK($m){ Write-Host "OK  $m" }
function FAIL($m){ Write-Host "FAIL $m"; $script:fail++ }

# 1) password loads
$pw = Get-SepidzSudoPassword
if ([string]::IsNullOrWhiteSpace($pw)) { FAIL 'Get-SepidzSudoPassword empty' }
elseif ($pw.Length -lt 4) { FAIL ("password too short len={0}" -f $pw.Length) }
else { OK ("Get-SepidzSudoPassword len={0}" -f $pw.Length) }

# 2) hardcoded present in sources (not printing value)
$cred = Get-Content "$root\publish\Get-DeployCredentials.ps1" -Raw
$dep  = Get-Content "$root\publish\deploy-client-bundles.ps1" -Raw
$loc  = Get-Content "$root\publish\sepidz-deploy.local.ps1" -Raw
if ($cred -match "return 'sepidz@Admin'") { OK 'hardcoded in Get-DeployCredentials.ps1' } else { FAIL 'missing hardcode in Get-DeployCredentials.ps1' }
if ($dep -match "sepidz@Admin") { OK 'hardcoded fallback in deploy-client-bundles.ps1' } else { FAIL 'missing hardcode in deploy-client-bundles.ps1' }
if ($loc -match "SepidzSudoPassword\s*=\s*'sepidz@Admin'") { OK 'present in sepidz-deploy.local.ps1' } else { FAIL 'missing in sepidz-deploy.local.ps1' }

# 3) live sudo on Sepidz with that password (non-interactive) — never echo password
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$lines = @(
  '#!/bin/bash',
  'set -e',
  ('PW=$(echo {0} | base64 -d)' -f $pwB64),
  'printf ''%s\n'' "$PW" | sudo -S -p '''' -v',
  'echo SUDO_AUTH_OK',
  'printf ''%s\n'' "$PW" | sudo -S -p '''' id -u',
  'printf ''%s\n'' "$PW" | sudo -S -p '''' cat /usr/local/share/claude-client/connect-version.txt',
  'echo DONE'
)
$wrap = ($lines -join "`n") + "`n"
[IO.File]::WriteAllBytes("$env:TEMP\test_sep_sudo.sh", [Text.Encoding]::UTF8.GetBytes($wrap))
scp -o BatchMode=yes -o ControlMaster=no -q "$env:TEMP\test_sep_sudo.sh" 'sepidz@192.168.250.70:/tmp/test_sep_sudo.sh'

$out = "$env:TEMP\test_sep_sudo_out.txt"
$p = Start-Process ssh -ArgumentList @(
  '-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ControlMaster=no',
  'sepidz@192.168.250.70','bash /tmp/test_sep_sudo.sh'
) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(45000)) {
  try { $p.Kill() } catch {}
  FAIL 'live sudo TIMEOUT'
} else {
  $txt = if (Test-Path $out) { Get-Content $out -Raw } else { '' }
  $err = if (Test-Path "$out.err") { Get-Content "$out.err" -Raw } else { '' }
  # redact any accidental password echo
  $safe = ($txt + "`n" + $err) -replace [regex]::Escape($pw), '***'
  Write-Host '--- remote ---'
  Write-Host $safe
  if ($txt -match 'SUDO_AUTH_OK' -and $txt -match 'DONE' -and $p.ExitCode -eq 0) {
    OK 'live sudo auth on Sepidz'
  } else {
    FAIL ("live sudo failed exit={0}" -f $p.ExitCode)
  }
  if ($txt -match '20260718\.1') { OK 'Sepidz bundle still 20260718.1' }
  else { Write-Host ("NOTE bundle line: {0}" -f (($txt -split "`n" | Select-Object -Last 5) -join ' | ')) }
}

# 4) Smart untouched
$sout = "$env:TEMP\smart_chk_pw.txt"
$p2 = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','smart@192.168.210.240',"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $sout -RedirectStandardError "$sout.err"
[void]$p2.WaitForExit(15000)
$sv = if (Test-Path $sout) { (Get-Content $sout -Raw).Trim() } else { '?' }
if ($sv -eq '20260717.22') { OK "Smart still frozen $sv" } else { FAIL "Smart unexpected $sv" }

Write-Host '======== RESULT ========'
Write-Host "fail=$fail"
if ($fail -ne 0) { Write-Host 'PW_TEST_RED'; exit 1 }
Write-Host 'PW_TEST_GREEN'
exit 0
