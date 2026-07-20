$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
# publish.ps1 deploy section full
Write-Output '=== publish.ps1 from 250 ==='
(Get-Content (Join-Path $root 'publish\publish.ps1'))[249..340]
Write-Output ''
# Test-TunnelUp full + cache TTL
Write-Output '=== Test-TunnelUp + Get-TunnelBanner TTL ==='
$gm=Join-Path $root 'scripts\client\git-mode.ps1'
(Get-Content $gm)[160..190]
(Get-Content $gm)[325..345]
# bat version guards
Write-Output '=== bat ConnectVersion guards ==='
Select-String -Path (Join-Path $root 'scripts\client\windows\connect.bat') -Pattern '202607|ConnectVersion|version' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
# Where ExpectedVersion could be read from client root
Write-Output '=== finish-*-deploy.ps1 ==='
Get-Content (Join-Path $root 'publish\finish-smart-deploy.ps1') -ErrorAction SilentlyContinue
Write-Output '---'
Get-Content (Join-Path $root 'publish\finish-sepidz-deploy.ps1') -ErrorAction SilentlyContinue
