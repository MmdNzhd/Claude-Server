#Requires -Version 5.1
# test-update-relaunch-hard-batch.ps1
#
# Hard batch: update apply + relaunch handoff (deeper than single-topic contract tests).
# Covers exit=2 need_relaunch, kill_self / stale Press Enter, Quiet+UPDATE_YES, apply paths
# (versioned, flat_layout, swap_inplace, foreign_verdir), mutex/cmd cleanup, optional policy, no Defer.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== Update relaunch hard batch (apply + handoff contracts) ===' -ForegroundColor Cyan
Write-Host ''

$upd = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$policyPath = Join-Path $RepoRoot 'scripts\server\client-update-policy.json'

# --- 1–2: exit 2 need_relaunch handoff chain ---
Assert (
    ($upd -match 'applied_ok need_relaunch exit=2') -and
    ($upd -match 'UPDATE_EXIT exit=2 need_relaunch pid=\$PID')
) 'apply success logs applied_ok + UPDATE_EXIT exit=2 need_relaunch breadcrumbs'

$idxApplied = $upd.LastIndexOf('applied_ok need_relaunch exit=2')
$idxRelease = $upd.LastIndexOf('Release-ConnectSingleInstanceForUpdateRelaunch')
$idxKillSelf = $upd.LastIndexOf('kill_self skip_stale_press_enter')
$idxHardExit = $upd.LastIndexOf('[Environment]::Exit(2)')
Assert (
    ($idxApplied -ge 0) -and ($idxRelease -gt $idxApplied) -and ($idxKillSelf -gt $idxRelease) -and ($idxHardExit -gt $idxKillSelf)
) 'apply tail order: applied_ok -> Release mutex -> kill_self -> Environment.Exit(2)'

# --- 4–6: kill_self / stale Press Enter (connect-update + connect-ui) ---
$killStart = $upd.IndexOf('if ($calledFromLiveUi) {')
$killEnd = if ($killStart -ge 0) { $upd.IndexOf('[Environment]::Exit(2)', $killStart) } else { -1 }
$killBlock = if ($killStart -ge 0 -and $killEnd -gt $killStart) {
    $upd.Substring($killStart, $killEnd - $killStart + '[Environment]::Exit(2)'.Length)
} else { '' }
Assert (
    ($killBlock.Length -gt 200) -and
    ($killBlock -match 'kill_self skip_stale_press_enter') -and
    ($killBlock -match 'bat_relaunch_from_update_self') -and
    ($killBlock -match 'Stop-Process -Id \$PID')
) 'calledFromLiveUi block relaunches bat, logs kill_self, schedules self Stop-Process, hard Exit(2)'

$wait = Get-FunctionSource -Content $ui -Name 'Wait-ConnectExit'
Assert (
    $wait -and
    ($wait -match '\$skipEnter\s*=') -and
    ($wait -match "update_manual_relaunch") -and
    ($wait -match "update_relaunch") -and
    ($wait -match 'session end \(update_relaunch\)')
) 'Wait-ConnectExit skipEnter fast path for update_* relaunch (no Press Enter drain)'

$manual = Get-FunctionSource -Content $ui -Name 'Invoke-ConnectManualUpdate'
Assert (
    $manual -and
    ($manual -match "CLAUDE_CONNECT_MANUAL_UPDATE = '1'") -and
    ($manual -match 'Never fall through to a stale in-memory Wait-ConnectExit')
) 'Invoke-ConnectManualUpdate flags manual update and forbids stale Press Enter fallthrough'

# --- 7–8: Quiet / UPDATE_UI=0 optional policy + UPDATE_YES automation apply ---
Assert (
    ($upd -match '\$autoYes = \(\$env:CLAUDE_CONNECT_UPDATE_YES -eq ''1''\)') -and
    ($upd -match '\$uiOff = \(\$env:CLAUDE_CONNECT_UPDATE_UI -eq ''0''\)') -and
    ($upd -match 'if \(\(\$script:Quiet -or \$uiOff\) -and -not \$autoYes\)') -and
    ($upd -match 'UPDATE_OPTIONAL_ANSWER source=CLAUDE_CONNECT_UPDATE_YES')
) 'Quiet mid-session skips optional unless CLAUDE_CONNECT_UPDATE_YES auto-applies'

