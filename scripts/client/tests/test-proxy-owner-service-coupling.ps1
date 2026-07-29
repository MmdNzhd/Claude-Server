#Requires -Version 5.1
# test-proxy-owner-service-coupling.ps1 - Task 4: service_dead empty-lease release
# Locks D5 + S2 reason=service_dead + stale_non_connect + S3 SERVICE_DEAD_SEC=60.
# HARD: Sync AND Complete call Update; t=59 no release / t=60 release;
#       intentional xray_closed (EverHad=false) never service_dead.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== proxy owner/service coupling (service_dead) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw

# --- Static contracts ---
Assert ($gmSrc -match 'function Update-CursorProxyOwnerServiceHealth') 'Win Update-CursorProxyOwnerServiceHealth'
Assert ($gmSrc -match 'ServiceDeadSec\s*=\s*60|SERVICE_DEAD_SEC') 'Win SERVICE_DEAD_SEC/ServiceDeadSec=60 locked'
Assert ($gmSrc -match 'reason=service_dead') 'Win reason=service_dead token'
Assert ($gmSrc -match 'stale_non_connect') 'Win stale_non_connect token'
Assert ($gmSrc -match 'SessionEverHadProxyLegs') 'Win SessionEverHadProxyLegs'

$updFn = Get-FunctionSource -Content $gmSrc -Name 'Update-CursorProxyOwnerServiceHealth'
Assert (-not [string]::IsNullOrWhiteSpace($updFn)) 'extracted Update-CursorProxyOwnerServiceHealth'
Assert ($updFn -match 'TotalSeconds\s*-ge\s*.*60|ServiceDeadSec|SERVICE_DEAD_SEC') `
    'Update compares age against 60s'
Assert ($updFn -match 'SessionEverHadProxyLegs') 'Update gates on SessionEverHadProxyLegs'
Assert ($updFn -match 'Release-CursorProxyOwner') 'Update calls Release-CursorProxyOwner'

$relFn = Get-FunctionSource -Content $gmSrc -Name 'Release-CursorProxyOwner'
Assert ($relFn -match 'Reason|reason=') 'Release accepts/emits reason'

$completeFn = Get-FunctionSource -Content $gmSrc -Name 'Complete-CursorProxyAfterTunnel'
Assert ($completeFn -match 'Update-CursorProxyOwnerServiceHealth') `
    'Complete calls Update-CursorProxyOwnerServiceHealth'

$syncFn = Get-FunctionSource -Content $gmSrc -Name 'Sync-SessionTunnelProcess'
Assert ($syncFn -match 'Update-CursorProxyOwnerServiceHealth') `
    'Sync calls Update-CursorProxyOwnerServiceHealth (D5 Sync-tick path)'

$ens = Get-FunctionSource -Content $gmSrc -Name 'Ensure-SessionTunnel'
Assert ($ens -match 'SessionEverHadProxyLegs\s*=\s*\$true') `
    'Ensure sets SessionEverHadProxyLegs when legs claimed'
