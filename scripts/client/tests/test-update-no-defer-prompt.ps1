#Requires -Version 5.1
# test-update-no-defer-prompt.ps1 - Optional update prompt is Y/N only; Defer removed everywhere.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== Update prompt: no Defer (static) ===' -ForegroundColor Cyan
Write-Host ''

$upd = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
$macUpd = Get-Content (Get-ClientFile 'mac\connect-update.sh') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$uiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw
$policyPath = Join-Path $RepoRoot 'scripts\server\client-update-policy.json'

Assert (Test-Path -LiteralPath $policyPath) 'client-update-policy.json exists'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
Assert (-not ($policy.PSObject.Properties.Name -contains 'defer_hours')) 'policy JSON has no defer_hours key'

# Windows optional prompt
Assert ($upd -match 'Update now\? \[Y\]es / \[N\]ot now:') 'Win prompt is [Y]es / [N]ot now'
Assert ($upd -notmatch '\[D\]efer') 'Win prompt has no [D]efer'
Assert ($upd -notmatch 'function Save-UpdateDefer') 'Save-UpdateDefer removed from connect-update.ps1'
Assert ($upd -notmatch 'function Test-UpdateDeferActive') 'Test-UpdateDeferActive removed from connect-update.ps1'
Assert ($upd -match 'Defer option removed') 'Win connect-update documents Defer removal'
Assert ($upd -match 'update-defer\.txt') 'Win connect-update clears leftover update-defer.txt'

# Mac optional prompt
Assert ($macUpd -match '\[y/N\]') 'Mac optional prompt shows [y/N]'
Assert ($macUpd -notmatch '\[y/N/D\]') 'Mac optional prompt no longer shows [y/N/D]'
Assert ($macUpd -notmatch 'D\|DEFER') 'Mac has no D|DEFER answer branch'
Assert ($macUpd -match 'Defer option removed') 'Mac connect-update documents Defer removal'
Assert ($macUpd -match 'update-defer\.txt') 'Mac connect-update clears leftover update-defer.txt'
Assert ($macUpd -match '(?m)^\s*ans=N\s*$') 'Mac optional ans defaults to N'
Assert ($macUpd -match '\[ -z "\$ans" \] && ans=N') 'Mac empty Enter keeps N'

# Manual update / setup-launch also drop stale defer stamps
Assert ($ui -match 'update-defer\.txt') 'connect-ui.ps1 clears update-defer.txt on manual update'
$manual = Get-FunctionSource -Content $ui -Name 'Invoke-ConnectManualUpdate'
if (-not $manual) {
    $manual = [regex]::Match($ui, '(?s)function Invoke-ConnectManualUpdate\s*\{[\s\S]*?\r?\n\}').Value
}
Assert ($manual -and ($manual -match 'update-defer\.txt')) 'Invoke-ConnectManualUpdate removes update-defer.txt'
Assert ($uiSh -match 'update-defer\.txt') 'connect-ui.sh clears update-defer.txt on manual update'

$setupLaunch = Join-Path $RepoRoot 'publish\_setup-launch-body.ps1'
if (Test-Path -LiteralPath $setupLaunch) {
    $sl = Get-Content -LiteralPath $setupLaunch -Raw
    Assert ($sl -match 'last-launch-dir\.txt') 'SFX setup-launch stamps last-launch-dir (launch context for updates)'
} else {
    Write-Host '  SKIP  publish/_setup-launch-body.ps1 missing' -ForegroundColor Yellow
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
