$ErrorActionPreference='Continue'
Write-Host "=== Remote versions ==="
$sep = (ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$sma = (ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
Write-Host "Sepidz=$sep  Smart=$sma"

$pkg = "$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows"
Write-Host "=== Package markers ($pkg) ==="
$checks = @(
  'CLAUDE_CONNECT_PERF_LOG -eq ''1''',
  'Enter-ConnectSingleInstance',
  'FileShare.ReadWrite',
  '512KB',
  'LastConnectLogSyncOk',
  'LastTunnelSyncTraceAt',
  'lastEditorCheckAt',
  'BOOTSTRAP'
)
$files = @{
  'CLAUDE_CONNECT_PERF_LOG -eq ''1'''='connect-ui.ps1'
  'Enter-ConnectSingleInstance'='connect-ui.ps1'
  'FileShare.ReadWrite'='connect-ui.ps1'
  '512KB'='connect-ui.ps1'
  'LastConnectLogSyncOk'='connect-ui.ps1'
  'LastTunnelSyncTraceAt'='git-mode.ps1'
  'lastEditorCheckAt'='connect.ps1'
  'BOOTSTRAP'='connect.bat'
}
foreach ($p in $checks) {
  $f = Join-Path $pkg $files[$p]
  $hit = Select-String -Path $f -Pattern $p -SimpleMatch -Quiet
  Write-Host ("{0}: {1}" -f $(if($hit){'OK'}else{'MISS'}), $p)
}
$ver = (Get-Content (Join-Path $pkg 'connect-version.txt') -Raw).Trim()
Write-Host "package_ver=$ver"

# Alias/IP sanity
$cp = Get-Content (Join-Path $pkg 'connect.ps1') -Raw
if ($cp -match 'claude-server-sepidz') { Write-Host 'OK: alias sepidz' } else { Write-Host 'MISS: alias' }
if ($cp -match '192\.168\.250\.70') { Write-Host 'OK: sepidz IP' } else { Write-Host 'MISS: sepidz IP' }
if ($cp -match '192\.168\.210\.240') { Write-Host 'WARN: still has smart IP' } else { Write-Host 'OK: no smart IP' }

Write-Host "=== Running connect processes? ==="
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.ps1' } |
  ForEach-Object { Write-Host ("PID={0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length))) }
