#Requires -Version 5.1
# test-agent-path-diag-logs.ps1 - AGENT_PATH / SSH_ROLLUP / TUNNEL_PORT_MISSING contracts
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Agent-path + SSH latency diagnostic logs (static) ===' -ForegroundColor Cyan

$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$cp = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$le = Get-Content (Get-ServerFile 'server\laptop-exec.sh') -Raw
$uiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

Assert ($ui -match 'function Invoke-AgentPathProbe') 'Windows Invoke-AgentPathProbe defined'
Assert ($ui -match 'AGENT_PATH ok') 'Windows AGENT_PATH ok log'
Assert ($ui -match 'AGENT_PATH bad') 'Windows AGENT_PATH bad log'
Assert ($ui -match 'conf_empty|conf_port_closed|probe_fail') 'Windows AGENT_PATH bad reasons'
Assert ($ui -match 'Invoke-AgentPathProbe') 'Agent path probe callable'
Assert ($ui -match 'Update-SessionStatusLine') 'Status line host present'
$sc = Get-FunctionSource -Content $ui -Name 'Write-ConnectScorecard'
Assert ($sc -match 'port=') 'Write-ConnectScorecard emits port='
Assert ($sc -match 'auth_ms=') 'SCORECARD keeps auth_ms='
Assert ($sc -match 'agent_path=') 'SCORECARD can emit agent_path='
Assert ($sc -match 'LastAgentPathResult') 'SCORECARD reuses LastAgentPathResult'

Assert ($cp -match 'function Add-SshMsSample') 'Add-SshMsSample defined'
Assert ($cp -match 'function Write-SshLatencyRollupIfDue') 'Write-SshLatencyRollupIfDue defined'
Assert ($cp -match 'SSH_ROLLUP') 'SSH_ROLLUP log line'
Assert ($cp -match 'Add-SshMsSample') 'SshX records samples'
Assert ($cp -match 'over_2s=') 'SSH_ROLLUP over_2s field'
Assert ($cp -match 'over_5s=') 'SSH_ROLLUP over_5s field'

Assert ($gm -match 'ABORT_EMPTY') 'git-mode.ps1 knows ABORT_EMPTY'
Assert ($gm -match 'port_empty_recovered') 'git-mode.ps1 knows port_empty_recovered'
Assert ($gm -match 'port_mismatch_keep') 'git-mode.ps1 knows port_mismatch_keep'
Assert ($gm -match "PUSH_CONF signal=") 'git-mode.ps1 emits PUSH_CONF signal= WARN'
Assert ($gmSh -match "PUSH_CONF signal=|signal=ABORT_EMPTY|port_empty_recovered") 'git-mode.sh surfaces PushConf signals'

Assert ($le -match 'TUNNEL_PORT_MISSING') 'laptop-exec TUNNEL_PORT_MISSING'
Assert ($le -match 'deprecated_would_be') 'laptop-exec logs deprecated_would_be'
Assert ($le -match '\(_uid - 1000\) \* 10|20000 \+ \(_uid - 1000\)') 'fallback still (UID-1000)*10'

Assert ($uiSh -match 'port=') 'Mac scorecard includes port='
Assert ($mac -match 'SSH_ROLLUP|_ssh_rollup_if_due') 'Mac SSH_ROLLUP helper'
Assert ($mac -match 'AGENT_PATH|_agent_path_probe') 'Mac AGENT_PATH helper'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL PASS (agent-path diag log contracts)' -ForegroundColor Green
    exit 0
}
Write-Host "FAILED=$fail" -ForegroundColor Red
exit 1
