$ErrorActionPreference = 'Continue'
$files = @(
  "$env:USERPROFILE\Downloads\Telegram Desktop\connect (2).log",
  "$env:USERPROFILE\Downloads\Telegram Desktop\connect.log",
  "$env:USERPROFILE\Downloads\connect.log",
  "$env:USERPROFILE\Downloads\connect-arya.log",
  "$env:USERPROFILE\Downloads\connect-mehrdad.log"
)
foreach ($p in $files) {
  if (-not (Test-Path $p)) { Write-Output "MISSING $p"; continue }
  Write-Output "======== $p ========"
  Select-String -Path $p -Pattern 'SERVER_USER|LAPTOP_USER|VERDICT_|CLIENT_VERSION|SESSION_STATUS|CURSOR_NOT|Partial auth|192\.168\.250|SERVER=' |
    Select-Object -First 30 |
    ForEach-Object { $_.Line.Trim() }
}
# any file with azin in name under Downloads
Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse -Depth 3 -EA SilentlyContinue |
  Where-Object { $_.Name -match 'azin|اذین|azeen|nima' } |
  Select-Object -First 20 FullName, Length, LastWriteTime
