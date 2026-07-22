$ErrorActionPreference='Continue'
$profileDir = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
$needle = [regex]::Escape($profileDir)
$killed = 0
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -match '(?i)^Cursor\.exe$' -and $_.CommandLine -and ($_.CommandLine -match $needle)
} | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  $killed++
}
Start-Sleep -Seconds 1
$left = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -match '(?i)^Cursor\.exe$' -and $_.CommandLine -and ($_.CommandLine -match $needle)
}).Count
Write-Host ("killed={0} left_profile={1}" -f $killed, $left)
$vscdb = Join-Path $profileDir 'User\globalStorage\state.vscdb'
if (Test-Path $vscdb) {
  $mb = [math]::Round((Get-Item $vscdb).Length/1MB,1)
  Write-Host ("state_vscdb_MB={0}" -f $mb)
}
