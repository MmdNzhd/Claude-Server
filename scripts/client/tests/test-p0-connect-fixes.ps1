#Requires -Version 5.1
# test-p0-connect-fixes.ps1
# Source-level regression gate for P0 Connect fixes (20260720 sweep).
# Failures may be pending until parallel fix agents land.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0
$passed = 0
$softFailed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

function Assert-Soft([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  (soft) $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  (soft) $Msg" -ForegroundColor Yellow
        $script:softFailed++
    }
}

function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== P0 Connect fixes (source contracts) ===' -ForegroundColor White
Write-Host ''

$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connectUi = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$winConnect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$editorLaunch = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw
$ver = Get-ConnectVersion
$winVerFile = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
$macVerFile = (Get-Content (Get-ClientFile 'mac\connect-version.txt') -Raw).Trim()
$macConnect = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

Write-Host '--- 1) Write-TunnelDropLog TunnelPid (not $Pid shadow) ---' -ForegroundColor Cyan
$dropFn = Get-FunctionSource $gitMode 'Write-TunnelDropLog'
Assert ($dropFn -match '\[int\]\$TunnelPid') 'Write-TunnelDropLog declares [int]$TunnelPid param'
Assert ($dropFn -notmatch '(?m)^\s*\[int\]\$Pid\s*=') 'Write-TunnelDropLog does not declare [int]$Pid param'

Write-Host '--- 2) Acquire-TunnelPort peer-live skip ---' -ForegroundColor Cyan
$acquireFn = Get-FunctionSource $gitMode 'Acquire-TunnelPort'
Assert (
    ($gitMode -match 'skip_peer_live|ACQUIRE_SKIP|peer_live') -or
    ($acquireFn -match 'skip_peer_live|ACQUIRE_SKIP|peer_live')
) 'git-mode.ps1 skips peer-live probe (skip_peer_live or ACQUIRE_SKIP)'

Write-Host '--- 3) Launch-RemoteEditor fail-closed ---' -ForegroundColor Cyan
$launchFn = Get-FunctionSource $editorLaunch 'Launch-RemoteEditor'
Assert (
    ($launchFn -match 'LAUNCH_FAIL:\s*started_but_no_process') -or
    ($launchFn -match 'PROC_START_FAIL:\s*mode=elevated_launch_task') -or
    ($launchFn -match 'no_process')
) 'Launch-RemoteEditor fail-closed markers present'

Write-Host '--- 4) Invoke-ConnectSilentUpdateCheck tunnel/stamp safety ---' -ForegroundColor Cyan
$silentFn = Get-FunctionSource $connectUi 'Invoke-ConnectSilentUpdateCheck'
Assert (
    ($silentFn -match 'tunnel_down|reason=tunnel_down|UPDATE_SILENT skip reason=.*tunnel') -or
    ($silentFn -match 'stamp_only|WriteAllText[\s\S]{0,400}\$result\s*-eq\s*''ok''') -or
    ($silentFn -notmatch '(?s)finally[\s\S]*WriteAllText[\s\S]*stateFile')
) 'Invoke-ConnectSilentUpdateCheck skips when tunnel down or stamps only on success'

Write-Host '--- 5) Begin-ConnectRecovery no silent update at start ---' -ForegroundColor Cyan
$recoveryFn = Get-FunctionSource $winConnect 'Begin-ConnectRecovery'
$recoveryEarly = ''
if ($recoveryFn -match '(?s)^function\s+Begin-ConnectRecovery\s*\{(.*)') {
    $recoveryEarly = $Matches[1].Substring(0, [Math]::Min(900, $Matches[1].Length))
}
Assert ($recoveryEarly -notmatch 'Invoke-ConnectSilentUpdateCheck') 'Begin-ConnectRecovery does not call silent update at function start'

Write-Host "--- 6) CONNECT_VERSION consistency ($ver) ---" -ForegroundColor Cyan
Assert ($ver -match '^\d{8}\.\d+$') "connect.ps1 ConnectVersion is dated ($ver)"
Assert ($winVerFile -eq $ver) "windows/connect-version.txt matches connect.ps1 ($ver vs $winVerFile)"
Assert ($macVerFile -eq $ver) "mac/connect-version.txt matches connect.ps1 ($ver vs $macVerFile)"
Assert ($macConnect -match "CONNECT_VERSION='$([regex]::Escape($ver))'") "mac/connect.sh CONNECT_VERSION matches connect.ps1 ($ver)"

Write-Host '--- 7) claude-mount git hide fail-fast (soft) ---' -ForegroundColor Cyan
$hasTripleSleep = (
    ($mount -match '\$n\s*-lt\s*3') -and
    ($mount -match 'Start-Sleep\s+-Seconds\s+2|sleep\s+2')
)
Assert-Soft (-not $hasTripleSleep) 'claude-mount hide retries are fail-fast (not 3x long sleep)'

Write-Host ''
Write-Host ("P0 connect fixes: {0} passed, {1} failed, {2} soft-pending" -f $passed, $failed, $softFailed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
