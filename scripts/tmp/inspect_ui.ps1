Select-String -Path scripts/client/connect-ui.ps1 -Pattern '^function ' | ForEach-Object { '{0} {1}' -f $_.LineNumber, $_.Line }
Write-Host '--- lines ---'
(Get-Content scripts/client/connect-ui.ps1 | Measure-Object -Line).Lines
