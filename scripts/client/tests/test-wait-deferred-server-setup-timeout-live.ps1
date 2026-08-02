#Requires -Version 5.1
# LIVE: Wait-DeferredServerSetup must not poll forever when the background worker never exits.
# Spawns a real never-exiting child, drives the shipped Wait-DeferredServerSetup with a short
# CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS, and asserts SERVER_SETUP_TIMEOUT + bounded return.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Wait-DeferredServerSetup timeout (LIVE never-exit child) ===' -ForegroundColor Cyan

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($connect -match 'function Get-DeferredServerSetupTimeoutMs') 'Get-DeferredServerSetupTimeoutMs defined'
Assert ($connect -match 'SERVER_SETUP_TIMEOUT ms=') 'Wait logs greppable SERVER_SETUP_TIMEOUT'
Assert ($connect -match 'CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS') 'timeout overridable via env'
Assert ($connect -match 'SERVER_SETUP_WAIT ms=') 'Wait emits SERVER_SETUP_WAIT heartbeats'
Assert ($connect -match 'deferred_setup_ssh_dir_not_running_profile') 'deferred child pins IdentityFile when elevated rebound'
Assert ($connect -match 'SERVER_SETUP deferred_child begin') 'deferred child logs begin breadcrumb'

$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
Assert ($gitMode -match '(?s)function\s+Push-ServerConnectConf.*?SshX \$remote -NoRetryOnTimeout') `
    'Push-ServerConnectConf uses -NoRetryOnTimeout (no double hard-kill budget)'

# --- LIVE: extract Wait + helpers, stub exit path, spawn never-exit child ---
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

$script:ConnectLogLines = [System.Collections.Generic.List[string]]::new()
function Write-ConnectLog([string]$Message, [string]$Level = 'INFO') {
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
    # Match production: Wait-ConnectExit ends the Connect process. Throw so Apply stops.
    throw ("WAIT_CONNECT_EXIT reason={0} code={1}" -f $Reason, $Code)
}
function Get-GitMode { return 'off' }

$script:ServerSessionBoot = $null
$script:DeferredSetupResultPath = Join-Path $env:TEMP ("cc-deferred-timeout-test-{0}.json" -f [guid]::NewGuid().ToString('N'))
$script:Port = 20110
$script:TunnelSlot = 0
$script:pendingFixes = @()
$script:WaitConnectExitReason = $null
$script:LastStepFail = $null

$child = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 999'
) -PassThru -WindowStyle Hidden
Assert ($null -ne $child -and -not $child.HasExited) 'never-exit child actually started'
$script:DeferredSetupProc = $child

$env:CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS = '3000'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$caughtExit = $false
try {
    $null = Wait-DeferredServerSetup
} catch {
    if ("$($_.Exception.Message)" -match 'WAIT_CONNECT_EXIT') { $caughtExit = $true }
    else {
        Write-Host ("  FAIL  Wait-DeferredServerSetup threw unexpected: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:fail++
    }
}
$sw.Stop()

Assert ($sw.ElapsedMilliseconds -lt 12000) ("Wait returned within 12s (measured {0}ms), did not hang the test" -f $sw.ElapsedMilliseconds)
Assert ($sw.ElapsedMilliseconds -ge 2500) ("Wait respected ~3s timeout (measured {0}ms)" -f $sw.ElapsedMilliseconds)
$joined = ($script:ConnectLogLines -join "`n")
if ($joined -notmatch 'SERVER_SETUP_TIMEOUT') {
    Write-Host ("  INFO  connect log lines ({0}): {1}" -f $script:ConnectLogLines.Count, $joined) -ForegroundColor DarkGray
}
Assert ($joined -match 'SERVER_SETUP_TIMEOUT ms=3000') 'logged SERVER_SETUP_TIMEOUT ms=3000'
Assert $caughtExit 'Apply-ServerSessionBootResult reached Wait-ConnectExit (boot failure path)'
Assert ($script:WaitConnectExitReason -match 'boot_error:server setup timed out') `
    'failed into Apply-ServerSessionBootResult / Wait-ConnectExit boot_error path'
Assert ($script:LastStepFail -match 'timed out') 'StepFail received timeout error'
Assert ($child.HasExited) 'never-exit child was killed on timeout'

try {
    if ($child -and -not $child.HasExited) { $child.Kill() }
} catch {}
Remove-Item -LiteralPath $script:DeferredSetupResultPath -Force -ErrorAction SilentlyContinue
Remove-Item Env:\CLAUDE_CONNECT_SERVER_SETUP_TIMEOUT_MS -ErrorAction SilentlyContinue

Write-Host ''
if ($fail -eq 0) { Write-Host 'All Wait-DeferredServerSetup timeout tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
