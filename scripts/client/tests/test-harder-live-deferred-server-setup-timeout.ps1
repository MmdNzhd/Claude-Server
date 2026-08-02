#Requires -Version 5.1
# test-harder-live-deferred-server-setup-timeout.ps1
# HARDER than test-wait-deferred-server-setup-timeout-live.ps1:
# - Static: no unbounded HasExited poll; SCP wait bounded; PUSH_CONF NoRetryOnTimeout;
#   deferred IdentityFile pin before Set-SshHostBlock; default timeout 120s
# - LIVE A: never-exit child via plain Start-Process -> SERVER_SETUP_TIMEOUT + kill + boot_error
# - LIVE B: never-exit child via Start-JobBoundProcess (today's production spawn path)
# - LIVE C: fast-success child writes result JSON -> Wait succeeds, NO timeout log
# - LIVE D: child exits with missing result file -> deferred setup result missing boot_error
# - LIVE E: ServerSessionBoot already set -> Wait returns immediately (no kill of unrelated proc)
# - LIVE F: env floor clamp (0 -> >=1000) and invalid env ignored (default 120000)
# - LIVE G: heartbeat SERVER_SETUP_WAIT appears before timeout when budget > 15s
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARDER LIVE: deferred Server setup timeout / hang contracts ===' -ForegroundColor Cyan

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

Write-Host ''
Note 'Static contracts (hamed.kh hang + today hardening)'
$waitFn = Get-FunctionSource -Content $connect -Name 'Wait-DeferredServerSetup'
Assert ($waitFn.Length -gt 200) 'extracted Wait-DeferredServerSetup'
Assert ($waitFn -match 'SERVER_SETUP_TIMEOUT ms=') 'Wait logs SERVER_SETUP_TIMEOUT'
Assert ($waitFn -match 'SERVER_SETUP_WAIT ms=') 'Wait logs SERVER_SETUP_WAIT heartbeats'
Assert ($waitFn -match 'Get-DeferredServerSetupTimeoutMs') 'Wait uses Get-DeferredServerSetupTimeoutMs'
Assert ($waitFn -match '\.Kill\(\)') 'timeout path Kill()s the stuck worker'
Assert ($waitFn -match '\.Refresh\(\)') 'Wait Refresh()es Process (stale HasExited defense)'
# Old bug shape: bare while (-not HasExited) { Sleep } with no timeout budget.
Assert ($waitFn -notmatch '(?s)while\s*\(\s*-not\s*\$script:DeferredSetupProc\.HasExited\s*\)\s*\{\s*Start-Sleep[^}]*\}\s*\$boot\s*=\s*Import-DeferredServerSetupResult') `
    'unbounded HasExited poll (pre-timeout bug shape) is gone'
Assert ($connect -match '\$ms = 120000') 'default Server-setup wait budget is 120000ms'
Assert ($connect -match 'CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS') 'timeout overridable via env'
Assert ($connect -match 'SCP_TIMEOUT: name=') 'scp WaitForExit is bounded + logged'
Assert ($connect -match 'WaitForExit\(90000\)') 'scp hard wait is 90s'
Assert ($gitMode -match '(?s)function\s+Push-ServerConnectConf.*?SshX \$remote -NoRetryOnTimeout') `
    'Push-ServerConnectConf uses -NoRetryOnTimeout (no 75s+75s double burn)'
Assert ($connect -match 'deferred_setup_ssh_dir_not_running_profile') 'deferred child IdentityFile pin present'
Assert ($connect -match '(?s)DeferredServerSetupOnly\)[\s\S]+?ConnectSshIdentityFile[\s\S]+?Set-SshHostBlock[\s\S]+?Initialize-ServerSession') `
    'Identity pin ordered before Set-SshHostBlock / Initialize-ServerSession in deferred child'
Assert ($connect -match 'SERVER_SETUP deferred_child begin') 'deferred child begin breadcrumb'
Assert ($connect -match '(?s)function\s+Start-DeferredServerSetup.*?Start-JobBoundProcess') `
    'production deferred spawn still goes through Start-JobBoundProcess'

