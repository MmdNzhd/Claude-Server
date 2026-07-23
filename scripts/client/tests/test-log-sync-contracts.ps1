# test-log-sync-contracts.ps1 - durable log sync / WARN coalesce contracts (static)
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert-C([string]$id, [bool]$ok, [string]$title, [string]$detail) {
  if ($ok) { Write-Host "PASS  [$id] $title"; Write-Host "      $detail" }
  else { Write-Host "HARD FAIL  [$id] $title"; Write-Host "      $detail"; $script:fail++ }
}

function Get-BalancedBlock {
  param([string]$Text, [string]$StartPattern)
  $m = [regex]::Match($Text, $StartPattern)
  if (-not $m.Success) { return '' }
  $start = $m.Index
  $i = $Text.IndexOf('{', $start)
  if ($i -lt 0) {
    # bash function name() { ... }
    $i = $Text.IndexOf('{', $start)
  }
  if ($i -lt 0) { return '' }
  $depth = 0
  for ($p = $i; $p -lt $Text.Length; $p++) {
    $ch = $Text[$p]
    if ($ch -eq '{') { $depth++ }
    elseif ($ch -eq '}') {
      $depth--
      if ($depth -eq 0) { return $Text.Substring($start, $p - $start + 1) }
    }
  }
  return ''
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1'))) {
  $RepoRoot = 'D:\Smart\Claude-Code-Server'
}

$ui = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/connect-ui.ps1') -Raw
$sh = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/connect-ui.sh') -Raw
$conn = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/windows/connect.ps1') -Raw
$mac = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts/client/mac/connect.sh') -Raw

Write-Host '=== log sync contracts (WARN coalesce + session-end Force) ==='
Write-Host ("root={0}" -f $RepoRoot)
Write-Host ''

$c1 = ($ui -match 'exit \$ec') -and ($ui -notmatch 'cat >>[^\r\n]*; true')
Assert-C '1' $c1 'Win: no ; true after log append' $(if ($c1) { 'exit $ec' } else { 'bad cat' })

$c2 = [regex]::IsMatch($ui, '(?ms)if\s*\(\s*\$appendOk\s*\)\s*\{[\s\S]{0,500}Write-ConnectLogSyncWatermark')
Assert-C '2' $c2 'Win: watermark only in appendOk' $(if ($c2) { 'gated' } else { 'missing' })

$c3 = ($conn -match 'trap') -and ($conn -match 'Write-ConnectLog') -and ($conn -match 'Wait-ConnectExit')
Assert-C '3' $c3 'Win: trap Write-Log + Wait-ConnectExit' $(if ($c3) { 'ok' } else { 'missing' })

$wc = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Write-ConnectLog\b'
$c4Err = ($wc -match "Level -eq 'ERROR'") -and ($wc -match 'Complete-ConnectLogAsyncDrain\s+-Force')
$c4Warn = ($wc -match "Level -eq 'WARN'") -and ($wc -match 'ConnectLogWarnPendingUntil') -and ($wc -match 'Request-ConnectLogSync')
Assert-C '4' ($c4Err -and $c4Warn) 'Win: ERROR Force; WARN Request-ConnectLogSync coalesce' $(if ($c4Err -and $c4Warn) { 'ERROR Force + WARN coalesce' } else { 'missing async WARN path' })

$c5 = ($ui -match 'LOG_SYNC_ASYNC scheduled=1') -and ($ui -match 'function Request-ConnectLogSync')
Assert-C '5' $c5 'Win: Request-ConnectLogSync + LOG_SYNC_ASYNC' $(if ($c5) { 'ok' } else { 'missing' })

$wait = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Wait-ConnectExit\b'
$close = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Close-ConnectLog\b'
$c6 = ($wait -match 'Complete-ConnectLogAsyncDrain\s+-Force') -and ($close -match 'Complete-ConnectLogAsyncDrain\s+-Force')
Assert-C '6' $c6 'Win: session-end Complete-ConnectLogAsyncDrain -Force' $(if ($c6) { 'Wait + Close' } else { 'missing Force drain' })

