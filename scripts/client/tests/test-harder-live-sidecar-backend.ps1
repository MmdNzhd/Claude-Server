#Requires -Version 5.1
# test-harder-live-sidecar-backend.ps1 - HARD LIVE/functional contracts for
# cursor-proxy-sidecar.ps1 backend paths: backend_down force-clear (never repair),
# bounded listening probe, watchdog mutex, KILL_ON_JOB_CLOSE job object,
# known-down cache behavior, and missing_http reseed (git-mode.ps1).
# Callers: manual / CI batch; NOT wired into run-all.ps1 by design.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0

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

function Get-IfNotBackendOkBlock([string]$ClearBody) {
    $m = [regex]::Match($ClearBody, 'if\s*\(\s*-not\s+\$backendOk\s*\)\s*\{')
    if (-not $m.Success) { return '' }
    $i = $ClearBody.IndexOf('{', $m.Index)
    $depth = 0
    for ($j = $i; $j -lt $ClearBody.Length; $j++) {
        if ($ClearBody[$j] -eq '{') { $depth++ }
        elseif ($ClearBody[$j] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $ClearBody.Substring($i, $j - $i + 1) }
        }
    }
    return ''
}

function Get-RandomEphemeralPort {
    param([int[]]$Excluded = @(18998, 18999, 19080, 19180, 20022))
    do { $p = Get-Random -Minimum 49152 -Maximum 65535 } while ($Excluded -contains $p)
    return $p
}

Write-Host ''
Write-Host '=== harder live sidecar backend (14 contracts) ==='
Write-Host ''

$side = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
$gm   = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

$clearBody   = Get-FunctionBody $side 'Clear-CursorProxySettingsSidecar'
$startBody   = Get-FunctionBody $side 'Start-CursorProxySidecar'
$ensureBody  = Get-FunctionBody $side 'Ensure-CursorProxySidecar'
$watchBody   = Get-FunctionBody $side 'Start-CursorProxySidecarWatchdog'
$listenBody  = Get-FunctionBody $side 'Test-CursorProxySidecarListening'
$backendBody = Get-FunctionBody $side 'Test-CursorProxyBackendOpen'
$relayBody   = Get-FunctionBody $side 'Start-TcpPortRelay'
$jobInitBody = Get-FunctionBody $side 'Initialize-CursorProxySidecarJob'
$backendDownBlock = Get-IfNotBackendOkBlock $clearBody

# 1-2) backend_down force-clear + repair never inside that branch (deep slice)
Assert ($clearBody -match 'CURSOR_PROXY_CLEAR force reason=backend_down') `
    'Clear logs force reason=backend_down when backend -L is down'

Assert (
    ($backendDownBlock.Length -gt 20) -and
    ($backendDownBlock -notmatch 'Repair-CursorProxySettingsToSidecar') -and
    ($backendDownBlock -match 'do NOT repair') -and
    ($backendDownBlock -notmatch '\breturn\s+\$')
) 'backend_down block never repairs, falls through to clear (deep slice)'

# 3-4) Start/Ensure stop fronts when backend -L down
Assert (
    ($startBody -match 'SIDECAR_START front_up backend_down stopping_fronts') -and
    ($startBody -match 'Stop-CursorProxySidecarRelays')
) 'Start stops front relays when backend -L is down'

Assert ($ensureBody -match 'SIDECAR_ENSURE front_up backend_down stopping_fronts_clearing_settings') `
    'Ensure stops fronts and clears settings when backend -L is down'

