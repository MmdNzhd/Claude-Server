$ErrorActionPreference = 'Continue'
$files = @(
  'scripts/client/git-mode.ps1',
  'scripts/client/windows/connect.ps1',
  'scripts/client/connect-ui.ps1',
  'scripts/client/editor-launch.ps1',
  'scripts/client/windows/connect-update.ps1'
)

$patterns = @(
  'Clear-SessionMount','Stop-SessionTunnelCleanup','Remove-LocalOrphanTunnel','ORPHAN_TUNNEL',
  'Clear-ServerStaleTunnelForward','fuser -k','soft_fail','tunnel_down','TUNNEL_DROP',
  'Push-ServerConnectConf','claude-self-heal','self-heal','Sync-ConnectLogToServer',
  'claude-code-client','Warn-Foreign','base64','ExitOnForwardFailure','ServerAlive',
  'SkipEditorStop','editor_opened','finally','Acquire-TunnelPort','MaxStartups',
  'Test-TunnelBannerIsWindows','OpenSSH_for_Windows','elevated','False','PERF',
  'TRACE','LastForwardProbeAt','Start-Sleep -Milliseconds 500','FromSeconds\(2\)',
  'cursor not on target','relaunching','ForceCursorAuthSync','auth-sync --force',
  'Invoke-BundleDownload','timeout 45','bash -lc'
)

Write-Output '===== PATTERN HITS ====='
foreach ($pat in $patterns) {
  $hits = @()
  foreach ($f in $files) {
    if (-not (Test-Path $f)) { continue }
    $m = Select-String -Path $f -Pattern $pat -SimpleMatch:$false -ErrorAction SilentlyContinue
    foreach ($h in $m) {
      $hits += ("{0}:{1}:{2}" -f $f, $h.LineNumber, ($h.Line.Trim().Substring(0, [Math]::Min(120, $h.Line.Trim().Length))))
    }
  }
  if ($hits.Count -gt 0) {
    Write-Output ("--- {0} (n={1}) ---" -f $pat, $hits.Count)
    $hits | Select-Object -First 8 | ForEach-Object { Write-Output $_ }
  }
}

Write-Output '`n===== Push-ServerConnectConf / self-heal body ====='
$gm = Get-Content 'scripts/client/git-mode.ps1'
for ($i=0; $i -lt $gm.Count; $i++) {
  if ($gm[$i] -match 'function Push-ServerConnectConf|self-heal|claude-self-heal|Warn-Foreign') {
    '{0,5}|{1}' -f ($i+1), $gm[$i]
  }
}
# extract Push-ServerConnectConf
for ($i=0; $i -lt $gm.Count; $i++) {
  if ($gm[$i] -match '^function Push-ServerConnectConf') {
    for ($j=$i; $j -lt [Math]::Min($i+80,$gm.Count); $j++) {
      '{0,5}|{1}' -f ($j+1), $gm[$j]
      if ($j -gt $i -and $gm[$j] -match '^function ') { break }
    }
    break
  }
}

Write-Output '`n===== Sync-ConnectLogToServer ====='
$ui = Get-Content 'scripts/client/connect-ui.ps1'
for ($i=0; $i -lt $ui.Count; $i++) {
  if ($ui[$i] -match '^function Sync-ConnectLogToServer') {
    for ($j=$i; $j -lt [Math]::Min($i+100,$ui.Count); $j++) {
      '{0,5}|{1}' -f ($j+1), $ui[$j]
      if ($j -gt $i -and $ui[$j] -match '^function ') { break }
    }
    break
  }
}

Write-Output '`n===== connect.ps1 finally + package guard ====='
$c = Get-Content 'scripts/client/windows/connect.ps1'
for ($i=0; $i -lt $c.Count; $i++) {
  if ($c[$i] -match 'claude-code-client|wrong package|SepidzOnly|finally|alreadyDown|Stop-SessionTunnelCleanup') {
    '{0,5}|{1}' -f ($i+1), $c[$i].Substring(0,[Math]::Min(140,$c[$i].Length))
  }
}