$c7 = $ui -match '\.sync-lock|ConnectLogSyncInProgress'
Assert-C '7' $c7 'Win: sync lock' $(if ($c7) { 'ok' } else { 'missing' })

$c8 = ($sh -match 'cat_ok=1') -and ($sh -match 'if \[ "\$cat_ok" = 1 \]')
Assert-C '8' $c8 'Mac: watermark gated by cat_ok' $(if ($c8) { 'ok' } else { 'missing' })

$clog = Get-BalancedBlock -Text $sh -StartPattern '(?m)^connect_log\(\)'
$c9MacWarn = ($clog -match '\[ "\$level" = "WARN" \]') -and ($clog -match 'CONNECT_LOG_WARN_UNTIL') -and ($clog -match 'request_connect_log_sync')
$c9MacErr = ($clog -match '\[ "\$level" = "ERROR" \]') -and ($clog -match 'complete_connect_log_async_drain force')
Assert-C '9' ($c9MacWarn -and $c9MacErr) 'Mac: ERROR force drain; WARN coalesce' $(if ($c9MacWarn -and $c9MacErr) { 'ok' } else { 'missing' })

$flush = Get-BalancedBlock -Text $sh -StartPattern '(?m)^flush_connect_log_to_server\(\)'
$c10 = ($flush.Length -gt 0) -and ($flush -match 'complete_connect_log_async_drain force')
Assert-C '10' $c10 'Mac: flush_connect_log_to_server Force drain' $(if ($c10) { 'ok' } else { 'missing' })

$c11 = ($mac -match "trap 'ec=\$\?") -and ($mac -match 'flush_connect_log_to_server')
Assert-C '11' $c11 'Mac: ERR/EXIT trap calls flush_connect_log_to_server' $(if ($c11) { 'ok' } else { 'missing ERR-trap flush' })

$bash = 'C:\Program Files\Git\bin\bash.exe'
$c12 = $true
if (Test-Path $bash) {
  & $bash -n (Join-Path $RepoRoot 'scripts/client/mac/connect.sh'); if ($LASTEXITCODE -ne 0) { $c12 = $false }
  & $bash -n (Join-Path $RepoRoot 'scripts/client/connect-ui.sh'); if ($LASTEXITCODE -ne 0) { $c12 = $false }
}
Assert-C '12' $c12 'Mac: bash -n syntax' $(if ($c12) { 'clean' } else { 'syntax error' })

$c13 = ($ui -match 'prevPath|previous day|rollover' -or $sh -match 'previous|rollover|CONNECT_LOG_PATH') -and
  ($ui -match 'Sync-ConnectLogToServer -Force -LogPath \$prevPath' -or $ui -match 'prevPath')
Assert-C '13' $c13 'Midnight flushes previous day' $(if ($c13) { 'ok' } else { 'missing' })


$c14 = ($ui -match 'LOG_SYNC_SKIP reason=forbid_shrink') -and ($sh -match 'LOG_SYNC_SKIP reason=forbid_shrink')
Assert-C '14' $c14 'Stage9: forbid_shrink skip Win+Mac' $(if ($c14) { 'ok' } else { 'missing' })

$c15 = ($ui -match 'LOG_SYNC_FAIL[^
]*detail=') -and ($sh -match 'LOG_SYNC_FAIL detail=')
Assert-C '15' $c15 'Stage9: LOG_SYNC_FAIL detail surfaced' $(if ($c15) { 'ok' } else { 'missing' })

Write-Host ''
Write-Host "=== RESULT fail=$fail ==="
if ($fail -eq 0) { Write-Host 'VERDICT: PASS'; exit 0 } else { Write-Host 'VERDICT: HARD FAIL'; exit 1 }
