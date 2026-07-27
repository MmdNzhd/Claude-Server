#Requires -Version 5.1
# test-sidecar-xray-hard-batch.ps1 - consolidated hard contracts for sidecar + xray fleet fixes:
#   CURSOR_PROXY_CLEAR backend_down, front_up/backend_down stop fronts, watchdog lease
#   (Local\ClaudeConnectSidecarWatchdog), job object, boot reap preserve fronts, xray probe
#   cache + HTTP leg resilience, sticky 18998 must not repair when backend down, listening
#   probe static contracts (live listening covered by test-sidecar-listening-live.ps1).
# Callers: manual / CI batch; NOT wired into run-all.ps1 by design.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

function Get-FunctionBody([string]$Content, [string]$Name) {
    $m = [regex]::Match($Content, "function\s+$([regex]::Escape($Name))\s*\{")
    if (-not $m.Success) { return '' }
    $start = $m.Index + $m.Length
    $depth = 1
    $i = $start
    while ($i -lt $Content.Length -and $depth -gt 0) {
        $ch = $Content[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth-- }
        $i++
    }
    if ($depth -ne 0) { return '' }
    return $Content.Substring($m.Index, $i - $m.Index)
}

Write-Host ''
Write-Host '=== sidecar + xray hard batch (14 contracts) ==='
Write-Host ''

$side = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
$gm   = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$dcb  = Get-Content (Get-ServerFile 'server\commands\deploy-client-bundle.sh') -Raw

$clearBody   = Get-FunctionBody $side 'Clear-CursorProxySettingsSidecar'
$startBody   = Get-FunctionBody $side 'Start-CursorProxySidecar'
$ensureBody  = Get-FunctionBody $side 'Ensure-CursorProxySidecar'
$bootBody    = Get-FunctionBody $side 'Invoke-CursorProxySidecarBootReap'
$watchBody   = Get-FunctionBody $side 'Start-CursorProxySidecarWatchdog'
$listenBody  = Get-FunctionBody $side 'Test-CursorProxySidecarListening'
$backendBody = Get-FunctionBody $side 'Test-CursorProxyBackendOpen'
$repairBody  = Get-FunctionBody $side 'Repair-CursorProxySettingsToSidecar'

