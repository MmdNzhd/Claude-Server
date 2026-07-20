$ErrorActionPreference = 'Continue'
Write-Host '=== RG-PROOF Get-DeployCredentials ==='
Select-String -Path publish\Get-DeployCredentials.ps1 -Pattern 'sepidz@Admin|No hardcoded|throw' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== RG-PROOF deploy-client-bundles ==='
Select-String -Path publish\deploy-client-bundles.ps1 -Pattern 'sepidz@Admin|no hardcoded|Get-SepidzSudoPassword' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Host '=== count sepidz@Admin in publish non-local ==='
$hits = Select-String -Path publish\Get-DeployCredentials.ps1,publish\deploy-client-bundles.ps1 -Pattern 'sepidz@Admin' -SimpleMatch
if ($hits) { $hits | ForEach-Object { '{0}:{1}:{2}' -f $_.Filename, $_.LineNumber, $_.Line.Trim() } } else { 'ZERO hits in Get-DeployCredentials.ps1 + deploy-client-bundles.ps1' }
Write-Host '=== deploy-client-bundle AK ==='
(Get-Content scripts\server\commands\deploy-client-bundle.sh)[233..255]
Write-Host '=== FIX report ==='
if (Test-Path scripts\tmp\FIX-AGENT-1.md) { Get-Content scripts\tmp\FIX-AGENT-1.md } else { 'FIX-AGENT-1.md ABSENT' }
Write-Host '=== settings chmod sync ==='
Select-String -Path scripts\server\claude-auth-sync.sh -Pattern 'chmod' | ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim() }
