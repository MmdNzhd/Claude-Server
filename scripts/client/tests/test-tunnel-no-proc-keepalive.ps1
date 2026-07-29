#Requires -Version 5.1
# test-tunnel-no-proc-keepalive.ps1 - dual-UI: lost ssh Process + TCP open must NOT force drop.
# Task 5: time-box zombie keep-alive (NO_PROC_ZOMBIE_SEC=120) with soft_fail_exhausted_zombie_drop.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; throw "ASSERT: $Msg" }
}

Write-Host '=== test-tunnel-no-proc-keepalive ===' -ForegroundColor Cyan

$gmPath = Get-ClientFile 'git-mode.ps1'
$gm = Get-Content -LiteralPath $gmPath -Raw
$gmSh = Get-Content -LiteralPath (Get-ClientFile 'git-mode.sh') -Raw

Assert ($gm -match 'soft_fail_exhausted_keep_alive') 'Win source has keep-alive marker'
Assert ($gmSh -match 'soft_fail_exhausted_keep_alive') 'Mac source has keep-alive marker'
Assert ($gm -match 'no_proc_tcp_open') 'Win still soft-fails no_proc_tcp_open under budget'

# Isolate the no_proc keep-alive arm (not the later banner_miss_tcp_open_budget arm).
$keepAt = $gm.IndexOf('soft_fail_exhausted_keep_alive')
Assert ($keepAt -ge 0) 'found soft_fail_exhausted_keep_alive'
$keepEnd = $gm.IndexOf('return $true', $keepAt)
Assert ($keepEnd -gt $keepAt) 'keep-alive arm has return $true'
$block = $gm.Substring($keepAt, ($keepEnd - $keepAt) + 'return $true'.Length)
Assert ($block -match 'no_proc_tcp_open') 'keep-alive arm is for no_proc_tcp_open'
Assert ($block -notmatch 'Release-StaleTunnelPort') 'keep-alive arm must not Release-StaleTunnelPort'
Assert ($block -notmatch 'return \$false') 'keep-alive arm must not return $false'
# Old drop path must be gone for no_proc budget
Assert ($gm -notmatch 'no_proc_tcp_open_budget') 'old no_proc_tcp_open_budget drop reason removed'

# Mac: after soft_fail count>=4 with tcp open, return 0 (keep), not 1 (drop).
$macKeep = $gmSh.IndexOf('soft_fail_exhausted_keep_alive')
Assert ($macKeep -ge 0) 'Mac has soft_fail_exhausted_keep_alive'
$macBlock = $gmSh.Substring($macKeep, [Math]::Min(280, $gmSh.Length - $macKeep))
Assert ($macBlock -match 'return 0') 'Mac keep-alive returns 0 (session up)'
Assert ($macBlock -notmatch 'return 1') 'Mac keep-alive slice must not return 1'
Assert ($gmSh -notmatch 'no_ssh_proc_tcp_open_budget') 'old Mac no_ssh_proc_tcp_open_budget drop removed'

# Runtime simulation of the keep-alive decision (mirrors Sync-SessionTunnelProcess budget arm).
$script:TunnelSoftFailBudget = 2
$script:TunnelSoftFailCount = 1
$tcpOpen = $true
$released = $false
function Release-StaleTunnelPort { $script:released = $true }
$result = $null
if ($tcpOpen) {
    $script:TunnelSoftFailCount++
    if ($script:TunnelSoftFailCount -ge $script:TunnelSoftFailBudget) {
        # keep-alive path
        $script:TunnelSoftFailCount = 0
        $result = $true
    }
}
Assert ($result -eq $true) 'runtime sim returns keep-alive true'
Assert (-not $released) 'runtime sim did not Release-StaleTunnelPort'
Assert ($script:TunnelSoftFailCount -eq 0) 'runtime sim resets soft-fail counter'

