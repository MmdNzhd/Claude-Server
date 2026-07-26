#Requires -Version 5.1
# Contracts: update applies scripts from bundle (not stale EXE SFX); Tag hashtable is consistent.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}
Write-Host ''
Write-Host '=== connect-update bundle-primary contracts ==='
$u = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
Assert ($u -match "bundle_primary try=1 reason=scripts_source_of_truth") 'bundle_primary is the update path'
Assert ($u -notmatch "exe_only_primary try=1") 'exe_only_primary early-exit removed'
Assert ($u -notmatch "exe_only_fallback_to_bundle") 'exe_only_fallback label removed'
Assert ($u -match "Tag = 'desk_exe'") 'EXE copy pairs use Tag= (not Req=)'
Assert ($u -notmatch "Req = 'desk_exe'") 'Req= typo gone'
Assert (($u -match 'GetFullPath\(\$dstExe\)') -or ($u -match 'GetFullPath\(\$desk\)')) 'exe_promote null-safe path compare'
Assert ($u -match 'scripts are source of truth') 'comment documents why bundle wins over SFX'
Write-Host ''
if ($Fail -eq 0) { Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green; exit 0 }
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
