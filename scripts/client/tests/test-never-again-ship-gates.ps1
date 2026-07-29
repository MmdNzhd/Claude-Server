#Requires -Version 5.1
# test-never-again-ship-gates.ps1 - lock the 2026-07-27 fleet breakages so they cannot ship again:
#   1) STALE-SHADOW diagnostic/ui in flat client bundle
#   2) IExpress AppLaunched powershell Bypass+Hidden (Defender dropper heuristic)
#   3) Sticky 18998 repair when xray backend is down (agent PROXY ECONNREFUSED)
#   4) Manual update leaving stale "Press Enter to close"
#   5) BusyBox sed \r truncating trailing "r" on identifiers
#   6) Versioned layout: NEW.exe leaked into OLD VerDir; orphan cmd from instant .cmd
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
Assert ($build -match "AppLaunched=wscript\.exe //B //Nologo setup-run-hidden\.vbs") `
    'IExpress AppLaunched is hidden wscript -> setup-run-hidden.vbs'
Assert ($build -match 'setup-claude-connect\.cmd') `
    'IExpress stage still runs setup-claude-connect.cmd under the hidden launcher'
Assert ($build -match 'sh\.Run cmd, 0, True') `
    'hidden VBS runs cmd with window style 0 (no console flash)'
Assert (-not ($build -match "AppLaunched=powershell\.exe")) `
    'IExpress AppLaunched is not raw powershell.exe'

