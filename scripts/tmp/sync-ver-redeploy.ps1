Set-Location D:\Smart\Claude-Code-Server
$ver = (Get-Content scripts/client/windows/connect-version.txt -Raw).Trim()
Write-Host "file_ver=$ver"
Select-String -Path scripts/client/windows/connect.ps1,scripts/client/mac/connect.sh -Pattern 'ConnectVersion|CONNECT_VERSION' |
  ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim()) }

# sync all to file ver
$utf8 = New-Object System.Text.UTF8Encoding $false
$win = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/windows/connect.ps1'))
$win2 = [regex]::Replace($win, "\$script:ConnectVersion = '20260720\.\d+'", "`$script:ConnectVersion = '$ver'")
if ($win2 -eq $win) {
  if ($win -match "ConnectVersion = '$([regex]::Escape($ver))'") { Write-Host 'connect.ps1 already synced' }
  else { throw 'connect.ps1 version replace failed' }
} else {
  [IO.File]::WriteAllText((Resolve-Path 'scripts/client/windows/connect.ps1'), $win2, $utf8)
  Write-Host "OK synced connect.ps1 -> $ver"
}
$mac = [IO.File]::ReadAllText((Resolve-Path 'scripts/client/mac/connect.sh'))
$mac2 = [regex]::Replace($mac, "CONNECT_VERSION='20260720\.\d+'", "CONNECT_VERSION='$ver'")
if ($mac2 -ne $mac) {
  [IO.File]::WriteAllText((Resolve-Path 'scripts/client/mac/connect.sh'), $mac2, $utf8)
  Write-Host "OK synced mac -> $ver"
} else {
  Write-Host 'mac already synced or pattern miss'
  Select-String -Path scripts/client/mac/connect.sh -Pattern "CONNECT_VERSION=" | Select-Object -First 1
}
# mac version txt
Set-Content scripts/client/mac/connect-version.txt $ver -Encoding ascii
Write-Host 'OK mac connect-version.txt'

# confirm
$win = Get-Content scripts/client/windows/connect.ps1 -Raw
if ($win -notmatch "ConnectVersion = '$([regex]::Escape($ver))'") { throw 'still mismatched' }
Write-Host "CONFIRMED ConnectVersion=$ver"
