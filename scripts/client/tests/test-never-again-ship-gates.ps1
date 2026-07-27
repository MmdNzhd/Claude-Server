#Requires -Version 5.1
# test-never-again-ship-gates.ps1 - lock the 2026-07-27 fleet breakages so they cannot ship again:
#   1) STALE-SHADOW diagnostic/ui in flat client bundle
#   2) IExpress AppLaunched powershell Bypass+Hidden (Defender dropper heuristic)
#   3) Sticky 18998 repair when xray backend is down (agent PROXY ECONNREFUSED)
#   4) Manual update leaving stale "Press Enter to close"
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== never-again ship gates (2026-07-27 fleet) ==='
Write-Host ''

$dcb = Get-Content (Join-Path $RepoRoot 'scripts\server\commands\deploy-client-bundle.sh') -Raw
$build = Get-Content (Join-Path $RepoRoot 'publish\build-windows-exe.ps1') -Raw
$side = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\cursor-proxy-sidecar.ps1') -Raw
$ui = Get-Content (Join-Path $RepoRoot 'scripts\client\connect-ui.ps1') -Raw
$diagCanon = Get-Content (Join-Path $RepoRoot 'scripts\client\connect-diagnostic.ps1') -Raw
$diagShadow = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-diagnostic.ps1') -Raw

# --- 1) Flat bundle must ship CANON diagnostic/ui; deploy must refuse shadows ---
Assert ($dcb -match 'connect-ui\.ps1\|connect-diagnostic\.ps1\|editor-launch') `
    'deploy maps connect-diagnostic + connect-ui from CLIENT_DIR canon'
Assert ($dcb -match 'scripts/client/connect-diagnostic\.ps1') `
    'deploy stages scripts/client/connect-diagnostic.ps1 (not only windows/ stub)'
Assert ($dcb -match 'STALE-SHADOW REPLACED') `
    'deploy fail-closed greps STALE-SHADOW before install'
Assert ($dcb -match '_verify_staged_client_bundle') `
    'deploy has post-stage ship-gate verifier'
Assert ($dcb -match 'ship-gate: staged connect-diagnostic\.ps1 is STALE-SHADOW') `
    'ship-gate explicitly blocks diagnostic shadow'
Assert ($dcb -match 'ship-gate: Claude-Connect\.exe embeds powershell Bypass') `
    'ship-gate blocks AV AppLaunched EXE heuristic'
Assert ($diagCanon -match 'Get-ConnectProblemVerdict') 'canon diagnostic has verdict helper'
Assert ($diagCanon -notmatch 'STALE-SHADOW REPLACED') 'canon diagnostic is not a shadow'
Assert ($diagShadow -match 'STALE-SHADOW REPLACED') 'windows/ diagnostic remains repo-dev shadow only'

# --- 2) EXE AppLaunched must stay cmd -> setup.cmd ---
Assert ($build -match "AppLaunched=cmd\.exe /c setup-claude-connect\.cmd") `
    'IExpress AppLaunched is cmd.exe /c setup-claude-connect.cmd'
Assert (-not ($build -match "AppLaunched=powershell\.exe")) `
    'IExpress AppLaunched is not raw powershell.exe'

# --- 3) Dead 18998 must never be repaired when backend down ---
Assert ($side -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'sidecar force-clears when backend -L down'
Assert ($side -match 'SIDECAR_ENSURE front_up backend_down stopping_fronts_clearing_settings') `
    'Ensure stops front doors when backend down'
Assert ($side -match 'SIDECAR_START front_up backend_down stopping_fronts') `
    'Start refuses to pin settings without backend'
Assert ($dcb -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'ship-gate requires backend_down force-clear string in staged sidecar'

# --- 4) Manual update must not stick on Press Enter ---
Assert ($ui -match 'Stop-Process -Id \$PID -Force') `
    'connect-ui hard-kills self after update apply (no stale Press Enter)'
Assert ($ui -match "Reason -eq 'update_manual_relaunch'") `
    'Wait-ConnectExit still knows update_manual_relaunch'
Assert ($ui -match 'Never fall through to a stale in-memory Wait-ConnectExit') `
    'manual update path documents no Press Enter fallthrough'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} never-again gates passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
