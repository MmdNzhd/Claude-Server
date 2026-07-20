# test-session-log-contracts.ps1 - session id + silent update source contracts
$ErrorActionPreference = 'Stop'
$client = Resolve-Path (Join-Path $PSScriptRoot '..')
$failed = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { Write-Host "PASS $msg" -ForegroundColor Green }
    else { Write-Host "FAIL $msg" -ForegroundColor Red; $script:failed++ }
}
$ui = Get-Content (Join-Path $client 'connect-ui.ps1') -Raw
$bat = Get-Content (Join-Path $client 'windows\connect.bat') -Raw
$win = Get-Content (Join-Path $client 'windows\connect.ps1') -Raw
$uiSh = Get-Content (Join-Path $client 'connect-ui.sh') -Raw
$mac = Get-Content (Join-Path $client 'mac\connect.sh') -Raw
$gitSh = Get-Content (Join-Path $client 'git-mode.sh') -Raw
Assert ($bat -match 'CLAUDE_CONNECT_RUN_ID') 'bat RUN_ID'
Assert ($ui -match 'Get-ConnectSessionId') 'Get-ConnectSessionId'
Assert ($ui -match 'sessions\.index') 'sessions.index'
Assert ($ui -match 'SESSION_FILTER') 'SESSION_FILTER'
Assert ($ui -match 'Invoke-ConnectSilentUpdateCheck') 'silent update fn'
Assert ($win -match 'Invoke-ConnectSilentUpdateCheck') 'win hooks silent'
Assert ($win -match 'TUNNEL_DROP reason=auto_reconnect') 'TUNNEL_DROP'
Assert ($mac -match 'CLAUDE_CONNECT_RUN_ID') 'mac RUN_ID'
Assert ($uiSh -match 'invoke_connect_silent_update_check') 'mac silent'
Assert ($uiSh -match 'SESSION_FILTER') 'mac SESSION_FILTER'
Assert ($gitSh -match 'invoke_connect_silent_update_check') 'git silent'
if ($failed -gt 0) { Write-Host "FAILED $failed"; exit 1 }

Assert ($ui -match 'FAIL EXIT reason=') 'Wait-ConnectExit logs FAIL EXIT on non-zero code'
Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'
Assert ($ui -match 'MULTI_INSTANCE: allowed') 'multi-instance allowed (no global mutex)'
Assert ($win -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN'
Assert ($win -match 'FAIL STEP name=') 'connect.ps1 logs FAIL STEP'
Assert ($win -match 'FAIL ADMIN_UAC') 'connect.ps1 logs FAIL ADMIN_UAC'
$upd = Get-Content (Join-Path $client 'windows\connect-update.ps1') -Raw
Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'
Assert ($bat -match 'FAIL UPDATE_BAT_EXIT') 'connect.bat logs FAIL UPDATE_BAT_EXIT'

Write-Host 'All session-log contracts passed' -ForegroundColor Green
