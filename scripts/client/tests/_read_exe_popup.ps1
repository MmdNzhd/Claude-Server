$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260722.log'
$cut = Get-Date '2026-07-22 23:45:00'
Write-Output '==== LINES AFTER 23:45 (any level, non-TRACE sample) ===='
Get-Content -LiteralPath $log | Where-Object {
  if ($_ -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
    try { [datetime]::ParseExact($Matches[1],'yyyy-MM-dd HH:mm:ss',$null) -ge $cut } catch { $false }
  } else { $false }
} | Where-Object { $_ -notmatch '\[TRACE\]' } | Select-Object -Last 80

Write-Output '==== MULTI_INSTANCE / UPDATE / WARN popup-ish last 60 ===='
Select-String -LiteralPath $log -Pattern 'MULTI_INSTANCE|UPDATE:|bat_relaunch|from_exe|MessageBox|Show-Error|Show-Warn|uiReady|EXIT_WAIT|require_fail|Personal Cursor|AUTH_WARN|Path is required|syntax error|CRLF|do\\r|elevated_direct|PROC_START_FAIL|win32=' |
  Select-Object -Last 60 | ForEach-Object { $_.Line }

Write-Output '==== DESKTOP EXE / FOLDER ===='
$desk = Join-Path $env:USERPROFILE 'Desktop'
@(
  (Join-Path $desk 'Claude-Connect.exe'),
  (Join-Path $desk 'Claude-Connect\Claude-Connect.exe'),
  (Join-Path $desk 'Claude-Connect\connect.bat'),
  (Join-Path $desk 'Claude-Connect\connect.ps1')
) | ForEach-Object {
  if (Test-Path -LiteralPath $_) {
    $i = Get-Item -LiteralPath $_
    Write-Output ("EXISTS {0} len={1} mtime={2:o}" -f $_, $i.Length, $i.LastWriteTime)
  } else { Write-Output ("MISSING {0}" -f $_) }
}
$ps1 = Join-Path $desk 'Claude-Connect\connect.ps1'
if (Test-Path $ps1) {
  Select-String -LiteralPath $ps1 -Pattern 'ConnectVersion|CONNECT_VERSION' | Select-Object -First 5 | ForEach-Object { $_.Line.Trim() }
}

Write-Output '==== RUNNING Claude-Connect / powershell connect ===='
Get-CimInstance Win32_Process -Filter "Name='Claude-Connect.exe' OR Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'Claude-Connect|connect\.ps1|connect\.bat' } |
  Select-Object ProcessId, Name, @{n='Cmd';e={ if ($_.CommandLine.Length -gt 180) { $_.CommandLine.Substring(0,180)+'...' } else { $_.CommandLine } }} |
  Format-List | Out-String -Width 220
