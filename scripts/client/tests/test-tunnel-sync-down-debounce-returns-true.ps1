#Requires -Version 5.1
# Task 8: document intentional soft-health — Sync-SessionTunnelProcess returns $true while
# miss<3 and logs reason=tunnel_down_debounce (do not "fix" product to return $false earlier).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Tunnel sync down debounce returns $true (Task 8 document) ===' -ForegroundColor Cyan

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$syncSrc = Get-FunctionSource -Content $gm -Name 'Sync-SessionTunnelProcess'
Assert (-not [string]::IsNullOrWhiteSpace($syncSrc)) 'Sync-SessionTunnelProcess extractable'
Assert ($syncSrc -match 'tunnel_down_debounce') 'source mentions tunnel_down_debounce'
Assert ($syncSrc -match '(?s)tunnel_down_debounce.*?return\s+\$true') `
    'source: tunnel_down_debounce path returns $true'

# Behavioral: no bg proc, TCP closed, tunnel down -> miss 1/3 returns $true + log
$script:GitModeLogLines = New-Object System.Collections.Generic.List[string]
function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    $script:GitModeLogLines.Add("$Level|$Message")
}
function Write-TunnelDropLog { param($Reason,$TunnelPid,$TcpOpen,$Banner) }
function Release-StaleTunnelPort { }
function Get-TunnelSessionDiagSuffix { return '' }
function Get-TunnelProcessExitCode { param($Process) return 0 }
function Try-ReattachSessionTunnelProcess { param([ref]$BgTunnel) return $false }
function Test-TunnelPortTcpOpen { return $false }
function Test-TunnelUp { param($Retries = 1) return $false }

$Port = 21004
$script:TunnelSyncFailCount = 0
$script:TunnelSoftFailCount = 0
$script:TunnelSoftFailBudget = 3
$script:TunnelForwardProbeIntervalSec = 30
$script:LastTunnelExitLoggedPid = 0
$script:LastForwardProbeAt = $null
$script:LastTunnelSyncTraceAt = $null
$script:TunnelBannerCacheBanner = ''
$script:LastTunnelSyncDropReason = $null

. ([scriptblock]::Create($syncSrc))

$bg = $null
$r1 = Sync-SessionTunnelProcess -BgTunnel ([ref]$bg)
Assert ($r1 -eq $true) 'miss 1/3: Sync-SessionTunnelProcess returns $true (soft-health debounce)'
$log1 = ($script:GitModeLogLines -join "`n")
Assert ($log1 -match 'tunnel_down_debounce') 'miss 1/3: logs reason=tunnel_down_debounce'
Assert ($log1 -match 'miss=1/3') 'miss 1/3: log shows miss=1/3'

$script:GitModeLogLines.Clear()
$r2 = Sync-SessionTunnelProcess -BgTunnel ([ref]$bg)
Assert ($r2 -eq $true) 'miss 2/3: still returns $true'
Assert (($script:GitModeLogLines -join "`n") -match 'tunnel_down_debounce') 'miss 2/3: still logs tunnel_down_debounce'

$script:GitModeLogLines.Clear()
$r3 = Sync-SessionTunnelProcess -BgTunnel ([ref]$bg)
Assert ($r3 -eq $false) 'miss 3/3: returns $false (debounce exhausted)'
Assert (($script:GitModeLogLines -join "`n") -notmatch 'tunnel_down_debounce') `
    'miss 3/3: no longer soft-returns via tunnel_down_debounce'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL PASS: soft-health debounce documented (returns $true + tunnel_down_debounce for miss<3).' -ForegroundColor Green
    exit 0
}
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1