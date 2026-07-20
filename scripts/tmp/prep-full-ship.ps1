$ErrorActionPreference='Continue'
Write-Output "version=$(Get-Content scripts\client\windows\connect-version.txt -Raw)"
Write-Output "--- publish scripts ---"
Get-ChildItem publish -Filter '*.ps1' | Select-Object Name
Write-Output "--- deploy locals ---"
Get-ChildItem publish -Filter '*deploy*.local.ps1' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
Write-Output "--- deploy-client-bundles ---"
Select-String -Path 'publish\deploy-client-bundles.ps1' -Pattern 'param\(|ExpectedVersion|Smart|Sepidz|ServerTarget' |
  Select-Object -First 40 | ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Output "--- publish.bat/ps1 entry ---"
Get-Content 'publish\publish.bat' -ErrorAction SilentlyContinue | Select-Object -First 20