Assert (
    ($upd -match 'UPDATE_OPTIONAL_SKIP reason=\{0\}') -and
    ($upd -match "'silent'") -and
    ($upd -match "'update_ui_0'") -and
    ($upd -match '\$forceApply = \(\$mode -eq ''force''\) -and \$forceReq')
) 'optional Quiet logs silent skip; force apply gated on mode=force AND force_min'

if (Test-Path -LiteralPath $policyPath) {
    $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
    $mode = [string]$policy.mode
    Assert ($mode -eq 'optional' -or $mode -eq 'force') 'server client-update-policy.json mode is optional or force'
    if ($mode -eq 'optional') {
        $minRaw = $null
        try { $minRaw = $policy.force_min_version } catch { $minRaw = $null }
        $minStr = if ($null -eq $minRaw) { '' } else { [string]$minRaw }
        Assert ([string]::IsNullOrWhiteSpace($minStr) -or $minStr -eq 'null') 'optional mode keeps force_min_version null/empty'
    } else {
        Assert (-not [string]::IsNullOrWhiteSpace([string]$policy.force_min_version)) 'force mode has force_min_version set'
        Assert ([string]$policy.force_min_version -eq [string]$policy.latest) 'force mode force_min_version matches latest'
    }
} else {
    Assert $false 'server client-update-policy.json missing'
}

# --- 9–12: apply paths (foreign_verdir, versioned, swap_inplace, flat_layout) ---
$syncFn = Get-FunctionSource -Content $upd -Name 'Sync-ConnectExeBesideClient'
Assert (
    $syncFn -and
    ($syncFn -match 'foreign_verdir') -and
    ($syncFn -match '\$dirLeaf -ne \$verLabel')
) 'Sync-ConnectExeBesideClient skips foreign_verdir (no NEW.exe into OLD VerDir)'

Assert (
    ($upd -match 'Set-ConnectInstallCurrent -Root \$versionedRoot -Ver \$remoteVer') -and
    ($upd -match 'Remove-Item -LiteralPath \(Join-Path \$versionedRoot ''current\.txt''\)') -and
    $upd.Contains('$env:CLAUDE_CONNECT_VER_DIR = $newVerDir') -and
    ($upd -match 'versioned_apply ok remote=\{0\} src=\{1\}')
) 'versioned_apply sets install-current + CLAUDE_CONNECT_VER_DIR, logs versioned_apply ok'

$swapFn = Get-FunctionSource -Content $upd -Name 'Swap-LiveDir'
Assert (
    $swapFn -and
    ($swapFn -match 'in use\|being used by another process') -and
    ($swapFn -match 'swap_inplace_ok reason=live_in_use') -and
    ($swapFn -match 'UPDATE_EXIT pending=2 reason=swap_inplace_live_in_use')
) 'Swap-LiveDir inplace fallback when live folder in use still pending exit=2 relaunch'

Assert (
    ($upd -match '\$windowsDir -eq \$packageRoot') -and
    ($upd -match 'flat_layout staging_ext=\$ext \(bak outside live root\)')
) 'flat Desktop layout stages bak/new outside live root (flat_layout staging_ext)'

# --- 13: Release-ConnectSingleInstanceForUpdateRelaunch stale session cleanup ---
$relFn = Get-FunctionSource -Content $upd -Name 'Release-ConnectSingleInstanceForUpdateRelaunch'
Assert (
    $relFn -and
    ($relFn -match 'connect\.ps1') -and
    ($relFn -match 'relaunch_prep stop_connect_ps1') -and
    ($relFn -match "parent\.Name -eq 'cmd\.exe'") -and
    ($relFn -match 'connect\.bat') -and
    ($relFn -match 'relaunch_prep stop_stale_cmd_window')
) 'Release-ConnectSingleInstanceForUpdateRelaunch stops stale connect.ps1 and parent cmd /K connect.bat'

# --- 14: no defer prompt (Y/N only) ---
Assert (
    ($upd -match 'Update now\? \[Y\]es / \[N\]ot now:') -and
    ($upd -notmatch '\[D\]efer') -and
    ($upd -notmatch 'function Test-UpdateDeferActive') -and
    ($upd -match 'update-defer\.txt') -and
    ($upd -match 'Defer option removed')
) 'optional prompt is Y/N only; defer helpers removed; stale update-defer.txt cleared'

Write-Host ''
Write-Host ("Assert count: {0}" -f $Pass) -ForegroundColor DarkGray
Write-Host ("Script: {0}" -f $MyInvocation.MyCommand.Path) -ForegroundColor DarkGray
if ($Fail -eq 0) {
    Write-Host ("All {0} hard-batch contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
