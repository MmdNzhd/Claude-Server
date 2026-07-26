#Requires -Version 5.1
# RED contracts (Task 7): log-sync fast mkdir must not embed find -mtime retention;
# Complete-ConnectLogAsyncDrain must preserve/restore ConnectLogSyncNeeded when Force sync fails.
# Plan: docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md Task 7

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Log-sync fast mkdir (no find) + Needed on Force fail ===' -ForegroundColor White

$uiPath = Get-ClientFile 'connect-ui.ps1'
Assert (Test-Path -LiteralPath $uiPath) "connect-ui.ps1 exists via Get-ClientFile ($uiPath)"
$ui = Get-Content -LiteralPath $uiPath -Raw

Assert ($ui -match 'LogSyncFastMkdir') 'LogSyncFastMkdir budget symbol present'

# Non-Force / fast $mk assignment must NOT embed find ... mtime
$m = [regex]::Match($ui, '\$mk\s*=\s*''([^'']+)''')
Assert $m.Success 'fast $mk single-quoted assignment found'
if ($m.Success) {
    $mkCmd = $m.Groups[1].Value
    Write-Host ("  note  `$mk = '{0}'" -f $mkCmd) -ForegroundColor DarkGray
    Assert ($mkCmd -notmatch 'find\s+.*mtime') 'fast $mk must not embed find ... mtime retention'
}

# Scope Needed restore to Complete-ConnectLogAsyncDrain (file-wide match is a false green)
$drain = Get-FunctionSource -Content $ui -Name 'Complete-ConnectLogAsyncDrain'
Assert (-not [string]::IsNullOrWhiteSpace($drain)) 'Complete-ConnectLogAsyncDrain extractable via Get-FunctionSource'
if ($drain) {
    $clearsBeforeForce = [regex]::IsMatch(
        $drain,
        '(?s)ConnectLogSyncNeeded\s*=\s*\$false.{0,800}Sync-ConnectLogToServer\s+-Force'
    )
    $restoresNeeded = [regex]::IsMatch($drain, 'ConnectLogSyncNeeded\s*=\s*\$true')
    Assert ((-not $clearsBeforeForce) -or $restoresNeeded) `
        'Complete-ConnectLogAsyncDrain must restore ConnectLogSyncNeeded=$true when Force sync fails (or not clear Needed before Force)'
    if ($clearsBeforeForce -and -not $restoresNeeded) {
        Write-Host '  note  clears Needed=$false before Sync -Force; no restore=$true in drain body' -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host ("Result: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -eq 0) { exit 0 }
exit 1
