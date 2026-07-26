#Requires -Version 5.1
# test-empty-menu-manual-update.ps1
# Empty project list stays on a/u/q menu (no auto-Add); laptop SSH prepared before Add;
# manual update (u) helper exists on Win + Mac.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Empty menu + manual update (u) ===' -ForegroundColor Cyan

$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw
$uiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw

Assert ($win -match 'MENU_PROJECT_EMPTY') 'Win empty menu uses MENU_PROJECT_EMPTY prompt tag'
Assert ($win -match 'EMPTY_MENU: ensure_laptop_ssh_before_add') 'Win logs ensure_laptop_ssh_before_add before empty Add'
Assert ($win -match "Preparing laptop SSH \(admin prompt if needed\)") 'Win shows admin-prep message on empty Add'
Assert ($win -match "(?s)'a'\s*\{\s*Write-ConnectDecision 'project_menu' 'add_empty'[\s\S]{0,600}?Ensure-ServerSessionReady[\s\S]{0,200}?Add-Project") 'Win empty a: Ensure then Add'
Assert ($win -notmatch '(?s)if \(\$mounts\.Count -eq 0\) \{\s*if \(\$hiddenCount[\s\S]{0,200}?Ensure-ServerSessionReady\s*\$null = \(\$added = Add-Project\)') 'Win empty path no longer auto-Add without menu'
Assert ($win -match "'u'\s*\{[\s\S]{0,120}?Invoke-ConnectManualUpdate") 'Win project menu has u -> Invoke-ConnectManualUpdate'
Assert ($win -match 'a/e/d/c/g/u/q') 'Win help text includes u'

Assert ($ui -match 'function Invoke-ConnectManualUpdate') 'connect-ui.ps1 defines Invoke-ConnectManualUpdate'
Assert ($ui -match 'UPDATE_MANUAL') 'manual update logs UPDATE_MANUAL'
Assert ($ui -match "a add   u update   q quit") 'empty Write-ProjectTable footer has a/u/q'
Assert ($ui -match "a add   e edit   d delete   c config   g git   u update   q quit") 'full footer includes u update'
Assert ($ui -match 'update-check-miss\.txt') 'manual update clears miss cache'
$manual = [regex]::Match($ui, '(?s)function Invoke-ConnectManualUpdate\s*\{.*?\r?\n\}').Value
if ($manual.Length -lt 100) {
    $manual = [regex]::Match($ui, '(?s)function Invoke-ConnectManualUpdate\s*\{[\s\S]*?Wait-ConnectExit -Reason ''update_manual_relaunch''[\s\S]*?\r?\n\}').Value
}
Assert ($manual.Length -gt 100) 'extracted Invoke-ConnectManualUpdate body'
Assert ($manual -notmatch '& \$updateScript[^\r\n]*-Quiet') 'manual update must not pass -Quiet switch'
Assert ($manual -match '& \$updateScript -ScriptDir \$scriptDir') 'manual update calls connect-update.ps1'
Assert ($ui -match 'function Close-ConnectRelaunchHostConsole') 'update relaunch closes leftover connect.bat cmd host'
Assert ($ui -match 'session end \(update_relaunch\)') 'update relaunch skips blocking SSH log drain'
$wait = [regex]::Match($ui, '(?s)function Wait-ConnectExit\s*\{.*?^\}').Value
if ($wait.Length -lt 80) {
    $wait = Get-FunctionSource -Content $ui -Name 'Wait-ConnectExit'
}
Assert ($wait -and ($wait -match 'update_manual_relaunch')) 'Wait-ConnectExit knows update_manual_relaunch'
Assert ($wait -match 'skipEnter') 'Wait-ConnectExit has skipEnter fast path'
# Fast path must exit before Complete-ConnectLogAsyncDrain -Force (ordering).
$fastIdx = $wait.IndexOf('session end (update_relaunch)')
$drainIdx = $wait.IndexOf('Complete-ConnectLogAsyncDrain -Force')
Assert ($fastIdx -ge 0 -and $drainIdx -gt $fastIdx) 'update relaunch local session-end before Force drain path'

Assert ($mac -match 'MENU_PROJECT_EMPTY') 'Mac empty menu prompt tag'
Assert ($mac -match 'invoke_connect_manual_update') 'Mac calls invoke_connect_manual_update'
Assert ($mac -match 'EMPTY_MENU: add_after_prompt') 'Mac empty Add is after prompt'
Assert ($mac -match 'a/e/d/c/g/u/q') 'Mac help includes u'
Assert ($uiSh -match 'invoke_connect_manual_update\(\)') 'connect-ui.sh defines invoke_connect_manual_update'
Assert ($uiSh -match 'a add   u update   q quit') 'Mac empty footer a/u/q'
Assert ($uiSh -match 'u update') 'Mac full footer includes u update'

# Hard: empty list must not call Add-Project before Ensure in the empty branch ordering
$emptyBranch = [regex]::Match($win, '(?s)if \(\$mounts\.Count -eq 0\) \{.*?continue\s*\}\s*Write-GitModeBanner').Value
Assert ($emptyBranch.Length -gt 200) 'extracted Win empty mounts branch'
Assert ($emptyBranch -match 'Ensure-ServerSessionReady') 'empty branch still Ensures before Add'
$ensureIdx = $emptyBranch.IndexOf('Ensure-ServerSessionReady')
$addIdx = $emptyBranch.IndexOf('Add-Project')
Assert ($ensureIdx -ge 0 -and $addIdx -gt $ensureIdx) 'Ensure-ServerSessionReady before Add-Project in empty branch'
Assert ($emptyBranch -match 'Read-ConnectPrompt') 'empty branch waits for user key before Add'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All empty-menu / manual-update tests passed.' -ForegroundColor Green
    exit 0
}
Write-Host "Failed: $fail" -ForegroundColor Red
exit 1
