# test-sshx-ntstatus-retry.ps1 - Precise×6: SshX retries STATUS_DLL_INIT_FAILED; Sync does not
# treat spawn-fail TCP probes as forward-dead; PUSH_CONF NTSTATUS is INFO after retries.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== SSH NTSTATUS retry / inconclusive TCP (static) ===' -ForegroundColor Cyan

$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

Assert ($win -match 'SSH_SPAWN_RETRY') 'SshX logs SSH_SPAWN_RETRY'
Assert ($win -match '\$result\.Exit -lt 0') 'SshX retries when Exit -lt 0'
Assert ($win -match "recovering session \(down mount, restart tunnel\)' 'INFO'") 'recovery announce is INFO (zero-noise)'
Assert ($gm -match 'probe_inconclusive') 'Test-TunnelPortTcpOpen / Sync use probe_inconclusive'
Assert ($gm -match 'LastTunnelTcpProbeInconclusive') 'inconclusive flag set'
Assert ($gm -match 'return \$false\s*\r?\n\s*\}\s*\r?\n\s*\$script:LastTunnelTcpProbeInconclusive = \$false|probe_inconclusive[\s\S]{0,200}return \$false') 'inconclusive TCP returns false (not optimistic-open)'
Assert ($gm -match 'port release inconclusive') 'Clear treats inconclusive as released'
Assert ($gm -match "refuse_spawn reason=stale_port_busy_no_rebind[^\r\n]+'INFO'") 'no_rebind soft fail is INFO'
Assert ($gm -match 'PUSH_CONF spawn_retry') 'PUSH_CONF retries spawn fails'
Assert ($gm -match "pushExit -lt 0\) \{ 'INFO' \}") 'PUSH_CONF NTSTATUS fail is INFO'
Assert ($gm -match 'MOUNT_DOWN\|CLEAR_') 'MOUNT_DOWN NTSTATUS fail demoted to INFO'

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