# --- shared stubs / extracted production functions ---
foreach ($n in @(
        'Get-DeferredServerSetupTimeoutMs',
        'Import-DeferredServerSetupResult',
        'Apply-ServerSessionBootResult',
        'Wait-DeferredServerSetup'
    )) {
    $src = Get-FunctionSource -Content $connect -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

function Reset-DeferredWaitHarness {
    $script:ConnectLogLines = [System.Collections.Generic.List[string]]::new()
    $script:ServerSessionBoot = $null
    $script:DeferredSetupProc = $null
    $script:DeferredSetupResultPath = Join-Path $env:TEMP ("cc-hard-def-setup-{0}.json" -f [guid]::NewGuid().ToString('N'))
    $script:Port = 20110
    $script:TunnelSlot = 0
    $script:pendingFixes = @()
    $script:WaitConnectExitReason = $null
    $script:WaitConnectExitCode = $null
    $script:LastStepFail = $null
    $script:LastStepOk = $null
    $script:currentStepName = $null
    Remove-Item Env:\CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS -ErrorAction SilentlyContinue
}

function Write-ConnectLog([string]$Message, [string]$Level = 'INFO') {
    if (-not $script:ConnectLogLines) { $script:ConnectLogLines = [System.Collections.Generic.List[string]]::new() }
    $script:ConnectLogLines.Add("[$Level] $Message")
}
function Step([string]$m) { $script:currentStepName = $m }
function StepFail([string]$d = '') { $script:LastStepFail = $d }
function StepOk([string]$d = '') { $script:LastStepOk = $d }
function Warn([string]$m) { }
function Wait-ConnectExit {
    param([string]$Reason = '', [int]$Code = 0)
    $script:WaitConnectExitReason = $Reason
    $script:WaitConnectExitCode = $Code
    throw ("WAIT_CONNECT_EXIT reason={0} code={1}" -f $Reason, $Code)
}
function Get-GitMode { return 'off' }

function Invoke-WaitCatchingExit {
    $script:CaughtWaitExit = $false
    try { return Wait-DeferredServerSetup }
    catch {
        if ("$($_.Exception.Message)" -match 'WAIT_CONNECT_EXIT') {
            $script:CaughtWaitExit = $true
            return $null
        }
        throw
    }
}

function Stop-ProcSafe($p) {
    if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
    try { if ($p) { $null = $p.WaitForExit(3000) } } catch {}
}

# =============================================================================
Write-Host ''
Note 'LIVE A: plain Start-Process never-exit child -> timeout'
Reset-DeferredWaitHarness
$childA = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 999'
) -PassThru -WindowStyle Hidden
$script:DeferredSetupProc = $childA
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '2500'
$swA = [System.Diagnostics.Stopwatch]::StartNew()
$null = Invoke-WaitCatchingExit
$swA.Stop()
$logA = ($script:ConnectLogLines -join "`n")
Assert ($swA.ElapsedMilliseconds -lt 10000) ("A: Wait bounded (measured {0}ms)" -f $swA.ElapsedMilliseconds)
Assert ($swA.ElapsedMilliseconds -ge 2000) ("A: waited near timeout (measured {0}ms)" -f $swA.ElapsedMilliseconds)
Assert ($logA -match 'SERVER_SETUP_TIMEOUT ms=2500') 'A: SERVER_SETUP_TIMEOUT ms=2500 logged'
Assert $script:CaughtWaitExit 'A: Wait-ConnectExit boot failure path hit'
Assert ($script:WaitConnectExitReason -match 'boot_error:server setup timed out after 2500ms') 'A: boot_error reason exact'
Assert ($childA.HasExited) 'A: never-exit child killed'
Stop-ProcSafe $childA
Remove-Item -LiteralPath $script:DeferredSetupResultPath -Force -ErrorAction SilentlyContinue

