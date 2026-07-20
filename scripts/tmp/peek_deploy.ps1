$root='D:\Smart\Claude-Code-Server'
Write-Host '=== publish.ps1 params ==='
Select-String -Path "$root\publish\publish.ps1" -Pattern 'param|SepidzOnly|SmartOnly|Deploy|Target' | Select-Object -First 40 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== deploy-client-bundles.ps1 ==='
if (Test-Path "$root\publish\deploy-client-bundles.ps1") {
  Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'param|Sepidz|Smart|Only|250|210' | Select-Object -First 50 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
}
Write-Host '=== versions ==='
Get-Content "$root\scripts\client\windows\connect-version.txt"
Get-Content "$root\scripts\client\mac\connect-version.txt"
