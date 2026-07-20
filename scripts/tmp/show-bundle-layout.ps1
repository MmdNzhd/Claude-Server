Select-String -Path 'publish\deploy-client-bundles.ps1' -Pattern 'function New-|Zip|bundle|install-client' |
  Select-Object -First 50 | ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Output '==== install script in repo ===='
Get-ChildItem -Recurse -Filter 'install-client-bundle.sh' | ForEach-Object { $_.FullName }