# 5) Watchdog mutex
Assert ($watchBody -match [regex]::Escape("Local\ClaudeConnectSidecarWatchdog")) `
    'Watchdog uses Local\ClaudeConnectSidecarWatchdog mutex'

# 6) Job object KILL_ON_JOB_CLOSE
Assert (
    ($jobInitBody -match 'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE') -and
    ($side -match 'Add-CursorProxySidecarJobProcess -Process \$pRelay')
) 'Sidecar job uses KILL_ON_JOB_CLOSE and assigns relay processes'

# 7) Headless relay spawn + bounded TcpClient listening probe
Assert (
    ($relayBody -match 'WindowStyle Hidden|CreateNoWindow\s*=\s*\$true') -and
    ($listenBody -match 'BeginConnect\(\[System\.Net\.IPAddress\]::Loopback') -and
    ($listenBody -match 'WaitOne\(300\)')
) 'Relay spawn is headless; listening probe uses bounded TcpClient WaitOne(300)'

# 8) Backend probe always real (no known-down skip)
Assert ($backendBody -notmatch 'Test-CursorProxyKnownDown') `
    'Test-CursorProxyBackendOpen never short-circuits on known-down cache'

# 9) LIVE: extracted listening probe on ephemeral port (TcpClient fallback path)
$livePort = Get-RandomEphemeralPort
$listener = $null
try {
    $listenSrc = Get-FunctionSource -Content $side -Name 'Test-CursorProxySidecarListening'
    if (-not $listenSrc) { throw 'could not extract Test-CursorProxySidecarListening' }
    . ([ScriptBlock]::Create($listenSrc))
    $before = Test-CursorProxySidecarListening -Port $livePort
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $livePort)
    $listener.Start()
    $after = Test-CursorProxySidecarListening -Port $livePort
    Assert (
        (-not (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue)) -and
        (-not $before) -and $after
    ) "LIVE: TcpClient fallback flips false->true on real bind (port $livePort)"
} catch {
    Assert $false "LIVE listening probe: $($_.Exception.Message)"
} finally {
    if ($listener) { try { $listener.Stop() } catch {} }
}

# 10) LIVE: backend_down Clear removes sticky 18998 from settings.json
$tmpSettings = Join-Path $env:TEMP ("sidecar-backend-clear-{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
    @{
        'http.proxy'        = 'http://127.0.0.1:18998'
        'https.proxy'       = 'http://127.0.0.1:18998'
        'http.proxySupport' = 'override'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmpSettings -Encoding UTF8

    function Write-GitModeLog { param($m, $lvl) }
    function Get-CursorProxySettingsPath { return $script:TmpSettingsPath }
    function Get-CursorProxySettingsPathsForClear { return @($script:TmpSettingsPath) }
    function Test-CursorProxyBackendOpen { return $false }
    function Get-CursorProfileProcesses { return @() }
    function Test-CursorProxySidecarListening { param([int]$Port) return ($Port -eq 18998) }

    $script:TmpSettingsPath = $tmpSettings
    $clearSrc = Get-FunctionSource -Content $side -Name 'Clear-CursorProxySettingsSidecar'
    if (-not $clearSrc) { throw 'could not extract Clear-CursorProxySettingsSidecar' }
    . ([ScriptBlock]::Create($clearSrc))
    $cleared = Clear-CursorProxySettingsSidecar
    $after = Get-Content -LiteralPath $tmpSettings -Raw | ConvertFrom-Json
    Assert ($cleared -and -not ($after.PSObject.Properties['http.proxy'])) `
        'LIVE: backend_down Clear removes http.proxy sticky 18998 from settings.json'
} catch {
    Assert $false "LIVE backend_down clear: $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $tmpSettings) {
        Remove-Item -LiteralPath $tmpSettings -Force -ErrorAction SilentlyContinue
    }
}

# 11) LIVE: known-down cache write on probe failure, clear on recovery
$cachePath = Join-Path $env:TEMP ("claude-connect-proxy-known-down-test-{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
    if (Test-Path -LiteralPath $cachePath) { Remove-Item -LiteralPath $cachePath -Force }

    $script:CursorProxyKnownDownCacheFile = $cachePath
    $script:HttpProxyPort = 0
    $script:SocksProxyPort = 0

    foreach ($fnName in @('Set-CursorProxyKnownDown', 'Clear-CursorProxyKnownDownCache', 'Test-CursorProxyBackendOpen')) {
        $fnSrc = Get-FunctionSource -Content $side -Name $fnName
        if (-not $fnSrc) { throw "could not extract $fnName" }
        . ([ScriptBlock]::Create($fnSrc))
    }

    function Test-CursorProxySidecarListening { param([int]$Port) return ($Port -eq 19080) }
    $down = Test-CursorProxyBackendOpen
    $hadCache = Test-Path -LiteralPath $cachePath

    function Test-CursorProxySidecarListening { param([int]$Port) return $true }
    $up = Test-CursorProxyBackendOpen
    $cacheGone = -not (Test-Path -LiteralPath $cachePath)

    Assert ((-not $down) -and $hadCache -and $up -and $cacheGone) `
        'LIVE: partial backend down writes known-down cache; full recovery clears it'
} catch {
    Assert $false "LIVE known-down cache: $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $cachePath) {
        Remove-Item -LiteralPath $cachePath -Force -ErrorAction SilentlyContinue
    }
}

