$ErrorActionPreference='Continue'
$pkg = "$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows"
Write-Host "package_ver=$((Get-Content (Join-Path $pkg 'connect-version.txt') -Raw).Trim())"
$pairs = @(
  @('connect-ui.ps1','CLAUDE_CONNECT_PERF_LOG -eq ''1'''),
  @('connect-ui.ps1','Enter-ConnectSingleInstance'),
  @('connect-ui.ps1','FileShare.ReadWrite'),
  @('connect-ui.ps1','512KB'),
  @('connect-ui.ps1','LastConnectLogSyncOk'),
  @('git-mode.ps1','LastTunnelSyncTraceAt'),
  @('connect.ps1','lastEditorCheckAt'),
  @('connect.bat','BOOTSTRAP')
)
foreach ($pair in $pairs) {
  $hit = Select-String -Path (Join-Path $pkg $pair[0]) -Pattern $pair[1] -SimpleMatch -Quiet
  Write-Host ("{0}: {1}" -f $(if($hit){'OK'}else{'MISS'}), $pair[1])
}
$cp = Get-Content (Join-Path $pkg 'connect.ps1') -Raw
Write-Host $(if($cp -match 'claude-server-sepidz'){'OK: alias'}else{'MISS: alias'})
Write-Host $(if($cp -match '192\.168\.250\.70'){'OK: sepidz IP'}else{'MISS: IP'})
Write-Host $(if($cp -notmatch '192\.168\.210\.240'){'OK: no smart IP'}else{'WARN: smart IP present'})
