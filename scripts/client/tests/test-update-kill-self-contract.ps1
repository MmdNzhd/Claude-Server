#Requires -Version 5.1
# test-update-kill-self-contract.ps1 - Manual update apply kills stale in-memory UI (exit 2 + bat relaunch).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== Update kill_self + relaunch contracts (static) ===' -ForegroundColor Cyan
Write-Host ''

$upd = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

# connect-update.ps1 apply handoff
Assert ($upd -match 'kill_self skip_stale_press_enter') 'connect-update logs kill_self skip_stale_press_enter'
Assert ($upd -match 'bat_relaunch_from_update_self') 'connect-update spawns bat_relaunch_from_update_self'
Assert ($upd -match '\[Environment\]::Exit\(2\)') 'connect-update uses [Environment]::Exit(2) hard exit'
Assert ($upd -match 'CLAUDE_CONNECT_MANUAL_UPDATE') 'connect-update detects CLAUDE_CONNECT_MANUAL_UPDATE'
Assert ($upd -match '\$calledFromLiveUi') 'connect-update has calledFromLiveUi detection'
Assert ($upd -match 'Wait-ConnectExit -ErrorAction SilentlyContinue') 'calledFromLiveUi probes Wait-ConnectExit in caller'

$detectStart = $upd.IndexOf('$calledFromLiveUi = $false')
$detectEnd = if ($detectStart -ge 0) { $upd.IndexOf('if ($calledFromLiveUi) {', $detectStart) } else { -1 }
$detectBlock = if ($detectStart -ge 0 -and $detectEnd -gt $detectStart) {
    $upd.Substring($detectStart, $detectEnd - $detectStart)
} else { '' }
Assert ($detectBlock -match "CLAUDE_CONNECT_MANUAL_UPDATE -eq '1'") 'calledFromLiveUi detection honors CLAUDE_CONNECT_MANUAL_UPDATE=1'

$killStart = $upd.IndexOf('if ($calledFromLiveUi) {')
$killEnd = if ($killStart -ge 0) { $upd.IndexOf('[Environment]::Exit(2)', $killStart) } else { -1 }
$killBlock = if ($killStart -ge 0 -and $killEnd -gt $killStart) {
    $upd.Substring($killStart, $killEnd - $killStart + '[Environment]::Exit(2)'.Length)
} else { '' }
Assert ($killBlock.Length -gt 200) 'extracted if ($calledFromLiveUi) -> Exit(2) block'
if ($killBlock.Length -gt 200) {
    Assert ($killBlock -match 'Start-Process -FilePath \$bat') 'kill block relaunches connect.bat before exit'
    Assert ($killBlock -match 'Stop-Process -Id \$PID') 'kill block schedules self Stop-Process'
}

# connect-ui.ps1 manual update + Wait-ConnectExit fast path
Assert ($ui -match 'function Invoke-ConnectManualUpdate') 'connect-ui defines Invoke-ConnectManualUpdate'
$manual = Get-FunctionSource -Content $ui -Name 'Invoke-ConnectManualUpdate'
if (-not $manual) {
    $manual = [regex]::Match($ui, '(?s)function Invoke-ConnectManualUpdate\s*\{[\s\S]*?\r?\n\}').Value
}
Assert ($manual -and ($manual -match "CLAUDE_CONNECT_MANUAL_UPDATE = '1'")) 'Invoke-ConnectManualUpdate sets CLAUDE_CONNECT_MANUAL_UPDATE=1'
Assert ($manual -and ($manual -match 'Remove-Item Env:CLAUDE_CONNECT_MANUAL_UPDATE')) 'Invoke-ConnectManualUpdate clears CLAUDE_CONNECT_MANUAL_UPDATE in finally'

$wait = Get-FunctionSource -Content $ui -Name 'Wait-ConnectExit'
if (-not $wait) {
    $wait = [regex]::Match($ui, '(?s)function Wait-ConnectExit\s*\{.*?^\}').Value
}
Assert ($wait -and ($wait -match 'update_relaunch')) 'Wait-ConnectExit knows update_relaunch reason'
Assert ($wait -and ($wait -match 'update_manual_relaunch')) 'Wait-ConnectExit knows update_manual_relaunch reason'
Assert ($wait -and ($wait -match 'session end \(update_relaunch\)')) 'Wait-ConnectExit logs session end (update_relaunch)'
Assert ($wait -and ($wait -match '\$skipEnter')) 'Wait-ConnectExit has skipEnter fast path'

$fastIdx = if ($wait) { $wait.IndexOf('session end (update_relaunch)') } else { -1 }
$drainIdx = if ($wait) { $wait.IndexOf('Complete-ConnectLogAsyncDrain -Force') } else { -1 }
Assert ($fastIdx -ge 0 -and $drainIdx -gt $fastIdx) 'update_relaunch fast path before Force log drain'

# Mid-session Quiet auto-update retired (manual_only). Wait-ConnectExit update_relaunch
# remains for apply/relaunch handoff; silent path must NOT call it.
Assert ($ui -match 'UPDATE_SILENT skip reason=manual_only') 'silent update path is manual_only (no mid-session Quiet apply)'
Assert ($ui -notmatch "Invoke-ConnectSilentUpdateCheck[\s\S]{0,400}Wait-ConnectExit -Reason 'update_relaunch'") `
    'silent update path does not call Wait-ConnectExit update_relaunch'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
