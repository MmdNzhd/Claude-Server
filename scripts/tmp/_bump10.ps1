$files = @(
  'scripts/client/mac/connect-version.txt',
  'scripts/client/windows/connect-version.txt'
)
foreach ($f in $files) { Set-Content $f -Value '20260717.10' -NoNewline; Write-Output "ver $f" }
$mac = Get-Content scripts/client/mac/connect.sh -Raw
$mac2 = [regex]::Replace($mac, "CONNECT_VERSION='20260717\.\d+'", "CONNECT_VERSION='20260717.10'")
Set-Content scripts/client/mac/connect.sh -Value $mac2 -NoNewline
$win = Get-Content scripts/client/windows/connect.ps1 -Raw
$win2 = [regex]::Replace($win, "ConnectVersion = '20260717\.\d+'", "ConnectVersion = '20260717.10'")
Set-Content scripts/client/windows/connect.ps1 -Value $win2 -NoNewline
Write-Output 'bumped'
