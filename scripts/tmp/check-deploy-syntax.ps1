$path = Join-Path (Get-Location) 'publish\deploy-client-bundles.ps1'
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
if ($errors) { $errors | ForEach-Object { Write-Host $_.ToString() }; exit 1 }
Write-Host 'deploy-client-bundles.ps1 syntax OK'
