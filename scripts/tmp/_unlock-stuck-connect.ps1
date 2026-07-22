#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
# Kill ONLY stuck connect-boot / connect.ps1 from publish folders or Claude-Connect.
# NEVER Cursor.exe / ClaudeServerCursorProfile.
$killed = @()
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  $_.CommandLine -and (
    $_.CommandLine -match '(?i)connect-boot\.ps1' -or
    ($_.CommandLine -match '(?i)[\\/]connect\.ps1(\s|$|"|'')' -and $_.CommandLine -match '(?i)claude-(publish|connect)|Claude-Connect')
  ) -and $_.Name -match 'powershell' -and $_.CommandLine -notmatch '(?i)Cursor\.exe'
} | ForEach-Object {
  Write-Host ("KILL pid=$($_.ProcessId) $($_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length)))")
  cmd /c "taskkill /F /PID $($_.ProcessId) /T" 2>$null | Out-Null
  $killed += $_.ProcessId
}
Start-Sleep -Milliseconds 500
# mutex check
try {
  $null = [System.Threading.Mutex]::OpenExisting('Global\ClaudeConnect')
  Write-Host 'mutex=STILL_HELD (abandoned may clear on next WaitOne)'
} catch {
  Write-Host 'mutex=FREE'
}
Write-Host ("killed_count=$($killed.Count)")
