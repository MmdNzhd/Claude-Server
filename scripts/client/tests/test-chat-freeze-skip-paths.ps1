#Requires -Version 5.1
# test-chat-freeze-skip-paths.ps1 - Stage 6d: CURSOR_PROXY_CLEAR_SKIP + AUTH_SYNC_SKIP db_too_large + auto_relaunch gate
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== chat freeze skip paths (Stage 6d) ==="
Write-Host ""

$el = Get-Content (Join-Path $RepoRoot 'scripts\client\editor-launch.ps1') -Raw
$side = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\cursor-proxy-sidecar.ps1') -Raw
$auth = Get-Content (Join-Path $RepoRoot 'scripts\client\cursor-auth-laptop.ps1') -Raw
$conn = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.ps1') -Raw

Assert ($el -match 'CURSOR_PROXY_CLEAR_SKIP') 'editor-launch has CURSOR_PROXY_CLEAR_SKIP'
Assert ($el -match 'Test-MayClearCursorProxySettings') 'editor-launch has Test-MayClearCursorProxySettings'
Assert ($el -match 'action=repair_sidecar_only') 'editor-launch prefers repair when windows open'
Assert ($side -match 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open') 'sidecar Clear skips when windows open AND front up'
Assert ($side -match 'CURSOR_PROXY_CLEAR force reason=18998_down_windows_open') 'sidecar force-clears sticky when windows open AND 18998 down'
Assert ($side -match 'Repair-CursorProxySettingsToSidecar') 'sidecar repair helper exists'
Assert ($side -match 'action=repair_sidecar_only') 'sidecar clear logs repair_sidecar_only'
Assert ($side -match 'SIDECAR_BOOT_REAP skip reason=') 'boot reap preserves live fronts / open windows'
Assert ($side -match 'Detach-CursorProxySidecarJobProcess -Process \$pWd') 'watchdog gets job-handle detach so Connect exit keeps fronts' # regex \$ = literal $

Assert ($auth -match 'AUTH_SYNC_SKIP') 'auth has AUTH_SYNC_SKIP'
Assert ($auth -match 'db_too_large') 'auth skips reason=db_too_large'
Assert ($auth -match '524288000') 'auth threshold is 500 MiB (524288000)'
# Size skip is mid-session only: requires -not $Force (Force / golden_stale may bypass).
Assert ($auth -match '(?s)-not \$Force[\s\S]{0,120}\$dbBytes\s*-gt') 'db_too_large only on mid-session (!Force)'

# Stage 6 auto_relaunch must not regress
Assert ($conn -match 'auto_relaunch_skip reason=cursor_settings') 'auto_relaunch still gated on cursor_settings'
Assert ($conn -match 'AutoRelaunchAttempted') 'AutoRelaunchAttempted one-shot still present'

# Lifetime test still relevant
$life = Get-Content (Join-Path $RepoRoot 'scripts\client\tests\test-cursor-proxy-lifetime.ps1') -Raw
Assert ($life -match 'CURSOR_PROXY_CLEAR_SKIP') 'proxy lifetime test still covers CLEAR_SKIP'

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1