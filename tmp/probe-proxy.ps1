$ErrorActionPreference = 'Continue'
$cc = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
Write-Host 'CC_VER=' (Get-Content (Join-Path $cc 'connect-version.txt') -EA SilentlyContinue)
Write-Host 'CC_FILES='
Get-ChildItem $cc -Name | Select-Object -First 25
Write-Host 'SSH='
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'ssh.exe' -and $_.CommandLine -match '-L|-D|2002' } | ForEach-Object {
  Write-Host ("pid={0} {1}" -f $_.ProcessId, $_.CommandLine)
}
$s = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile\User\settings.json'
Write-Host 'SETTINGS='
if (Test-Path $s) { Get-Content $s -Raw }
$day = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
Write-Host 'LOG5472='
Select-String -Path $day -Pattern '5472d67e94d2' -EA SilentlyContinue | Select-Object -Last 20 | ForEach-Object { $_.Line }