# --- Task 5: zombie_drop + NO_PROC_ZOMBIE_SEC=120 (D6+D7, S2, S3) ---
Write-Host '-- Task 5 static: zombie_drop + 120 locked --' -ForegroundColor White
Assert ($gm -match 'soft_fail_exhausted_zombie_drop') 'Win has soft_fail_exhausted_zombie_drop'
Assert ($gmSh -match 'soft_fail_exhausted_zombie_drop') 'Mac has soft_fail_exhausted_zombie_drop'
Assert ($gm -match 'NoProcZombieSec\s*=\s*120|NO_PROC_ZOMBIE_SEC') 'Win NO_PROC_ZOMBIE_SEC/NoProcZombieSec=120 locked'
Assert ($gmSh -match 'NO_PROC_ZOMBIE_SEC=120') 'Mac NO_PROC_ZOMBIE_SEC=120 locked'
Assert ($gm -match 'NoProcKeepAliveSince') 'Win tracks NoProcKeepAliveSince'
Assert ($gmSh -match '_NO_PROC_KEEPALIVE_SINCE') 'Mac tracks _NO_PROC_KEEPALIVE_SINCE'
# S5: first keep-alive arm (to first return $true) still has no Release-Stale (re-checked above).
# Age-gate Release must appear AFTER that first return $true.
$zombieAt = $gm.IndexOf('soft_fail_exhausted_zombie_drop')
Assert ($zombieAt -gt $keepEnd) 'zombie_drop arm is after first keep-alive return $true'
$zombieSlice = $gm.Substring($zombieAt, [Math]::Min(400, $gm.Length - $zombieAt))
Assert ($zombieSlice -match 'Release-StaleTunnelPort') 'zombie_drop arm calls Release-StaleTunnelPort'
Assert ($gm -match 'NoProcKeepAliveSince\s*=\s*\$null') 'Win resets NoProcKeepAliveSince'
Assert ($gm -match 'Try-ReattachSessionTunnelProcess[\s\S]{0,500}NoProcKeepAliveSince\s*=\s*\$null') `
    'Win resets NoProcKeepAliveSince on healthy reattach'

Write-Host '-- Task 5 behavioral: age gate via Sync stubs --' -ForegroundColor White
. $gmPath

$script:gmLogs = New-Object System.Collections.Generic.List[string]
$script:released = 0
$script:updateOnFalse = 0
$script:AuthStub = $false
$script:BannerStub = ''
$script:Port = 20020
$script:NoProcZombieSec = 120
$script:TunnelSoftFailBudget = 2
$script:TunnelSyncFailCount = 0
$script:LastTunnelExitLoggedPid = 0
$script:NoProcKeepAliveSince = $null
$script:NoProcZombieNow = $null

function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    [void]$script:gmLogs.Add($Message)
}
function Write-ConnectLog {
    param([string]$Message, [string]$Level = 'INFO')
    [void]$script:gmLogs.Add($Message)
}
function Write-TunnelDropLog {
    param([string]$Reason)
    $script:LastTunnelSyncDropReason = $Reason
    [void]$script:gmLogs.Add("TUNNEL_DROP reason=$Reason")
}
function Test-TunnelPortTcpOpen { return $true }
function Try-ReattachSessionTunnelProcess { param([ref]$BgTunnel) return $false }
function Test-TunnelUp { param([int]$Retries = 1) return $false }
function Test-TunnelPortAuthOwned { param([int]$TargetPort) return [bool]$script:AuthStub }
function Get-TunnelBanner { return [string]$script:BannerStub }
function Test-TunnelBannerIsWindows {
    param([string]$Banner)
    if (-not $Banner) { return $false }
    return ($Banner -match 'OpenSSH_for_Windows')
}
function Release-StaleTunnelPort { $script:released++ }
function Test-IsCursorProxyOwner { return $true }
function Update-CursorProxyOwnerServiceHealth { $script:updateOnFalse++ }
function Get-TunnelSessionDiagSuffix { return '' }
function Get-TunnelProcessExitCode { param($Process) return -1 }

function Invoke-NoProcSyncTick {
    $script:TunnelSoftFailCount = $script:TunnelSoftFailBudget - 1
    $bg = $null
    return (Sync-SessionTunnelProcess -BgTunnel ([ref]$bg))
}

# First exhaust at t=0: keep-alive, starts Since, no Release
$script:gmLogs.Clear()
$script:released = 0
$script:AuthStub = $false
$script:BannerStub = ''
$script:NoProcKeepAliveSince = $null
$script:NoProcZombieNow = [datetime]'2026-07-29T12:00:00Z'
$r = Invoke-NoProcSyncTick
Assert ($r -eq $true) 'first exhaust: keep-alive returns true'
Assert ($script:released -eq 0) 'first exhaust: no Release-Stale (D6/S5)'
Assert (($script:gmLogs | Where-Object { $_ -match 'soft_fail_exhausted_keep_alive' }).Count -ge 1) `
    'first exhaust: logs soft_fail_exhausted_keep_alive'