# --- 3) Dead 18998 must never be repaired when backend down ---
Assert ($side -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'sidecar force-clears when backend -L down'
Assert ($side -match 'Get-CursorProxySettingsPathsForClear') `
    'sidecar enumerates personal+profile settings paths for clear'
Assert ($side -match 'CURSOR_PROXY_CLEAR removed_18998_dead_proxy path=') `
    'sidecar logs which settings path was scrubbed'
Assert ($side -match 'SIDECAR_ENSURE front_up backend_down stopping_fronts_clearing_settings') `
    'Ensure stops front doors when backend down'
Assert ($side -match 'SIDECAR_START front_up backend_down stopping_fronts') `
    'Start refuses to pin settings without backend'
Assert ($side -match 'SIDECAR_HEAL_BLACKHOLE front_up backend_down') `
    'HealBlackhole stops orphan fronts without backends'
Assert ($side -match 'Clear-Sticky18998Settings') `
    'watchdog scrubs sticky 18998 when front is blackhole'
$macSide = Get-Content (Join-Path $RepoRoot 'scripts\client\mac\cursor-proxy-sidecar.sh') -Raw
Assert ($macSide -match 'SIDECAR_HEAL_BLACKHOLE front_up backend_down') `
    'Mac sidecar has HealBlackhole'
Assert ($macSide -match 'test_cursor_proxy_backend_open') `
    'Mac sidecar gates start on backend'
Assert ($dcb -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'ship-gate requires backend_down force-clear string in staged sidecar'
Assert ($dcb -match 'Get-CursorProxySettingsPathsForClear') `
    'ship-gate requires personal+profile path enum'
Assert ($dcb -match 'SIDECAR_HEAL_BLACKHOLE') `
    'ship-gate requires HealBlackhole marker'
Assert ($dcb -match 'Never overwrite versioned src with stale hybrid root leftovers') `
    'ship-gate requires hybrid no-overwrite'
Assert ($dcb -match 'mac/editor-launch.sh') `
    'ship-gate checks Mac editor-launch personal scrub'

$boot = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-boot.ps1') -Raw
$upd = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
$cps1 = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.ps1') -Raw
Assert ($boot -match 'Never overwrite versioned src with stale hybrid root leftovers') `
    'connect-boot hybrid sweep drops stale root instead of overwriting src'
Assert ($boot -match 'Prefer connect-version when that tree exists') `
    'connect-boot prefers stamped version tree over stale current.txt'
Assert ($upd -match 'Never overwrite versioned src with stale hybrid root leftovers') `
    'connect-update hybrid sweep drops stale root instead of overwriting src'
# HealBlackhole lives in sidecar; connect.ps1 boot uses BootReap only (Task 1 strip —
# do not re-add caller drive-bys). Ship gate: function + SIDECAR_HEAL_BLACKHOLE marker above.
Assert ($cps1 -match 'Invoke-CursorProxySidecarBootReap') `
    'connect.ps1 invokes BootReap (HealBlackhole is sidecar/boot-sidecar, not connect drive-by)'
$gmPs1 = Get-Content (Join-Path $RepoRoot 'scripts\client\git-mode.ps1') -Raw
Assert ($gmPs1 -match 'function Complete-CursorProxyAfterTunnel') `
    'git-mode Complete-CursorProxyAfterTunnel present'
Assert ($gmPs1 -notmatch 'Invoke-CursorProxySidecarHealBlackhole') `
    'git-mode must not drive-by HealBlackhole (sidecar owns blackhole heal)'
Assert ($side -match 'function Invoke-CursorProxySidecarHealBlackhole') `
    'sidecar still defines Invoke-CursorProxySidecarHealBlackhole'

# --- 4) Manual update must not stick on Press Enter ---
Assert ($ui -match 'Stop-Process -Id \$PID -Force') `
    'connect-ui hard-kills self after update apply (no stale Press Enter)'
Assert ($ui -match "Reason -eq 'update_manual_relaunch'") `
    'Wait-ConnectExit still knows update_manual_relaunch'
Assert ($ui -match 'Never fall through to a stale in-memory Wait-ConnectExit') `
    'manual update path documents no Press Enter fallthrough'

# --- 5) BusyBox sed \r must not truncate trailing "r" on identifiers ---
Assert ($dcb -match 'NEVER use sed .s/\\r\$') `
    'deploy documents BusyBox sed \\r = letter-r hazard'
Assert ($dcb -match 'perl -pi -e .s/\\r\$') `
    'deploy prefers perl for CR strip (not sed \\r)'
Assert ($dcb -match 'trailing-r strip corruption') `
    'ship-gate rejects truncated connect.ps1 identifiers'
Assert ($dcb -match 'Get-InteractiveLaptopUser') `
    'ship-gate requires intact Get-InteractiveLaptopUser in connect.ps1'

# --- 6) Versioned layout: no NEW.exe in OLD VerDir; no orphan cmd instant launcher ---
$upd = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-update.ps1') -Raw
$launch = Get-Content (Join-Path $RepoRoot 'publish\_setup-launch-body.ps1') -Raw
Assert ($upd -match 'foreign_verdir') `
    'update Sync skips Claude-Connect-NEW.exe inside OLD \{ver\} folders'
Assert ($upd -match 'Repair-ConnectVerDirLayout|Repair-ConnectAllVerDirLayouts') `
    'update repairs VerDir so only matching EXE + src sit outside root'
$envRepair = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-env-repair.ps1') -Raw
Assert ($envRepair -match 'function Repair-ConnectVerDirLayout') `
    'connect-env-repair owns VerDir-only-EXE layout healer'
Assert ($launch -match 'verdir_leaf_wins') `
    'setup forces DestExe name to match VerDir folder leaf'
Assert ($launch -match 'Repair-SetupVerDirContract') `
    'setup enforces VerDir src+EXE after instant launcher'
Assert ($launch -match 'Set-SrcVersionStamp') `
    'setup stamps src connect-version to folder leaf'
Assert ($launch -match 'Test-VersionSrcStructural') `
    'setup uses structural src check (folder leaf may differ from package)'
Assert ($launch -match 'instant reopen via current\.txt') `
    'setup instant launcher lives at root via current.txt'
Assert ($envRepair -match 'removed_foreign_or_launcher') `
    'VerDir repair removes stale .vbs/.cmd beside EXE'
Assert ($envRepair -match 'removed_extra_dir') `
    'VerDir repair removes unexpected directories (only src + EXE allowed)'
Assert ($envRepair -match 'removed_incomplete_orphan') `
    'VerDir repair-all drops incomplete src-only orphan trees'
Assert ($boot -match 'Repair-ConnectVerDirLayout') `
    'connect-boot heals VerDir stray scripts at boot'
Assert ($boot -match 'Length -gt 2000') `
    'connect-boot heals hybrid root when launched from src'
Assert ($upd -match 'dirLeaf -ne \$verLabel') `
    'update compares VerDir leaf to VersionLabel before promote'
Assert ($launch -match 'Claude-Connect\.vbs') `
    'setup-launch writes Claude-Connect.vbs instant reopen'
Assert ($launch -match 'wscript\.exe //B //Nologo') `
    'instant .cmd trampoline uses hidden wscript (no lingering console)'
Assert ($launch -notmatch 'start "Claude Connect" /D') `
    'instant launcher must not use titled start /D powershell (orphan cmd)'
$pub = Get-Content (Join-Path $RepoRoot 'publish\publish.ps1') -Raw
Assert ($pub -match 'versioned \{ver\}\\src') `
    'publish Desktop sync targets Claude-Connect\{ver}\src (not flat dump)'
Assert ($pub -match 'src \+ Claude-Connect-\{0\}\.exe only') `
    'publish reports VerDir contract EXE+src only'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} never-again gates passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
