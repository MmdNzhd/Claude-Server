$root='D:\Smart\Claude-Code-Server'
# confirm local password helper works without prompt
. "$root\publish\Get-DeployCredentials.ps1"
$p = Get-SepidzSudoPassword
if ([string]::IsNullOrWhiteSpace($p)) { Write-Host 'FAIL empty sepidz sudo password' } else { Write-Host "OK sepidz password loaded len=$($p.Length)" }
# show deploy path around sudo
Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'sudo|SudoPassword|Get-Sepidz|BatchMode|interactive' |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
Test-Path "$root\publish\sepidz-deploy.local.ps1"