# =============================================================================
Write-Host ''
Note 'LIVE B: Start-JobBoundProcess never-exit child - production spawn path'
Reset-DeferredWaitHarness
foreach ($n in @('Initialize-ConnectSessionJob', 'Add-ConnectSessionJobProcess', 'Stop-ConnectSessionJob', 'Start-JobBoundProcess')) {
    $src = Get-FunctionSource -Content $gitMode -Name $n
    if (-not $src) { Write-Host "  FAIL  extract $n" -ForegroundColor Red; exit 1 }
    . ([scriptblock]::Create($src))
}
$childB = Start-JobBoundProcess -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 999'
) -PassThru -WindowStyle Hidden
Assert ($null -ne $childB -and -not $childB.HasExited) 'B: job-bound never-exit child started'
$script:DeferredSetupProc = $childB
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '2500'
$swB = [System.Diagnostics.Stopwatch]::StartNew()
$null = Invoke-WaitCatchingExit
$swB.Stop()
$logB = ($script:ConnectLogLines -join "`n")
Assert ($swB.ElapsedMilliseconds -lt 10000) ("B: job-bound Wait bounded (measured {0}ms)" -f $swB.ElapsedMilliseconds)
Assert ($logB -match 'SERVER_SETUP_TIMEOUT ms=2500') 'B: SERVER_SETUP_TIMEOUT logged for job-bound child'
Assert $script:CaughtWaitExit 'B: Wait-ConnectExit hit for job-bound child'
Assert ($childB.HasExited) 'B: job-bound never-exit child killed on timeout'
try { Stop-ConnectSessionJob } catch {}
Stop-ProcSafe $childB
Remove-Item -LiteralPath $script:DeferredSetupResultPath -Force -ErrorAction SilentlyContinue

