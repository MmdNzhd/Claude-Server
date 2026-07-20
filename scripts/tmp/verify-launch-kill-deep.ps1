$ErrorActionPreference = 'Continue'
$fail = 0
$warn = 0
function Ok($m) { Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Warn($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:warn++ }

$repo = 'D:\Smart\Claude-Code-Server'
$expectVer = '20260715.18'
$bannedForce = "pre_launch_agent_or_new_window' -Force"
$bannedRetry = 'retry_before_$'

Write-Host "`n======== A) All editor-launch.ps1 copies ========" -ForegroundColor Cyan
$copies = @(Get-ChildItem -Path $repo, 'C:\Users\Smart\Desktop\claude-publish' -Recurse -Filter 'editor-launch.ps1' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\node_modules\\|\\\.git\\' })
if ($copies.Count -eq 0) { Bad 'no editor-launch.ps1 found' }
foreach ($c in $copies) {
  $raw = Get-Content $c.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $raw) { Bad "unreadable $($c.FullName)"; continue }
  $hasPreserve = $raw -match 'preserve_open_windows'
  $hasBad = $raw -match [regex]::Escape($bannedForce)
  $hasRetryKill = $raw -match 'Stop-CursorServerProfileTreeIfNeeded -Reason "retry_before_'
  $label = $c.FullName.Replace($repo + '\', 'REPO\').Replace('C:\Users\Smart\Desktop\claude-publish\', 'DESKTOP\')
  if ($hasBad) { Bad "$label has pre_launch Force kill" }
  elseif ($hasRetryKill) { Bad "$label has retry Force kill" }
  elseif (-not $hasPreserve -and $label -match 'REPO\\|DESKTOP\\claude-code-client-20260715') { Bad "$label missing preserve_open_windows" }
  elseif (-not $hasPreserve) { Warn "$label is older copy (no preserve) - OK if unused" }
  else { Ok "$label OK (preserve, no force)" }
}

Write-Host "`n======== B) Version consistency ========" -ForegroundColor Cyan
$verPaths = @(
  'scripts\client\windows\connect-version.txt',
  'scripts\client\windows\connect.ps1',
  'scripts\client\mac\connect.sh',
  'scripts\client\mac\connect-version.txt'
)
foreach ($rel in $verPaths) {
  $p = Join-Path $repo $rel
  if (-not (Test-Path $p)) {
    if ($rel -eq 'scripts\client\mac\connect-version.txt') {
      # may be published copy only from windows
      Warn "optional missing $rel"
      continue
    }
    Bad "missing $rel"; continue
  }
  $t = Get-Content $p -Raw
  if ($t -match [regex]::Escape($expectVer)) { Ok "$rel has $expectVer" }
  else { Bad "$rel missing $expectVer" }
}
# bat must not hardcode old version that blocks .18
$bat = Join-Path $repo 'scripts\client\windows\connect.bat'
$batRaw = Get-Content $bat -Raw
if ($batRaw -match 'connect-version\.txt') { Ok 'connect.bat reads connect-version.txt' } else { Bad 'connect.bat version guard' }
if ($batRaw -match '20260715\.17' -and $batRaw -notmatch '20260715\.18') { Warn 'connect.bat mentions .17 literally' }

Write-Host "`n======== C) Desktop Smart package deep ========" -ForegroundColor Cyan
$desk = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows'
$need = @('connect.bat','connect.ps1','connect-version.txt','editor-launch.ps1','git-mode.ps1','connect-ui.ps1','connect-update.ps1','cursor-auth-laptop.ps1')
foreach ($n in $need) {
  $p = Join-Path $desk $n
  if (Test-Path $p) { Ok "Desktop has $n" } else { Bad "Desktop missing $n" }
}
$dVer = (Get-Content (Join-Path $desk 'connect-version.txt') -Raw).Trim()
if ($dVer -eq $expectVer) { Ok "Desktop connect-version = $dVer" } else { Bad "Desktop ver=$dVer" }
# connect.ps1 ConnectVersion
$dPs1 = Get-Content (Join-Path $desk 'connect.ps1') -Raw
if ($dPs1 -match [regex]::Escape("ConnectVersion = '$expectVer'")) { Ok 'Desktop connect.ps1 ConnectVersion' } else { Bad 'Desktop connect.ps1 version' }
# hashes for critical trio
foreach ($pair in @(
  @{ Name='editor-launch.ps1'; Repo='scripts\client\editor-launch.ps1'; Desk='editor-launch.ps1' },
  @{ Name='connect.ps1'; Repo='scripts\client\windows\connect.ps1'; Desk='connect.ps1' },
  @{ Name='connect-version.txt'; Repo='scripts\client\windows\connect-version.txt'; Desk='connect-version.txt' }
)) {
  $rh = (Get-FileHash (Join-Path $repo $pair.Repo) -Algorithm SHA256).Hash
  $dh = (Get-FileHash (Join-Path $desk $pair.Desk) -Algorithm SHA256).Hash
  if ($rh -eq $dh) { Ok "SHA256 match $($pair.Name)" } else { Bad "SHA256 MISMATCH $($pair.Name)" }
}

Write-Host "`n======== D) Other Desktop packages (stale?) ========" -ForegroundColor Cyan
Get-ChildItem 'C:\Users\Smart\Desktop\claude-publish' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $v = Join-Path $_.FullName 'windows\connect-version.txt'
  $elp = Join-Path $_.FullName 'windows\editor-launch.ps1'
  if (-not (Test-Path $v)) {
    $v2 = Join-Path $_.FullName 'claude-code\windows\connect-version.txt'
    $elp2 = Join-Path $_.FullName 'claude-code\windows\editor-launch.ps1'
    if (Test-Path $v2) { $v=$v2; $elp=$elp2 }
  }
  if (Test-Path $v) {
    $vv = (Get-Content $v -Raw).Trim()
    $has = $false
    if (Test-Path $elp) { $has = (Get-Content $elp -Raw) -match 'preserve_open_windows' }
    if ($_.Name -eq 'claude-code-client-20260715' -and $vv -eq $expectVer -and $has) {
      Ok "$($_.Name) ready v$vv + fix"
    } elseif ($has -and $vv -eq $expectVer) {
      Ok "$($_.Name) v$vv + fix"
    } else {
      Warn "$($_.Name) v$vv preserve=$has (do not use if stale)"
    }
  }
}

Write-Host "`n======== E) Related kill paths (must stay scoped) ========" -ForegroundColor Cyan
$gm = Get-Content (Join-Path $repo 'scripts\client\git-mode.ps1') -Raw
# Clear-SessionMount must only Stop-RemoteEditor for THAT path, not profile tree
if ($gm -match 'Stop-RemoteEditor' -and $gm -notmatch 'Stop-CursorServerProfileTree') {
  Ok 'Clear-SessionMount uses Stop-RemoteEditor only (path-scoped)'
} else { Bad 'git-mode Clear-SessionMount kill scope unexpected' }
if ($gm -match 'ORPHAN_TUNNEL') { Ok 'ORPHAN_TUNNEL still exists (tunnel recycle - expected)' } else { Warn 'ORPHAN_TUNNEL missing' }

$elSrc = Get-Content (Join-Path $repo 'scripts\client\editor-launch.ps1') -Raw
# Stop-RemoteEditor must still soft-close path windows only
if ($elSrc -match 'function Stop-RemoteEditor') { Ok 'Stop-RemoteEditor still present (path-only)' } else { Bad 'Stop-RemoteEditor missing' }
# Auth merge must not kill
$auth = Join-Path $repo 'scripts\client\cursor-auth-laptop.ps1'
if (Test-Path $auth) {
  $ar = Get-Content $auth -Raw
  if ($ar -match 'Stop-Process|Stop-CursorServerProfileTree') { Bad 'cursor-auth-laptop kills processes' }
  else { Ok 'cursor-auth-laptop does not kill Cursor' }
}

Write-Host "`n======== F) Parse all launch-related scripts ========" -ForegroundColor Cyan
$toParse = @(
  'scripts\client\editor-launch.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\windows\connect.ps1',
  'scripts\client\cursor-auth-laptop.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\tests\test-editor-launch-strategies.ps1',
  'scripts\client\tests\test-editor-launch.ps1'
)
foreach ($rel in $toParse) {
  $p = Join-Path $repo $rel
  if (-not (Test-Path $p)) { Warn "skip missing $rel"; continue }
  $e = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
  if ($e) { Bad "parse $rel :: $($e[0].Message)" } else { Ok "parse $(Split-Path $rel -Leaf)" }
}

Write-Host "`n======== G) Regression tests ========" -ForegroundColor Cyan
Push-Location $repo
foreach ($t in @(
  'scripts\client\tests\test-editor-launch-strategies.ps1',
  'scripts\client\tests\test-editor-launch.ps1',
  'scripts\client\tests\test-connect-pipeline.ps1'
)) {
  $tp = Join-Path $repo $t
  if (-not (Test-Path $tp)) { Warn "missing $t"; continue }
  Write-Host "--- running $(Split-Path $t -Leaf) ---" -ForegroundColor DarkCyan
  & $tp
  if ($LASTEXITCODE -ne 0) { Bad "$(Split-Path $t -Leaf) FAILED exit=$LASTEXITCODE" }
  else { Ok "$(Split-Path $t -Leaf) ALL PASS" }
}
Pop-Location

Write-Host "`n======== H) Live process / tunnel sanity ========" -ForegroundColor Cyan
$cursor = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)
Ok ("Cursor processes running: {0}" -f $cursor.Count)
$tunnel = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match '-R 21\d{3}:localhost:22' }
if ($tunnel) {
  foreach ($t in $tunnel) {
    if ($t.CommandLine -match '-R (21\d{3})') { Ok "reverse tunnel up port=$($Matches[1]) pid=$($t.ProcessId)" }
  }
} else { Warn 'no reverse tunnel (-R 21xxx) currently (OK if connect not running)' }

Write-Host "`n======== SUMMARY ========" -ForegroundColor Cyan
if ($fail -eq 0) {
  Write-Host "ALL CRITICAL CHECKS PASSED ($warn warning(s))" -ForegroundColor Green
  exit 0
}
Write-Host "$fail FAIL / $warn WARN" -ForegroundColor Red
exit 1
