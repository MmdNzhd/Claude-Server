#Requires -Version 5.1
# test-wait-local-r-ownership.ps1 - Wait Gate A: spawn pid must own local -R (Task 2)
# Locks D3 + S2 token local_r_not_owned (Win Wait, Mac wait).
# Behavioral: Test-TunnelUp=$true + empty local PIDs => Wait false; pid in list => true.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== Wait local -R ownership (Gate A / local_r_not_owned) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw

# --- Static ---
$waitFn = Get-FunctionSource -Content $gmSrc -Name 'Wait-ForTunnelUp'
Assert (-not [string]::IsNullOrWhiteSpace($waitFn)) 'extracted Wait-ForTunnelUp'
Assert ($waitFn -match 'Get-LocalTunnelSshPids') 'Wait body calls Get-LocalTunnelSshPids'
Assert ($waitFn -match 'local_r_not_owned') 'Wait emits local_r_not_owned'
$pidsRel = $waitFn.IndexOf('Get-LocalTunnelSshPids')
$trueRel = $waitFn.LastIndexOf('return $true')
Assert ($pidsRel -ge 0 -and $trueRel -gt $pidsRel) `
    'Get-LocalTunnelSshPids appears before return $true in Wait'

Assert ($shSrc -match 'local_r_not_owned') 'Mac local_r_not_owned token'
Assert ($shSrc -match 'wait_for_tunnel_up\s*\(') 'Mac wait_for_tunnel_up exists'
# ensure uses poll_tunnel_with_progress — Gate A must live there too
$pollSrc = ''
if ($shSrc -match '(?s)poll_tunnel_with_progress\(\)\s*\{.*?^\}') {
    $pollSrc = $Matches[0]
}
Assert ($shSrc -match 'get_local_tunnel_ssh_pids') 'Mac get_local_tunnel_ssh_pids available'
Assert (
    ($shSrc -match '(?s)wait_for_tunnel_up\(\)\s*\{.*?local_r_not_owned') -or
    ($shSrc -match '(?s)poll_tunnel_with_progress\(\)\s*\{.*?local_r_not_owned')
) 'Mac wait/poll body contains local_r_not_owned'

# --- Behavioral ---
Write-Host '-- behavioral Wait Gate A --' -ForegroundColor White

. $gmPath

$script:Port = 20021
$script:gmLogs = New-Object System.Collections.Generic.List[string]
$script:LocalPidStub = @()

function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    [void]$script:gmLogs.Add($Message)
}
function Test-TunnelUp { param([int]$Retries = 1) $true }
function Get-LocalTunnelSshPids { param([int]$TargetPort) @($script:LocalPidStub) }
function Release-StaleTunnelPort { }
# Keep Gate A; only accelerate the 12-attempt loop
function Start-Sleep { param($Seconds, $Milliseconds) return }

$spawnPid = 4242
$fake = [pscustomobject]@{ Id = $spawnPid; HasExited = $false }

# Negative: banner up, empty local -R PID list => fail
$script:LocalPidStub = @()
$script:gmLogs.Clear()
$negOk = $false
try {
    $negOk = Wait-ForTunnelUp -TunnelProc $fake -Quiet
} catch {
    # Typed Process param may reject PSCustomObject; use a Process stand-in
    $fake = Get-Process -Id $PID
    $spawnPid = [int]$fake.Id
    $script:LocalPidStub = @()
    $script:gmLogs.Clear()
    $negOk = Wait-ForTunnelUp -TunnelProc $fake -Quiet
}
Assert (-not $negOk) 'behavioral: Test-TunnelUp=true + empty local PIDs => Wait false'
$negLog = ($script:gmLogs -join "`n")
Assert ($negLog -match 'local_r_not_owned') 'behavioral: empty PIDs logs local_r_not_owned'

# Positive: local PIDs contain spawn pid => true
$script:LocalPidStub = @($spawnPid)
$script:gmLogs.Clear()
$posOk = Wait-ForTunnelUp -TunnelProc $fake -Quiet
Assert $posOk 'behavioral: spawn pid in local -R list => Wait true'
$posLog = ($script:gmLogs -join "`n")
Assert ($posLog -match 'TUNNEL_WAIT ok=1') 'behavioral: success logs TUNNEL_WAIT ok=1'
Assert ($posLog -notmatch 'local_r_not_owned') 'behavioral: owned path does not log local_r_not_owned'

# Extra negative control: foreign pid in list still fails
$script:LocalPidStub = @(99999)
$script:gmLogs.Clear()
$foreignOk = Wait-ForTunnelUp -TunnelProc $fake -Quiet
Assert (-not $foreignOk) 'behavioral: foreign-only local PIDs => Wait false'
Assert (($script:gmLogs -join "`n") -match 'local_r_not_owned') `
    'behavioral: foreign-only PIDs logs local_r_not_owned'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All wait local -R ownership tests passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("wait local -R ownership FAILED: {0} pass, {1} fail" -f $Pass, $Fail) -ForegroundColor Red
exit 1