# =============================================================================
Write-Host ''
Note 'LIVE C: fast-success child writes result JSON -> no timeout'
Reset-DeferredWaitHarness
$resultPathC = $script:DeferredSetupResultPath
$runnerC = Join-Path $env:TEMP ("cc-hard-def-success-{0}.ps1" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$runnerCBody = @"
Start-Sleep -Milliseconds 400
`$json = '{"Ok":true,"Error":"","PubB":"ssh-ed25519 AAAATEST hard-deferred","PushOk":true,"Port":20112,"TunnelSlot":2,"ServerUidStr":"1011","ClaudeMountSyncVerifiedHash":"","LaptopFirewallOk":true}'
Set-Content -LiteralPath '$($resultPathC -replace "'", "''")' -Value `$json -Encoding UTF8
exit 0
"@
Set-Content -LiteralPath $runnerC -Value $runnerCBody -Encoding UTF8
$childC = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $runnerC
) -PassThru -WindowStyle Hidden
$script:DeferredSetupProc = $childC
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '15000'
$swC = [System.Diagnostics.Stopwatch]::StartNew()
$bootC = $null
try { $bootC = Wait-DeferredServerSetup } catch {
    Write-Host ("  FAIL  C threw: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $script:Fail++
}
$swC.Stop()
$logC = ($script:ConnectLogLines -join "`n")
Assert ($swC.ElapsedMilliseconds -lt 8000) ("C: success path fast (measured {0}ms)" -f $swC.ElapsedMilliseconds)
Assert ($bootC -and $bootC.Ok) 'C: boot.Ok from imported result'
Assert ($script:Port -eq 20112) 'C: imported Port=20112 into script scope'
Assert ($script:TunnelSlot -eq 2) 'C: imported TunnelSlot=2'
Assert ($logC -notmatch 'SERVER_SETUP_TIMEOUT') 'C: no SERVER_SETUP_TIMEOUT on success'
Assert ($script:LastStepOk -match 'port 20112') 'C: StepOk from Apply-ServerSessionBootResult'
Stop-ProcSafe $childC
Remove-Item -LiteralPath $resultPathC, $runnerC -Force -ErrorAction SilentlyContinue

# =============================================================================
Write-Host ''
Note 'LIVE D: child exits without result file -> result-missing boot_error'
Reset-DeferredWaitHarness
$childD = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Milliseconds 300; exit 1'
) -PassThru -WindowStyle Hidden
$script:DeferredSetupProc = $childD
# Point at a path that will never be written.
$script:DeferredSetupResultPath = Join-Path $env:TEMP ("cc-hard-def-missing-{0}.json" -f [guid]::NewGuid().ToString('N'))
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '15000'
$swD = [System.Diagnostics.Stopwatch]::StartNew()
$null = Invoke-WaitCatchingExit
$swD.Stop()
Assert ($swD.ElapsedMilliseconds -lt 8000) ("D: missing-result path bounded (measured {0}ms)" -f $swD.ElapsedMilliseconds)
Assert $script:CaughtWaitExit 'D: Wait-ConnectExit on missing result'
Assert ($script:WaitConnectExitReason -match 'boot_error:deferred setup result missing') `
    'D: boot_error:deferred setup result missing'
Assert ($script:LastStepFail -match 'deferred setup result missing') 'D: StepFail message'
Stop-ProcSafe $childD

# =============================================================================
Write-Host ''
Note 'LIVE E: ServerSessionBoot already set -> immediate return (no kill)'
Reset-DeferredWaitHarness
$keepAlive = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60'
) -PassThru -WindowStyle Hidden
$script:DeferredSetupProc = $keepAlive
$script:ServerSessionBoot = @{ Ok = $true; Error = ''; PubB = 'cached'; PushOk = $true }
$swE = [System.Diagnostics.Stopwatch]::StartNew()
$bootE = Wait-DeferredServerSetup
$swE.Stop()
Assert ($swE.ElapsedMilliseconds -lt 500) ("E: cached boot returns immediately (measured {0}ms)" -f $swE.ElapsedMilliseconds)
Assert ($bootE.PubB -eq 'cached') 'E: returned cached ServerSessionBoot'
Assert (-not $keepAlive.HasExited) 'E: unrelated DeferredSetupProc not killed when boot already cached'
Stop-ProcSafe $keepAlive

# =============================================================================
Write-Host ''
Note 'LIVE F: timeout env floor + invalid env'
Reset-DeferredWaitHarness
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '0'
Assert ((Get-DeferredServerSetupTimeoutMs) -ge 1000) 'F: env=0 clamped to >=1000ms'
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = 'not-a-number'
Assert ((Get-DeferredServerSetupTimeoutMs) -eq 120000) 'F: invalid env falls back to default 120000'
Remove-Item Env:\CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS -ErrorAction SilentlyContinue
Assert ((Get-DeferredServerSetupTimeoutMs) -eq 120000) 'F: unset env uses default 120000'

# =============================================================================
Write-Host ''
Note 'LIVE G: SERVER_SETUP_WAIT heartbeat before timeout (budget 16s)'
Reset-DeferredWaitHarness
$childG = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 999'
) -PassThru -WindowStyle Hidden
$script:DeferredSetupProc = $childG
$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '16000'
$swG = [System.Diagnostics.Stopwatch]::StartNew()
$null = Invoke-WaitCatchingExit
$swG.Stop()
$logG = ($script:ConnectLogLines -join "`n")
Assert ($swG.ElapsedMilliseconds -lt 25000) ("G: 16s timeout bounded (measured {0}ms)" -f $swG.ElapsedMilliseconds)
Assert ($logG -match 'SERVER_SETUP_WAIT ms=') 'G: SERVER_SETUP_WAIT heartbeat emitted before timeout'
Assert ($logG -match 'SERVER_SETUP_TIMEOUT ms=16000') 'G: SERVER_SETUP_TIMEOUT ms=16000 after heartbeats'
Assert ($childG.HasExited) 'G: child killed after heartbeat+timeout'
Stop-ProcSafe $childG
Remove-Item -LiteralPath $script:DeferredSetupResultPath -Force -ErrorAction SilentlyContinue
Remove-Item Env:\CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("HARDER deferred Server-setup timeout RESULT: {0} pass / {1} fail" -f $Pass, $Fail) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -eq 0) { exit 0 }
exit 1
