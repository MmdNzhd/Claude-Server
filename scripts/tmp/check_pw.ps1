. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$p = Get-SepidzSudoPassword
if ([string]::IsNullOrWhiteSpace($p)) { Write-Host 'FAIL empty'; exit 1 }
Write-Host ("OK password ready len={0}" -f $p.Length)
# confirm deploy script has hardcoded fallback
$d = Get-Content 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' -Raw
if ($d -match "sepidz@Admin") { Write-Host 'OK deploy has hardcoded sepidz password' } else { Write-Host 'FAIL deploy missing hardcode'; exit 1 }
$c = Get-Content 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1' -Raw
if ($c -match "return 'sepidz@Admin'") { Write-Host 'OK credentials has hardcoded return' } else { Write-Host 'FAIL cred missing'; exit 1 }
