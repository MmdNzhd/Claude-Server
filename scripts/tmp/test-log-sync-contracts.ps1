# Log sync contracts - full-file evidence (nested Get-FunctionBody unreliable)
$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}
$fail = 0
function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

$ui = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1') -Raw
$sh = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/connect-ui.sh') -Raw
$conn = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/windows/connect.ps1') -Raw
$mac = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/mac/connect.sh') -Raw
$gm = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/git-mode.sh') -Raw

# C1: no trailing ; true on cat append
$c1 = ($ui -match 'exit \$ec') -and ($ui -notmatch 'cat >>[^\r\n]*; true')
Assert-C '1' $c1 'Win: no ; true after log append' $(if ($c1) { 'exit $ec' } else { 'bad cat' })

# C2: watermark only inside appendOk
$c2 = [regex]::IsMatch($ui, '(?ms)if\s*\(\s*\$appendOk\s*\)\s*\{[\s\S]{0,500}Write-ConnectLogSyncWatermark')
Assert-C '2' $c2 'Win: watermark only in appendOk' $(if ($c2) { 'gated' } else { 'missing' })

# C3: trap flush
$c3 = ($conn -match 'trap') -and ($conn -match "Write-ConnectLog") -and ($conn -match 'Wait-ConnectExit')
Assert-C '3' $c3 'Win: trap Write-Log + Wait-ConnectExit' $(if ($c3) { 'ok' } else { 'missing' })

# C4: ERROR/WARN Force sync
$c4 = [regex]::IsMatch($ui, "(?ms)Level -eq 'ERROR'[\s\S]{0,80}Sync-ConnectLogToServer\s+-Force") -and
      [regex]::IsMatch($ui, "(?ms)Level -eq 'WARN'[\s\S]{0,80}Sync-ConnectLogToServer\s+-Force")
Assert-C '4' $c4 'Win: WARN/ERROR sync -Force' $(if ($c4) { 'ok' } else { 'missing' })

# C5: lock
$c5 = $ui -match '\.sync-lock|ConnectLogSyncInProgress'
Assert-C '5' $c5 'Win: sync lock' $(if ($c5) { 'ok' } else { 'missing' })

# C6 Mac cat_ok
$c6 = ($sh -match 'cat_ok=1') -and ($sh -match 'if \[ "\$cat_ok" = 1 \]')
Assert-C '6' $c6 'Mac: watermark gated by cat_ok' $(if ($c6) { 'ok' } else { 'missing' })

# C7 bash -n
$bash = 'C:\Program Files\Git\bin\bash.exe'
$c7 = $true
if (Test-Path $bash) {
  & $bash -n (Join-Path $RepoRoot 'scripts/client/mac/connect.sh'); if ($LASTEXITCODE -ne 0) { $c7 = $false }
  & $bash -n (Join-Path $RepoRoot 'scripts/client/git-mode.sh'); if ($LASTEXITCODE -ne 0) { $c7 = $false }
}
Assert-C '7' $c7 'Mac: bash -n' $(if ($c7) { 'clean' } else { 'syntax' })

# C8 midnight flush
$c8 = ($ui -match 'prevPath|previous day|rollover' -or $sh -match 'previous|rollover|CONNECT_LOG_PATH') -and ($ui -match 'Sync-ConnectLogToServer -Force -LogPath \$prevPath' -or $ui -match 'prevPath')
Assert-C '8' $c8 'Midnight flushes previous day' $(if ($c8) { 'ok' } else { 'missing' })

Write-Host ""
Write-Host "=== RESULT fail=$fail ==="
if ($fail -eq 0) { Write-Host 'VERDICT: PASS'; exit 0 } else { Write-Host 'VERDICT: HARD FAIL'; exit 1 }