Assert (
    ($ens -match '(?s)proxy_leg=-L.*?SessionEverHadProxyLegs\s*=\s*\$true') -or
    ($ens -match '(?s)SessionEverHadProxyLegs\s*=\s*\$true.*?proxy_leg=-L')
) 'Ensure sets EverHad near proxy_leg=-L'
Assert ($ens -match '(?s)proxy_adopt busy_healthy.*?SessionEverHadProxyLegs\s*=\s*\$true|SessionEverHadProxyLegs\s*=\s*\$true.*?proxy_adopt busy_healthy') `
    'Ensure sets EverHad on proxy_adopt busy_healthy'

# Mac parity
Assert ($shSrc -match 'update_cursor_proxy_owner_service_health') 'Mac update_cursor_proxy_owner_service_health'
Assert ($shSrc -match 'SERVICE_DEAD_SEC=60') 'Mac SERVICE_DEAD_SEC=60 locked'
Assert ($shSrc -match 'reason=service_dead') 'Mac reason=service_dead token'
Assert ($shSrc -match 'stale_non_connect') 'Mac stale_non_connect token'
Assert ($shSrc -match 'SESSION_EVER_HAD_PROXY_LEGS') 'Mac SESSION_EVER_HAD_PROXY_LEGS'
Assert (
    $shSrc -match '(?s)complete_cursor_proxy_after_tunnel\(\)\s*\{.*?update_cursor_proxy_owner_service_health'
) 'Mac complete calls update health'
Assert (
    $shSrc -match '(?s)sync_session_tunnel_forward\(\)\s*\{.*?update_cursor_proxy_owner_service_health'
) 'Mac sync calls update health'
Assert (
    $shSrc -match '(?s)_process_alive\(\)\s*\{.{0,400}ps -o state=.{0,200}Z\*'
) 'Mac _process_alive filters zombie state Z'

$claimFn = Get-FunctionSource -Content $gmSrc -Name 'Claim-CursorProxyOwner'
Assert ($claimFn -match 'stale_non_connect') 'Claim logs stale_non_connect on non-Connect adopt'

# --- Behavioral: clock inject 59 vs 60 + xray_closed negative ---
Write-Host '-- behavioral service_dead timer + xray_closed negative --' -ForegroundColor White

$CfgDir = Join-Path $env:TEMP ("proxy-svc-dead-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
$ownerPath = Join-Path $CfgDir 'cursor-proxy-owner.json'
try {
    . $gmPath

    $script:release_count = 0
    $script:release_reasons = New-Object System.Collections.Generic.List[string]
    $script:gmLogs = New-Object System.Collections.Generic.List[string]
    $script:BackendsUpStub = $false
    $script:ServiceDeadSec = 60
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:00:00Z'

    function Write-GitModeLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Write-ConnectLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Get-CursorProxyOwnerPath { return $ownerPath }
    function Test-IsCursorProxyOwner { return $true }
    function Test-LocalPortOpen { param([int]$PortNum) return [bool]$script:BackendsUpStub }
    function Release-CursorProxyOwner {
        param([string]$Reason = '')
        $script:release_count++
        [void]$script:release_reasons.Add([string]$Reason)
        [void]$script:gmLogs.Add(("CURSOR_PROXY_OWNER: released reason={0} pid={1}" -f $Reason, $PID))
    }

    # Seed owner file (real Claim path not required for health timer)
    '{"pid":1,"slot":0,"socks":19080,"http":19180,"started_utc":"2026-07-29T00:00:00Z"}' |
        Set-Content -LiteralPath $ownerPath -Encoding UTF8

    $script:SocksProxyPort = 19080
    $script:HttpProxyPort = 19180
    $script:SessionEverHadProxyLegs = $true
    $script:ProxyOwnerServiceDeadSince = $null
    $script:BackendsUpStub = $false
    $script:release_count = 0
    $script:release_reasons.Clear()
    $script:gmLogs.Clear()

    # t=0: start timer, no release
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:00:00Z'
    Update-CursorProxyOwnerServiceHealth
    Assert ($script:release_count -eq 0) 't=0 backends-down: no release (timer start)'
    Assert ($null -ne $script:ProxyOwnerServiceDeadSince) 't=0 sets ProxyOwnerServiceDeadSince'

    # t=59: still hold
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:00:59Z'
    Update-CursorProxyOwnerServiceHealth
    Assert ($script:release_count -eq 0) 't=59s: no service_dead release'
    Assert ($script:release_reasons -notcontains 'service_dead') 't=59s: reason list has no service_dead'

    # t=60: release
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:01:00Z'
    Update-CursorProxyOwnerServiceHealth
    Assert ($script:release_count -ge 1) 't=60s: release fires'
    Assert ($script:release_reasons -contains 'service_dead') 't=60s: reason=service_dead'
    Assert (($script:gmLogs | Where-Object { $_ -match 'reason=service_dead' }).Count -ge 1) `
        't=60s: log contains reason=service_dead'

    # Positive control: backends recover clears timer (no release on next tick before 60s)
    $script:release_count = 0
    $script:release_reasons.Clear()
    $script:ProxyOwnerServiceDeadSince = $null
    $script:BackendsUpStub = $true
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:10:00Z'
    Update-CursorProxyOwnerServiceHealth
    Assert ($script:release_count -eq 0) 'backends up: no release'
    Assert ($null -eq $script:ProxyOwnerServiceDeadSince) 'backends up: clears dead-since'

    # Matrix #10: intentional xray_closed => never service_dead even after 120s
    $script:BackendsUpStub = $false
    $script:SessionEverHadProxyLegs = $false
    $script:SessionTunnelProxyLegs = $false
    $script:ProxyOwnerServiceDeadSince = $null
    $script:release_count = 0
    $script:release_reasons.Clear()
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:00:00Z'
    Update-CursorProxyOwnerServiceHealth
    $script:CursorProxyHealthNow = [datetime]'2026-07-29T12:02:00Z'
    Update-CursorProxyOwnerServiceHealth
    Assert ($script:release_count -eq 0) 'xray_closed (EverHad=false): never service_dead at 120s'
    Assert ($script:release_reasons -notcontains 'service_dead') `
        'xray_closed: reason list has no service_dead'

    # Sync tick path: Sync invokes Update (behavioral counter)
    $script:update_from_sync = 0
    function Update-CursorProxyOwnerServiceHealth { $script:update_from_sync++ }
    function Test-TunnelPortTcpOpen { $false }
    function Try-ReattachSessionTunnelProcess { param([ref]$BgTunnel) $false }
    function Test-TunnelUp { param([int]$Retries = 1) $false }
    $script:Port = 20020
    $script:TunnelSoftFailCount = 0
    $script:TunnelSoftFailBudget = 4
    $script:TunnelSyncFailCount = 0
    $script:LastTunnelExitLoggedPid = 0
    $bg = $null
    $null = Sync-SessionTunnelProcess -BgTunnel ([ref]$bg)
    Assert ($script:update_from_sync -ge 1) 'Sync-SessionTunnelProcess invokes Update (behavioral)'

    # Claim stale_non_connect adopt (behavioral)
    Remove-Item function:Update-CursorProxyOwnerServiceHealth -ErrorAction SilentlyContinue
    # Re-dot-source would rebind; call Claim with stubbed alive + non-Connect cmdline
    $script:claimAdopted = $false
    $script:gmLogs.Clear()
    function Test-ProcessAlive { param([int]$ProcessId) return ($ProcessId -eq 999001) }
    function Get-CimInstance {
        param($ClassName, $Filter)
        return [pscustomobject]@{ CommandLine = 'C:\Windows\System32\notepad.exe' }
    }
    function Test-ProcessCommandIsConnectUi { param([string]$CommandLine) return $false }
    # Restore real Claim + Release + Get-CursorProxyOwnerInfo by reloading only if needed —
    # Claim was already defined from . $gmPath; stubs above override helpers.
    Remove-Item function:Release-CursorProxyOwner -ErrorAction SilentlyContinue
    function Release-CursorProxyOwner { param([string]$Reason = '') }
    # Rewrite owner as foreign live non-Connect pid
    (@{ pid = 999001; slot = 0; socks = 19080; http = 19180; started_utc = '2026-07-29T00:00:00Z' } |
        ConvertTo-Json -Compress) | Set-Content -LiteralPath $ownerPath -Encoding UTF8
    $claimed = Claim-CursorProxyOwner
    Assert ($claimed -eq $true) 'Claim adopts live non-Connect pid'
    Assert (($script:gmLogs | Where-Object { $_ -match 'stale_non_connect' }).Count -ge 1) `
        'Claim logs stale_non_connect on adopt'
}
finally {
    Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("Asserts: {0} passed, {1} failed" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -gt 0) { 'Red' } else { 'Green' })
if ($Fail -gt 0) { exit 1 }
exit 0
