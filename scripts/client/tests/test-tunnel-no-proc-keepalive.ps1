#Requires -Version 5.1
# test-tunnel-no-proc-keepalive.ps1 - dual-UI: lost ssh Process + TCP open must NOT force drop.
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

Write-Host ''
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