# 1) CURSOR_PROXY_CLEAR backend_down
Assert ($clearBody -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'Clear force-clears when backend -L is down'

# 2) backend_down must not repair sticky 18998
$backendDownIdx = $clearBody.IndexOf('if (-not $backendOk)')
$repairIdx = $clearBody.IndexOf('Repair-CursorProxySettingsToSidecar')
Assert ($backendDownIdx -ge 0 -and $repairIdx -ge 0 -and $backendDownIdx -lt $repairIdx) `
    'backend_down branch precedes Repair (force clear, never repair to 18998)'

# 3) Start: front_up + backend_down stops fronts
Assert (
    ($startBody -match 'SIDECAR_START front_up backend_down stopping_fronts') -and
    ($startBody -match 'Stop-CursorProxySidecarRelays')
) 'Start stops front relays when backend -L is down'

# 4) Ensure: front_up + backend_down stops fronts and clears settings
Assert ($ensureBody -match 'SIDECAR_ENSURE front_up backend_down stopping_fronts_clearing_settings') `
    'Ensure stops fronts and clears settings when backend -L is down'

# 5) Watchdog lease mutex name
Assert ($watchBody -match [regex]::Escape("Local\ClaudeConnectSidecarWatchdog")) `
    'Watchdog uses Local\ClaudeConnectSidecarWatchdog mutex'

# 6) Watchdog lease file records owner PID
Assert (
    ($watchBody -match 'claude-connect-sidecar-watchdog\.lease') -and
    ($watchBody -match '\$script:CursorProxyWatchdogMutex\s*=')
) 'Watchdog writes lease file and holds mutex in $script:CursorProxyWatchdogMutex'

# 7) Job object on relay spawn
Assert (
    ($side -match 'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE') -and
    ($side -match 'Add-CursorProxySidecarJobProcess -Process \$pRelay')
) 'Relay processes are assigned into KILL_ON_JOB_CLOSE sidecar job'

# 8) Boot reap preserve live fronts
$skipIdx = $bootBody.IndexOf('SIDECAR_BOOT_REAP skip')
$stopWdCall = [regex]::Match($bootBody, 'Get-Command\s+Stop-CursorProxySidecarWatchdog[\s\S]{0,120}?Stop-CursorProxySidecarWatchdog')
Assert (
    ($bootBody -match "SIDECAR_BOOT_REAP skip reason=\{0\}" -and $bootBody -match "'fronts_up'") -and
    ($skipIdx -ge 0 -and $stopWdCall.Success -and $skipIdx -lt $stopWdCall.Index)
) 'BootReap skips reap when fronts are up (skip before StopWatchdog)'

# 9) never-again ship gate: deploy blocks missing backend_down clear
Assert ($dcb -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'deploy-client-bundle ship-gate requires backend_down force-clear in staged sidecar'

# 10) Repair skips dead 18998 front
Assert ($repairBody -match '18998_not_listening') `
    'Repair skips when 18998 is not listening (never repair dead sticky)'

# 11) xray probe cache: conclusive-only
$fnProbe = Get-FunctionSource -Content $gm -Name 'Test-RemoteXraySocksOpen'
Assert ($fnProbe -match 'if\s*\(\$conclusive\s+-and\s+\$script:XrayProbeCache') `
    'xray probe caches only CONCLUSIVE verdicts (not timeout/inconclusive)'

# 12) xray HTTP leg: ForceProbe retry before skip
$fnHttp = Get-FunctionSource -Content $gm -Name 'Add-TunnelHttpProxyLeg'
$forceIdx = $fnHttp.IndexOf('-ForceProbe')
$skipIdxHttp = $fnHttp.IndexOf('skipping_http_proxy_leg')
Assert ($forceIdx -ge 0 -and $skipIdxHttp -ge 0 -and $forceIdx -lt $skipIdxHttp) `
    'Add-TunnelHttpProxyLeg retries with -ForceProbe before skipping HTTP leg'

# 13) xray reseed: missing_http self-heal (functional)
$fnReseed = Get-FunctionSource -Content $gm -Name 'Test-TunnelNeedsProxyReseed'
function Write-GitModeLog { param($m, $lvl) }
function Get-SocksProxyPort { 19080 }
function Get-HttpProxyPort  { 19180 }
function Get-CursorSocksFrontPort { 18999 }
function Get-CursorHttpFrontPort  { 18998 }
function Test-RemoteXraySocksOpen { param([string]$Alias, [string]$SshCfgPath = '', [int]$RemotePort = 0, [switch]$ForceProbe) return $true }
function Test-CursorProxySidecarListening { param([int]$Port) return $true }
$script:XrayServerSocksPort = 10808
$script:XrayServerHttpPort  = 10809
$script:SocksProxyPort = 0
$script:HttpProxyPort  = 0
. ([ScriptBlock]::Create($fnReseed))
function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'missing_http' }
function Test-LocalPortOpen { param([int]$PortNum) return ($PortNum -eq 19080) }
Assert ((Test-TunnelNeedsProxyReseed -TunnelPid 9001 -Alias 'claude-server') -eq $true) `
    'missing_http with dead HTTP backend + live front => reseed (not false adopt)'

# 14) listening static contracts (live probe in test-sidecar-listening-live.ps1)
Assert (
    ($listenBody -match 'BeginConnect\(\[System\.Net\.IPAddress\]::Loopback') -and
    ($listenBody -match 'WaitOne\(300\)') -and
    ($backendBody -notmatch 'Test-CursorProxyKnownDown')
) 'listening uses bounded TcpClient probe; backend check never skips on known-down cache'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} hard-batch contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
