#Requires -Version 5.1
# Task 3: elevate-when-needed — cold start must not immediate RunAs
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Elevate-when-needed contracts ===' -ForegroundColor White
$win = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($win -match 'Elevate-when-needed') 'connect.ps1 documents elevate-when-needed'
Assert ($win -notmatch '(?s)Always elevate the main connect UI') 'always-elevate main UI block removed'
$early = $win.Substring(0, [Math]::Min(3500, $win.Length))
Assert ($early -notmatch 'Verb RunAs') 'cold-start header has no Verb RunAs'
Assert ($win -match 'Invoke-LaptopAdminOps') 'Invoke-LaptopAdminOps still present for on-demand elevate'
Assert ($win -match 'Start-Process powershell\.exe -Verb RunAs') 'AdminFix path still uses RunAs'
Assert ($win -match '\[switch\]\$AdminFix') 'AdminFix switch retained'

Write-Host ''
if ($failed -gt 0) { Write-Host "FAIL elevate-when-needed ($failed failed)" -ForegroundColor Red; exit 1 }
Write-Host "PASS elevate-when-needed ($passed checks)" -ForegroundColor Green
exit 0
