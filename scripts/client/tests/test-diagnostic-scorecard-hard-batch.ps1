#Requires -Version 5.1
# test-diagnostic-scorecard-hard-batch.ps1
# HARD batch gate: diagnostic verdicts, MOUNT_PENDING/mountPendingLight, AGENT_PATH,
# STALE-SHADOW canon vs shadow + deploy ship-gates, SSH_ROLLUP/Add-SshMsSample,
# scorecard agent_path contracts, dual-UI already_on_folder false-positive guard.
# Callers: manual / CI (NOT wired into run-all.ps1 by design for this task).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== HARD: diagnostic + scorecard batch ===' -ForegroundColor Cyan
Write-Host ''

# --- Live Get-ConnectProblemVerdict (canon scripts/client/connect-diagnostic.ps1) ---
. (Get-ClientFile 'connect-diagnostic.ps1')

Assert (Get-Command Get-ConnectProblemVerdict -ErrorAction SilentlyContinue) `
    'Get-ConnectProblemVerdict defined in canon diagnostic'

$vPending = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'started_in_background'
    MountPoint = ''; PathExists = ''; ServerReachable = $true
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true
    OnFolder = $false; AgentHome = $false; WindowOpen = $false; DidLaunch = $false
}
Assert ($vPending.Code -eq 'MOUNT_PENDING' -and $vPending.Severity -eq 'INFO') `
    'MOUNT_PENDING is INFO when bg mount has no live mount truth yet'

$vBgOnFolder = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'started_in_background'
    MountPoint = 'yes'; PathExists = 'yes'; ServerReachable = $true
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true
    OnFolder = $true; AgentHome = $false; WindowOpen = $true
}
Assert ($vBgOnFolder.Code -eq 'CURSOR_ON_FOLDER_OK') `
    'bg mount + mountpoint=yes + on_folder => CURSOR_ON_FOLDER_OK (not MOUNT_FAILED)'

# --- mountPendingLight light-path contracts (canon diagnostic + connect.ps1) ---
$diagCanon = Get-Content (Get-ClientFile 'connect-diagnostic.ps1') -Raw
$winConnect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

Assert ($diagCanon -match 'mountPendingLight' -and $diagCanon -match 'skipped=light_session_open') `
    'canon diagnostic mountPendingLight skips heavy probes on happy SESSION_OPEN'
Assert ($winConnect -match 'mountPendingLight' -and $winConnect -match '\$lightOpen = \(\$Phase -eq ''SESSION_OPEN''') `
    'connect.ps1 lightOpen allows bg-mount + on_folder without false MOUNT_FAILED'

# --- AGENT_PATH ok/bad reason contracts (connect-ui.ps1) ---
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

Assert ($ui -match 'AGENT_PATH ok') 'connect-ui emits AGENT_PATH ok log line'
Assert ($ui -match 'conf_empty|conf_port_closed|probe_fail') `
    'AGENT_PATH bad reasons are explicit (conf_empty|conf_port_closed|probe_fail)'

# --- STALE-SHADOW: canon ships real body; windows/ shadow is repo-dev only ---
$diagShadow = Get-Content (Get-ClientFile 'windows\connect-diagnostic.ps1') -Raw
$dcb = Get-Content (Get-ServerFile 'server\commands\deploy-client-bundle.sh') -Raw

Assert ($diagCanon -notmatch 'STALE-SHADOW REPLACED') 'canon connect-diagnostic.ps1 is not a shadow wrapper'
Assert ($diagShadow -match 'STALE-SHADOW REPLACED') 'windows/connect-diagnostic.ps1 remains repo-dev shadow only'
Assert ($dcb -match 'ship-gate: staged connect-diagnostic\.ps1 is STALE-SHADOW') `
    'deploy-client-bundle fail-closed blocks STALE-SHADOW diagnostic in flat bundle'

# --- SSH_ROLLUP / Add-SshMsSample ring buffer (connect.ps1) ---
Assert ($winConnect -match 'function Add-SshMsSample' -and $winConnect -match 'SSH_ROLLUP' `
    -and $winConnect -match 'over_2s=' -and $winConnect -match 'over_5s=') `
    'Add-SshMsSample feeds SSH_ROLLUP with over_2s/over_5s buckets'

# --- Scorecard agent_path contract (live fixture on extracted Write-ConnectScorecard) ---
$scSrc = Get-FunctionSource -Content $ui -Name 'Write-ConnectScorecard'
Assert ($scSrc -match 'LastAgentPathResult' -and $scSrc -match 'agent_path=') `
    'Write-ConnectScorecard sources LastAgentPathResult and agent_path= field'

$script:ScorecardLines = New-Object System.Collections.Generic.List[string]
function Write-ConnectLog {
    param([string]$Message, [string]$Level = 'INFO')
    $script:ScorecardLines.Add([string]$Message)
}
. ([scriptblock]::Create($scSrc))

$script:LastAgentPathResult = @{ Ok = $true; ConfPort = '21004'; Reason = '' }
$script:ConnectVersion = 'test-diag-scorecard-hard'
$script:ScorecardLines.Clear()
Write-ConnectScorecard -Phase 'end'
$scLine = ($script:ScorecardLines | Where-Object { $_ -match 'SCORECARD' } | Select-Object -First 1)
Assert ($scLine -match 'agent_path=ok' -and $scLine -match 'conf_port=21004') `
    "SCORECARD live: agent_path=ok conf_port= emitted (got: $scLine)"

# --- Dual-UI false-positive: skip press-O warn when already on folder (Win + Mac) ---
$macConnect = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

Assert ($winConnect -match 'skip_press_o_warn reason=already_on_folder') `
    'Windows skips press-O recovery warn when already on project folder'
Assert ($macConnect -match 'skip_press_o_warn reason=already_on_folder') `
    'Mac skips press-O recovery warn when already on project folder'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'HARD diagnostic+scorecard batch: ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host "$fail test(s) failed." -ForegroundColor Red
exit 1