# 12) LIVE: Initialize-CursorProxySidecarJob creates non-zero KILL_ON_JOB_CLOSE handle
try {
    $script:CursorProxySidecarJob = $null
    $jobSrc = Get-FunctionSource -Content $side -Name 'Initialize-CursorProxySidecarJob'
    if (-not $jobSrc) { throw 'could not extract Initialize-CursorProxySidecarJob' }
    . ([ScriptBlock]::Create($jobSrc))
    function Write-GitModeLog { param($m, $lvl) }
    $jobOk = Initialize-CursorProxySidecarJob
    Assert (
        $jobOk -and $null -ne $script:CursorProxySidecarJob -and
        $script:CursorProxySidecarJob -ne [IntPtr]::Zero
    ) 'LIVE: Initialize-CursorProxySidecarJob returns a real job handle (KILL_ON_JOB_CLOSE)'
} catch {
    Assert $false "LIVE job object: $($_.Exception.Message)"
} finally {
    if ($script:CursorProxySidecarJob -and ('ClaudeConnect.SidecarJob' -as [type])) {
        try { [void][ClaudeConnect.SidecarJob]::CloseHandle([IntPtr]$script:CursorProxySidecarJob) } catch {}
        $script:CursorProxySidecarJob = $null
    }
}

# 13-14) LIVE: missing_http reseed when HTTP backend dead but sticky fronts up
$fnReseed = Get-FunctionSource -Content $gm -Name 'Test-TunnelNeedsProxyReseed'
try {
    if (-not $fnReseed) { throw 'could not extract Test-TunnelNeedsProxyReseed' }
    function Write-GitModeLog { param($m, $lvl) }
    function Get-SocksProxyPort { 19080 }
    function Get-HttpProxyPort { 19180 }
    function Get-CursorSocksFrontPort { 18999 }
    function Get-CursorHttpFrontPort { 18998 }
    function Test-RemoteXraySocksOpen { param([string]$Alias, [string]$SshCfgPath = '', [int]$RemotePort = 0, [switch]$ForceProbe) return $true }
    function Test-CursorProxySidecarListening { param([int]$Port) return $true }
    $script:XrayServerSocksPort = 10808
    $script:XrayServerHttpPort = 10809
    $script:SocksProxyPort = 0
    $script:HttpProxyPort = 0
    . ([ScriptBlock]::Create($fnReseed))
    function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'missing_http' }
    function Test-LocalPortOpen { param([int]$PortNum) return ($PortNum -eq 19080) }

    Assert ((Test-TunnelNeedsProxyReseed -TunnelPid 8801 -Alias 'claude-server') -eq $true) `
        'LIVE: missing_http + dead HTTP backend + live fronts => reseed (not false adopt)'

    function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'missing_http' }
    function Test-LocalPortOpen { param([int]$PortNum) return $true }
    Assert ((Test-TunnelNeedsProxyReseed -TunnelPid 8802 -Alias 'claude-server') -eq $false) `
        'LIVE: missing_http + live HTTP backend => genuine adoption, skip reseed'
} catch {
    Assert $false "LIVE missing_http reseed: $($_.Exception.Message)"
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} harder-live sidecar-backend contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
