#Requires -Version 5.1
# test-connect-ui-menu-hard-batch.ps1
# HARD batch gate: connect-ui session footer, menu pipeline safety, multi-instance mutex,
# session/post-disconnect keys, interactive project menu logging, MENU_ABORT.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== HARD: connect-ui menu / session batch ===' -ForegroundColor White
Write-Host ''

$ui = Get-Content -LiteralPath (Get-ClientFile 'connect-ui.ps1') -Raw
$win = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw
$gm = Get-Content -LiteralPath (Get-ClientFile 'git-mode.ps1') -Raw
$el = Get-Content -LiteralPath (Get-ClientFile 'editor-launch.ps1') -Raw
$exeLaunch = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$exeBody = if (Test-Path -LiteralPath $exeLaunch) { Get-Content -LiteralPath $exeLaunch -Raw } else { '' }

$sessionBoxFn = Get-FunctionSource $ui 'Write-SessionBox'
$waitExitFn = Get-FunctionSource $ui 'Wait-ConnectExit'
$chooseFn = Get-FunctionSource $win 'Choose-Project'
$resolveFn = Get-FunctionSource $el 'Resolve-EditorChoice'
$postKeyFn = Get-FunctionSource $gm 'Read-PostDisconnectKey'
$mutexFn = Get-FunctionSource $ui 'Enter-ConnectSingleInstance'

Assert ($sessionBoxFn -and $sessionBoxFn -match 'H hygiene' -and $sessionBoxFn -notmatch 'G git') `
    'Write-SessionBox footer has H hygiene (G git removed)'

Assert ($waitExitFn -and $waitExitFn -match 'EXIT_WAIT: reason=' -and $waitExitFn -match 'FAIL EXIT reason=') `
    'Wait-ConnectExit logs EXIT_WAIT and FAIL EXIT on failure'
Assert ($waitExitFn -and $waitExitFn -match 'Press Enter to close') 'Wait-ConnectExit offers Press Enter close (P)'

Assert ($chooseFn -and ($chooseFn -match 'return ,')) 'Choose-Project uses unary comma pipeline-safe return'
Assert ($win -match '@\(Choose-Project -Mounts \$allMounts\)\[-1\]') 'connect.ps1 captures Choose-Project via @(..)[-1]'

Assert ($win -match '@\(Resolve-EditorChoice -CfgDir \$CfgDir\)\[-1\]') 'connect.ps1 captures Resolve-EditorChoice via @(..)[-1]'
Assert ($resolveFn -and ($resolveFn -match 'return ,')) 'Resolve-EditorChoice uses unary comma pipeline-safe return'

Assert (($exeBody -match 'MessageBox.*10 Claude Connect windows already open') -or ($ui -match '10 Claude Connect windows already open')) `
    'multi-instance cap surfaces 10 windows already open (MessageBox or console)'

Assert ($mutexFn -and $mutexFn -match 'MULTI_INSTANCE: acquired') 'Enter-ConnectSingleInstance logs MULTI_INSTANCE acquired'
Assert ($mutexFn -and $mutexFn -match 'mutex error \(block\)' -and $mutexFn -notmatch 'mutex error \(continue\)') `
    'Enter-ConnectSingleInstance mutex catch is fail-closed (block)'

$sessionKeyHay = [regex]::Match($win, '(?s)if \(\[Console\]::KeyAvailable\)[\s\S]{0,2200}break\s*\n\s*\}').Value
Assert (
    ($sessionKeyHay -match "resolved = 'r'" -and $sessionKeyHay -match "resolved = 'h'" -and $sessionKeyHay -match "resolved = 'o'" -and $sessionKeyHay -match "resolved = 'q'") -and
    ($sessionKeyHay -match '\[ConsoleKey\]::R') -and ($sessionKeyHay -match '\[ConsoleKey\]::H') -and
    ($sessionKeyHay -match '\[ConsoleKey\]::O') -and ($sessionKeyHay -match '\[ConsoleKey\]::Q') -and
    ($sessionKeyHay -match '\[ConsoleKey\]::Enter')
) 'session loop resolves R/H/O/Q (+ Enter for Q) with ConsoleKey VK fallback'

Assert (
    ($postKeyFn -match "return 'm'" -and $postKeyFn -match "return 'c'" -and $postKeyFn -match "return 'x'") -and
    ($postKeyFn -match '\[ConsoleKey\]::M') -and ($postKeyFn -match '\[ConsoleKey\]::C') -and ($postKeyFn -match '\[ConsoleKey\]::X') -and
    ($postKeyFn -match 'M = project menu\s+C = connect again\s+X = exit')
) 'Read-PostDisconnectKey resolves M/C/X with VK-safe ConsoleKey fallback'

Assert ($win -match 'INTERACTIVE: project_menu_shown') 'connect.ps1 logs INTERACTIVE project_menu_shown'
Assert ($win -match 'FAIL MENU_ABORT') 'empty Choose-Project logs FAIL MENU_ABORT'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
