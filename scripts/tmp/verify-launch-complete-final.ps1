$ErrorActionPreference = 'Continue'
$fail = 0; $warn = 0
function Ok($m) { Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Warn($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:warn++ }

$repo = 'D:\Smart\Claude-Code-Server'
$expectVer = '20260715.18'
$ban = "pre_launch_agent_or_new_window' -Force"

Write-Host "`n=== CRITICAL PATHS (must be fixed) ===" -ForegroundColor Cyan
$critical = @(
  "$repo\scripts\client\editor-launch.ps1",
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\editor-launch.ps1',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\editor-launch.ps1'
)
foreach ($p in $critical) {
  if (-not (Test-Path $p)) { Bad "missing $p"; continue }
  $r = Get-Content $p -Raw
  $ok = ($r -match 'preserve_open_windows') -and ($r -notmatch [regex]::Escape($ban)) -and ($r -match 'LAUNCH_RETRY_NO_KILL')
  if ($ok) { Ok $p.Replace('C:\Users\Smart\Desktop\claude-publish\','DESKTOP\').Replace("$repo\",'REPO\') }
  else { Bad "not fixed: $p" }
}

Write-Host "`n=== VERSIONS ===" -ForegroundColor Cyan
foreach ($p in @(
  "$repo\scripts\client\windows\connect-version.txt",
  "$repo\scripts\client\mac\connect-version.txt",
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect-version.txt',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect-version.txt'
)) {
  $v = (Get-Content $p -Raw).Trim()
  if ($v -eq $expectVer) { Ok "$(Split-Path (Split-Path $p -Parent) -Leaf)\...\connect-version.txt = $v" }
  else { Bad "$p = $v" }
}
# Sepidz IP integrity
$sepPs1 = Get-Content 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect.ps1' -Raw
if ($sepPs1 -match '192\.168\.250\.70' -and $sepPs1 -notmatch '192\.168\.210\.240') { Ok 'Sepidz connect.ps1 IP intact' }
else { Bad 'Sepidz IP broken' }
$smartPs1 = Get-Content 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.ps1' -Raw
if ($smartPs1 -match '192\.168\.210\.240' -and $smartPs1 -notmatch '192\.168\.250\.70') { Ok 'Smart connect.ps1 IP intact' }
else { Bad 'Smart IP broken' }

Write-Host "`n=== SHA256 repo <-> Desktop Smart ===" -ForegroundColor Cyan
foreach ($pair in @(
  @{ R='scripts\client\editor-launch.ps1'; D='editor-launch.ps1' },
  @{ R='scripts\client\windows\connect.ps1'; D='connect.ps1' },
  @{ R='scripts\client\windows\connect-version.txt'; D='connect-version.txt' }
)) {
  $rh=(Get-FileHash "$repo\$($pair.R)" -Algorithm SHA256).Hash
  $dh=(Get-FileHash "C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\$($pair.D)" -Algorithm SHA256).Hash
  if ($rh -eq $dh) { Ok "match $($pair.D)" } else { Bad "mismatch $($pair.D)" }
}

Write-Host "`n=== SHA256 repo editor-launch <-> Sepidz Desktop ===" -ForegroundColor Cyan
$rh=(Get-FileHash "$repo\scripts\client\editor-launch.ps1" -Algorithm SHA256).Hash
$dh=(Get-FileHash 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\editor-launch.ps1' -Algorithm SHA256).Hash
if ($rh -eq $dh) { Ok 'Sepidz editor-launch matches repo' } else { Bad 'Sepidz editor-launch differs' }

Write-Host "`n=== STALE packages (must NOT use) ===" -ForegroundColor Cyan
Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Directory | ForEach-Object {
  if ($_.Name -match '20260715$') { return }
  Warn "STALE do-not-use: $($_.Name)"
}

Write-Host "`n=== SCOPED KILLS / SAFETY ===" -ForegroundColor Cyan
$gm = Get-Content "$repo\scripts\client\git-mode.ps1" -Raw
$el = Get-Content "$repo\scripts\client\editor-launch.ps1" -Raw
$auth = Get-Content "$repo\scripts\client\cursor-auth-laptop.ps1" -Raw
if ($gm -match 'Stop-RemoteEditor' -and $gm -notmatch 'Stop-CursorServerProfileTree') { Ok 'mount clear only path-scoped' } else { Bad 'git-mode kill scope' }
if ($auth -notmatch 'Stop-CursorServerProfileTree|Stop-Process') { Ok 'auth merge never kills Cursor' } else { Bad 'auth kills' }
if ($el -match '\$useNewWindow = \(\$agentHome -or \$hasProfileWindow\)') { Ok 'new-window still used' } else { Bad 'new-window lost' }

Write-Host "`n=== TESTS ===" -ForegroundColor Cyan
Push-Location $repo
foreach ($t in @('test-editor-launch-strategies.ps1','test-editor-launch.ps1','test-connect-pipeline.ps1')) {
  $tp = Join-Path $repo "scripts\client\tests\$t"
  & $tp *>$null
  if ($LASTEXITCODE -eq 0) { Ok "$t" } else { Bad "$t exit=$LASTEXITCODE" }
}
Pop-Location

Write-Host "`n=== LIVE ===" -ForegroundColor Cyan
Ok ("Cursor procs={0}" -f @(Get-Process Cursor -EA SilentlyContinue).Count)
$tun = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match '-R (21\d{3}):localhost:22' }
if ($tun) { Ok "tunnel $($Matches[0])" } else { Warn 'no reverse tunnel now' }

Write-Host "`n==============================" -ForegroundColor Cyan
if ($fail -eq 0) {
  Write-Host "COMPLETE: ALL CRITICAL CHECKS PASSED ($warn stale-package warning(s))" -ForegroundColor Green
  Write-Host "Use ONLY:" -ForegroundColor Green
  Write-Host "  Desktop\claude-publish\claude-code-client-20260715\windows\connect.bat" -ForegroundColor White
  Write-Host "  Desktop\claude-publish\claude-code-sepidz-20260715\claude-code\windows\connect.bat" -ForegroundColor White
  exit 0
}
Write-Host "COMPLETE FAIL: $fail / warn $warn" -ForegroundColor Red
exit 1
