$ErrorActionPreference = 'Continue'
Write-Host "=== SOURCE ==="
Write-Host ("version.txt=" + (Get-Content .\scripts\client\windows\connect-version.txt -Raw).Trim())
$m = Select-String -Path .\scripts\client\windows\connect.ps1 -Pattern 'ConnectVersion\s*=' | Select-Object -First 1
Write-Host ("connect.ps1=" + $m.Line.Trim())

# Key fix markers
$checks = @(
  @{f='scripts\client\connect-ui.ps1'; p='CLAUDE_CONNECT_PERF_LOG -eq ''1'''},
  @{f='scripts\client\connect-ui.ps1'; p='Enter-ConnectSingleInstance'},
  @{f='scripts\client\connect-ui.ps1'; p='FileShare.ReadWrite'},
  @{f='scripts\client\connect-ui.ps1'; p='512KB'},
  @{f='scripts\client\connect-ui.ps1'; p='Get-ConnectLogDayPath'},
  @{f='scripts\client\connect-ui.ps1'; p='LastConnectLogSyncOk'},
  @{f='scripts\client\git-mode.ps1'; p='LastTunnelSyncTraceAt'},
  @{f='scripts\client\git-mode.ps1'; p='$i -le 4'},
  @{f='scripts\client\windows\connect.ps1'; p='lastEditorCheckAt'},
  @{f='scripts\client\windows\connect.ps1'; p='Start-Sleep -Milliseconds 500'},
  @{f='scripts\client\windows\connect.bat'; p='BOOTSTRAP'},
  @{f='scripts\client\connect-ui.sh'; p='flock'},
  @{f='scripts\client\git-mode.sh'; p='seq 1 4'}
)
Write-Host "=== FIX MARKERS ==="
foreach ($c in $checks) {
  $hit = Select-String -Path $c.f -Pattern $c.p -SimpleMatch -Quiet
  Write-Host ("{0}: {1} -> {2}" -f $(if($hit){'OK'}else{'MISS'}), $c.f, $c.p)
}

# Parse
try {
  . .\scripts\client\connect-ui.ps1
  . .\scripts\client\git-mode.ps1
  Write-Host "=== PARSE OK ==="
} catch {
  Write-Host ("=== PARSE FAIL: " + $_.Exception.Message)
  exit 1
}

# Desktop folder version if present
$desk = @(
  "$env:USERPROFILE\Desktop\Claude Connect",
  "$env:USERPROFILE\Desktop\Claude-Connect",
  "$env:USERPROFILE\Desktop\Sepidz Claude Connect"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($desk) {
  $dv = Join-Path $desk 'connect-version.txt'
  if (Test-Path $dv) { Write-Host ("desktop_version=" + (Get-Content $dv -Raw).Trim() + " path=$desk") }
  else { Write-Host "desktop_found=$desk but no version file" }
} else {
  Write-Host "desktop_folder=not_found"
  Get-ChildItem "$env:USERPROFILE\Desktop" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("desk_dir=" + $_.Name) }
}
