$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
Write-Output '=== CURRENT VERSIONS ==='
@(
  'scripts\client\windows\connect-version.txt',
  'scripts\client\mac\connect-version.txt'
) | ForEach-Object {
  $p=Join-Path $root $_
  Write-Output ("$((Get-Content $p -Raw).Trim()) | $_")
}
Select-String -Path (Join-Path $root 'scripts\client\windows\connect.ps1') -Pattern "ConnectVersion\s*=" | Select-Object -First 3 | ForEach-Object { $_.Line.Trim() }
Select-String -Path (Join-Path $root 'scripts\client\mac\connect.sh') -Pattern "CONNECT_VERSION=" | Select-Object -First 3 | ForEach-Object { $_.Line.Trim() }
Write-Output '=== AUTH FIX PRESENT? ==='
Select-String -Path (Join-Path $root 'scripts\client\cursor-auth-laptop.ps1') -Pattern 'Get-CursorAuthTempRoot|Remove-CursorAuthTempDir' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '=== PUBLISH SCRIPTS ==='
Get-ChildItem (Join-Path $root 'publish') -Filter '*.bat' | ForEach-Object { $_.Name }
Get-ChildItem (Join-Path $root 'publish') -Filter 'publish*.ps1' | ForEach-Object { $_.Name }
