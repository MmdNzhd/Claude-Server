$ErrorActionPreference = 'Stop'
$fail = 0
function Ok($m) { Write-Host "OK  $m" -ForegroundColor Green }
function Bad($m) { Write-Host "FAIL $m" -ForegroundColor Red; $script:fail++ }

$repo = 'D:\Smart\Claude-Code-Server'
$el = Join-Path $repo 'scripts\client\editor-launch.ps1'
$verFile = Join-Path $repo 'scripts\client\windows\connect-version.txt'
$ps1 = Join-Path $repo 'scripts\client\windows\connect.ps1'
$sh = Join-Path $repo 'scripts\client\mac\connect.sh'
$desk = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows'
$expectVer = '20260715.18'

Write-Host '=== 1) Syntax ===' -ForegroundColor Cyan
foreach ($f in @($el, $ps1, (Join-Path $repo 'scripts\client\tests\test-editor-launch-strategies.ps1'))) {
  $e = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e)
  if ($e) { Bad "syntax $f :: $($e[0])" } else { Ok "syntax $(Split-Path $f -Leaf)" }
}

Write-Host "`n=== 2) Version sync ===" -ForegroundColor Cyan
$ver = (Get-Content $verFile -Raw).Trim()
if ($ver -eq $expectVer) { Ok "connect-version.txt = $ver" } else { Bad "connect-version.txt=$ver expected $expectVer" }
$ps1Raw = Get-Content $ps1 -Raw
if ($ps1Raw -match [regex]::Escape("ConnectVersion = '$expectVer'")) { Ok "connect.ps1 ConnectVersion" } else { Bad 'connect.ps1 version' }
$shRaw = Get-Content $sh -Raw
if ($shRaw -match [regex]::Escape("CONNECT_VERSION='$expectVer'")) { Ok "connect.sh CONNECT_VERSION" } else { Bad 'connect.sh version' }

Write-Host "`n=== 3) Kill-fix invariants (repo) ===" -ForegroundColor Cyan
$src = Get-Content $el -Raw
if ($src -match 'preserve_open_windows') { Ok 'preserve_open_windows present' } else { Bad 'preserve_open_windows missing' }
if ($src -match 'LAUNCH_RETRY_NO_KILL') { Ok 'LAUNCH_RETRY_NO_KILL present' } else { Bad 'LAUNCH_RETRY_NO_KILL missing' }
if ($src -match "pre_launch_agent_or_new_window' -Force") { Bad 'pre_launch Force kill STILL present' } else { Ok 'pre_launch Force kill removed' }
if ($src -match 'retry_before_\$\(\$strategy\.Name\)') { Bad 'retry Force kill STILL present' } else { Ok 'retry Force kill removed' }
# ensure Stop-CursorServerProfileTreeIfNeeded still exists (manual recovery) but Launch path skips
if ($src -match 'function Stop-CursorServerProfileTreeIfNeeded') { Ok 'helper kept for manual recovery' } else { Bad 'helper missing' }
if ($src -match 'WARNING=closes_all_profile_windows') { Ok 'Force path warned as dangerous' } else { Bad 'Force warning missing' }
# new-window still used
if ($src -match '\$useNewWindow = \(\$agentHome -or \$hasProfileWindow\)') { Ok 'useNewWindow logic intact' } else { Bad 'useNewWindow logic broken' }

Write-Host "`n=== 4) Desktop package sync ===" -ForegroundColor Cyan
if (-not (Test-Path $desk)) { Bad "Desktop package missing: $desk" }
else {
  $dEl = Join-Path $desk 'editor-launch.ps1'
  $dVer = Join-Path $desk 'connect-version.txt'
  $dPs1 = Join-Path $desk 'connect.ps1'
  foreach ($p in @($dEl,$dVer,$dPs1)) {
    if (Test-Path $p) { Ok "exists $(Split-Path $p -Leaf)" } else { Bad "missing $p" }
  }
  $dv = (Get-Content $dVer -Raw).Trim()
  if ($dv -eq $expectVer) { Ok "Desktop version = $dv" } else { Bad "Desktop version=$dv expected $expectVer" }
  $dSrc = Get-Content $dEl -Raw
  if ($dSrc -match 'preserve_open_windows') { Ok 'Desktop has preserve skip' } else { Bad 'Desktop missing preserve skip' }
  if ($dSrc -match "pre_launch_agent_or_new_window' -Force") { Bad 'Desktop STILL has Force kill' } else { Ok 'Desktop Force kill removed' }
  # binary/same content check for editor-launch
  $repoHash = (Get-FileHash $el -Algorithm SHA256).Hash
  $deskHash = (Get-FileHash $dEl -Algorithm SHA256).Hash
  if ($repoHash -eq $deskHash) { Ok 'Desktop editor-launch.ps1 matches repo (SHA256)' } else { Bad 'Desktop editor-launch differs from repo' }
  $repoPs1Hash = (Get-FileHash $ps1 -Algorithm SHA256).Hash
  $deskPs1Hash = (Get-FileHash $dPs1 -Algorithm SHA256).Hash
  if ($repoPs1Hash -eq $deskPs1Hash) { Ok 'Desktop connect.ps1 matches repo' } else { Bad 'Desktop connect.ps1 differs (version bump may differ relative paths - check)' }
}

Write-Host "`n=== 5) Regression tests ===" -ForegroundColor Cyan
& (Join-Path $repo 'scripts\client\tests\test-editor-launch-strategies.ps1')
if ($LASTEXITCODE -ne 0) { Bad "test-editor-launch-strategies exit=$LASTEXITCODE" } else { Ok 'test-editor-launch-strategies ALL PASS' }

# Also run test-editor-launch if exists
$tel = Join-Path $repo 'scripts\client\tests\test-editor-launch.ps1'
if (Test-Path $tel) {
  & $tel
  if ($LASTEXITCODE -ne 0) { Bad "test-editor-launch exit=$LASTEXITCODE" } else { Ok 'test-editor-launch ALL PASS' }
}

Write-Host "`n=== RESULT ===" -ForegroundColor Cyan
if ($fail -eq 0) { Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green; exit 0 }
Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red; exit 1
