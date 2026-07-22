$ErrorActionPreference = 'Continue'
$killed = 0
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  $_.CommandLine -and ($_.CommandLine -match '(?i)connect\.(bat|ps1)') -and ($_.Name -match 'cmd|powershell')
} | ForEach-Object {
  Write-Host ("KILL pid=$($_.ProcessId) name=$($_.Name)")
  cmd /c "taskkill /F /PID $($_.ProcessId) /T" 2>$null | Out-Null
  $killed++
}
Write-Host "killed_count=$killed"

Write-Host '--- version ---'
Get-Content scripts/client/windows/connect-version.txt -ErrorAction SilentlyContinue
(Select-String -Path scripts/client/windows/connect.ps1 -Pattern 'ConnectVersion\s*=' | Select-Object -First 1).Line.Trim()

Write-Host '--- connect.bat ---'
Select-String -Path scripts/client/windows/connect.bat -Pattern 'UPD_EC|start ""|exit 0|exit /b|client-update-relaunch|call "%~f0"' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }

Write-Host '--- connect-update ---'
Select-String -Path scripts/client/windows/connect-update.ps1 -Pattern 'Invoke-ConnectPs1Relaunch|Exit-ConnectSingleInstance|exit 2|Release-Connect|need_relaunch' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }

$p = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\connect.bat'
Write-Host "publish2017_bat=$(Test-Path $p)"
if (Test-Path $p) {
  Select-String -Path $p -Pattern 'call "%~f0"|start ""|exit 0|UPD_EC|exit /b' | Select-Object -First 10 |
    ForEach-Object { $_.Line.Trim() }
}