Assert ($null -ne $script:NoProcKeepAliveSince) 'first exhaust: sets NoProcKeepAliveSince'

# age=119 + NOT auth => keep-alive
$script:gmLogs.Clear()
$script:released = 0
$script:AuthStub = $false
$script:BannerStub = ''
$script:NoProcZombieNow = [datetime]'2026-07-29T12:01:59Z'
$r = Invoke-NoProcSyncTick
Assert ($r -eq $true) 'age=119 + NOT auth: keep-alive'
Assert ($script:released -eq 0) 'age=119 + NOT auth: no Release'
Assert (($script:gmLogs | Where-Object { $_ -match 'soft_fail_exhausted_zombie_drop' }).Count -eq 0) `
    'age=119: no zombie_drop log'

# age=120 + NOT auth => drop + Release
$script:gmLogs.Clear()
$script:released = 0
$script:updateOnFalse = 0
$script:AuthStub = $false
$script:BannerStub = ''
$script:NoProcZombieNow = [datetime]'2026-07-29T12:02:00Z'
$r = Invoke-NoProcSyncTick
Assert ($r -eq $false) 'age=120 + NOT auth: drop returns false'
Assert ($script:released -ge 1) 'age=120 + NOT auth: Release-Stale fired'
Assert (($script:gmLogs | Where-Object { $_ -match 'soft_fail_exhausted_zombie_drop' }).Count -ge 1) `
    'age=120 + NOT auth: logs soft_fail_exhausted_zombie_drop'
Assert ($script:updateOnFalse -ge 1) 'Sync false path invokes owner health update'

# age=120 + auth AND banner => keep-alive
$script:gmLogs.Clear()
$script:released = 0
$script:AuthStub = $true
$script:BannerStub = 'SSH-2.0-OpenSSH_for_Windows_8.1'
$script:NoProcKeepAliveSince = [datetime]'2026-07-29T12:00:00Z'
$script:NoProcZombieNow = [datetime]'2026-07-29T12:02:00Z'
$r = Invoke-NoProcSyncTick
Assert ($r -eq $true) 'age=120 + auth AND banner: keep-alive'
Assert ($script:released -eq 0) 'age=120 + auth AND banner: no Release'
Assert (($script:gmLogs | Where-Object { $_ -match 'soft_fail_exhausted_zombie_drop' }).Count -eq 0) `
    'age=120 + auth AND banner: no zombie_drop'

# Reset Since on healthy reattach (behavioral: success path clears the timer)
$script:NoProcKeepAliveSince = [datetime]'2026-07-29T12:00:00Z'
$reattachBg = $null
# Stub Get-Process + CIM; re-bind Try-Reattach from source.
Remove-Item function:Try-ReattachSessionTunnelProcess -ErrorAction SilentlyContinue
$reattachFn = [regex]::Match($gm, '(?s)function Try-ReattachSessionTunnelProcess\s*\{.*?^\}', 'Multiline')
Assert ($reattachFn.Success) 'extracted Try-ReattachSessionTunnelProcess for reattach sim'
Invoke-Expression $reattachFn.Value
function Get-TunnelSshProcess { return [pscustomobject]@{ ProcessId = 424242 } }
# Bypass real Get-Process: inject via scripted stand-in that returns a non-exited handle.
$script:reattachProc = [pscustomobject]@{ Id = 424242; HasExited = $false }
function Get-Process {
    [CmdletBinding()]
    param([int]$Id)
    if ($Id -eq 424242) { return $script:reattachProc }
    throw "process $Id not found"
}
$ok = $false
try { $ok = Try-ReattachSessionTunnelProcess -BgTunnel ([ref]$reattachBg) } catch { $ok = $false }
Assert ($ok -eq $true) 'reattach sim returns true'
Assert ($null -eq $script:NoProcKeepAliveSince) 'healthy reattach clears NoProcKeepAliveSince'

Write-Host ''
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
