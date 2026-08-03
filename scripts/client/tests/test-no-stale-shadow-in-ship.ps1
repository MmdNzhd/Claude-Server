#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
. (Join-Path $here "_paths.ps1")
$fail = 0
function Assert($c,$m){ if($c){Write-Host "PASS $m" -ForegroundColor Green} else {Write-Host "FAIL $m" -ForegroundColor Red; $script:fail++} }
$win = Get-ClientFile "windows"
# windows shadows OK in repo; published flat paths must not use them
$canonDiag = Get-ClientFile "connect-diagnostic.ps1"
$canonUi = Get-ClientFile "connect-ui.ps1"
Assert ((Get-Item $canonDiag).Length -gt 5000) "canon connect-diagnostic is full body"
Assert ((Get-Item $canonUi).Length -gt 5000) "canon connect-ui is full body"
$shadowDiag = Join-Path $win "connect-diagnostic.ps1"
$shadowUi = Join-Path $win "connect-ui.ps1"
Assert (((Get-Content $shadowDiag -TotalCount 3) -join " ") -match "STALE-SHADOW") "windows/connect-diagnostic remains intentional shadow"
Assert (((Get-Content $shadowUi -TotalCount 3) -join " ") -match "STALE-SHADOW") "windows/connect-ui remains intentional shadow"
# deploy script must source canon for these names
$dcb = Get-Content (Join-Path (Split-Path (Split-Path $here)) "server\commands\deploy-client-bundle.sh") -Raw -EA 0
if (-not $dcb) { $dcb = Get-Content "D:\Smart\Claude-Code-Server\scripts\server\commands\deploy-client-bundle.sh" -Raw }
Assert ($dcb -match "connect-ui.ps1\|connect-diagnostic.ps1") "deploy-client-bundle maps ui/diagnostic to CLIENT_DIR canon"
Assert ($dcb -match "STALE-SHADOW") "deploy refuses STALE-SHADOW wrappers"
# simulate wrong ship map would fail size gate
Assert ((Get-Item $shadowDiag).Length -lt 2000) "shadow diagnostic is tiny (would break flat install)"
if ($fail -gt 0) { Write-Host "FAILED $fail"; exit 1 }
Write-Host "ALL PASS"; exit 0
