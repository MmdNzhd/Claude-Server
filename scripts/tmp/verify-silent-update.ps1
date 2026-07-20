$ErrorActionPreference = 'Stop'
function Assert($cond, $msg) {
    if (-not $cond) { throw "FAIL: $msg" }
    Write-Host "PASS $msg"
}
$ui = Get-Content 'scripts/client/connect-ui.ps1' -Raw
Assert ($ui -match 'function Invoke-ConnectSilentUpdateCheck') 'Invoke-ConnectSilentUpdateCheck exists'
Assert ($ui -match 'UPDATE_SILENT skip reason=throttle') 'throttle log'
$cp = Get-Content 'scripts/client/windows/connect.ps1' -Raw
Assert ($cp -match "Trigger -eq 'auto'") 'auto trigger gate'
Assert ($cp -match 'Invoke-ConnectSilentUpdateCheck') 'wired in recovery'
$sh = Get-Content 'scripts/client/connect-ui.sh' -Raw
Assert ($sh -match 'invoke_connect_silent_update_check') 'mac helper'
$gm = Get-Content 'scripts/client/git-mode.sh' -Raw
Assert ($gm -match 'invoke_connect_silent_update_check') 'mac wired'
$upd = Get-Content 'scripts/client/mac/connect-update.sh' -Raw
Assert ($upd -match 'UPDATE_QUIET') 'mac quiet'
Assert ($upd -match '_update_msg') 'mac _update_msg'
$wupd = Get-Content 'scripts/client/windows/connect-update.ps1' -Raw
Assert ($wupd -match '\[switch\]\$Quiet') 'win Quiet switch'
Write-Host 'ALL ASSERTS PASS'
