#Requires -Version 5.1
# test-sidecar-watchdog-lease.ps1 (Windows-only, Stage F #15)
# Source-level contract for the sidecar watchdog lease / cleanup design:
#
#   1. Start-CursorProxySidecarWatchdog (scripts/client/windows/cursor-proxy-sidecar.ps1)
#      MUST keep the Mutex it creates in $script:CursorProxyWatchdogMutex (and call
#      .WaitOne() on it), instead of the old discard-only pattern:
#        $null = New-Object System.Threading.Mutex($false, $mutexName, [ref]$created)
#      That old pattern throws the mutex handle away, so nothing can ever release/dispose
#      it later and orphaned watchdog processes cannot be reaped deterministically.
#
#   2. New function Stop-CursorProxySidecarWatchdog:
#        - ReleaseMutex + Dispose (or Close) the held $script:CursorProxyWatchdogMutex.
#        - Kills only processes whose CommandLine contains
#          "claude-connect-sidecar-watchdog.ps1" (cmdline-scoped kill, never a bare
#          process-name kill of all powershell.exe).
#
#   3. New function Stop-CursorProxySidecarRelays (or Reap-CursorProxySidecarOrphans):
#        - Kills only powershell processes whose CommandLine matches
#          "claude-connect-sidecar-18998.ps1" or "claude-connect-sidecar-18999.ps1"
#          (cmdline-scoped; must never touch foreign/unrelated powershell processes).
#
#   4. A lease file (e.g. "$env:TEMP\claude-connect-sidecar-watchdog.lease") is written
#      with the owner PID when the watchdog starts, so a later session can tell whether
#      the watchdog that's holding the mutex is still alive.
#
#   5. scripts/client/windows/connect.ps1's finally/cleanup path calls
#      Stop-CursorProxySidecarWatchdog (or the Reap/Stop-relays function) on the
#      disconnect path - i.e. inside the "else" branch of the final
#      "if ($keepTunnelForEditor) { ... } else { ... }" block - and must NOT call it
#      while $keepTunnelForEditor is true (editor still open -> sidecar/watchdog must
#      keep running for that session).
#
# MUST-NOT (regression guards):
#   - No "-ForceUnfreeze" flag and no Sepidz-specific paths in this feature.
# NOTE: Job Object APIs (#14) are now expected in cursor-proxy-sidecar.ps1 after #15 PASS.
#
# ============================================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

# Brace-counting function-body extractor (robust to function ordering; PowerShell
# source in this file has no unbalanced braces inside strings/comments).
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
Write-Host '=== SIDECAR_WATCHDOG_LEASE: watchdog mutex ownership + Stop/Reap cleanup + lease file (source contracts) ===' -ForegroundColor Cyan
Write-Host ''

$sidecarPath = Get-ClientFile 'windows\cursor-proxy-sidecar.ps1'
$connectPath = Get-ClientFile 'windows\connect.ps1'
$sidecar = Get-Content -LiteralPath $sidecarPath -Raw
$connect = Get-Content -LiteralPath $connectPath -Raw

# ----------------------------------------------------------------------------
# #1 Start-CursorProxySidecarWatchdog keeps the mutex (WaitOne), no discard-only
# ----------------------------------------------------------------------------
Write-Host '--- #1 Start-CursorProxySidecarWatchdog: keep mutex in $script:CursorProxyWatchdogMutex ---' -ForegroundColor Cyan
$startWdBody = Get-FunctionBody $sidecar 'Start-CursorProxySidecarWatchdog'
Assert ($startWdBody.Length -gt 50) 'extracted Start-CursorProxySidecarWatchdog function body'

# Capture the local variable the Mutex constructor is assigned to (if any), so the
# WaitOne()/$script: assignment checks below aren't sensitive to how much unrelated
# code (created-check, Dispose-on-not-owned, etc.) sits between the three statements.
$mutexCtorMatch = [regex]::Match($startWdBody, '(\$\w+)\s*=\s*New-Object\s+System\.Threading\.Mutex\(')
Assert $mutexCtorMatch.Success 'Start-CursorProxySidecarWatchdog creates a Mutex object into a variable (not a $null = discard)'
$mutexVar = if ($mutexCtorMatch.Success) { $mutexCtorMatch.Groups[1].Value } else { '' }

$assignsWatchdogMutex = (
    ($startWdBody -match '\$script:CursorProxyWatchdogMutex\s*=\s*New-Object\s+System\.Threading\.Mutex') -or
    ($mutexVar -and ($startWdBody -match ([regex]::Escape('$script:CursorProxyWatchdogMutex') + '\s*=\s*' + [regex]::Escape($mutexVar) + '\b')))
)
Assert $assignsWatchdogMutex '$script:CursorProxyWatchdogMutex is assigned the Mutex object (not discarded)'

$waitOneOk = (
    ($mutexVar -and ($startWdBody -match ([regex]::Escape($mutexVar) + '\.WaitOne\('))) -or
    ($startWdBody -match '\$script:CursorProxyWatchdogMutex\.WaitOne\(')
)
Assert $waitOneOk 'watchdog mutex handle is WaitOne()-ed (not just created-and-ignored)'

Assert ($startWdBody -notmatch '\$null\s*=\s*New-Object\s+System\.Threading\.Mutex\(\$false,\s*\$mutexName,\s*\[ref\]\$created\)') `
    'old discard-only "$null = New-Object System.Threading.Mutex(...)" pattern removed from Start-CursorProxySidecarWatchdog'

# ----------------------------------------------------------------------------
# #4 Lease file with owner PID, written when the watchdog starts
# ----------------------------------------------------------------------------
Write-Host '--- #4 Watchdog lease file (owner PID) ---' -ForegroundColor Cyan
Assert ($sidecar -match [regex]::Escape('claude-connect-sidecar-watchdog.lease')) `
    "lease filename 'claude-connect-sidecar-watchdog.lease' present in cursor-proxy-sidecar.ps1"
Assert ($startWdBody -match [regex]::Escape('claude-connect-sidecar-watchdog.lease')) `
    'Start-CursorProxySidecarWatchdog references the lease file path'
$writesPidToLease = (
    $startWdBody -match '(?s)claude-connect-sidecar-watchdog\.lease[\s\S]{0,400}?(\$PID\b|GetCurrentProcess\(\)\.Id|\$script:CursorProxyWatchdogPid)'
) -or (
    $startWdBody -match '(?s)(\$PID\b|GetCurrentProcess\(\)\.Id|\$script:CursorProxyWatchdogPid)[\s\S]{0,400}?claude-connect-sidecar-watchdog\.lease'
)
Assert $writesPidToLease 'Start-CursorProxySidecarWatchdog writes the owner PID into the lease file'
Assert ($startWdBody -match 'Set-Content|Out-File|WriteAllText') 'lease file is actually written to disk (Set-Content/Out-File/WriteAllText)'

# ----------------------------------------------------------------------------
# #2 Stop-CursorProxySidecarWatchdog: release/dispose mutex + cmdline-scoped kill
# ----------------------------------------------------------------------------
Write-Host '--- #2 Stop-CursorProxySidecarWatchdog exists: release/dispose mutex + cmdline-scoped kill ---' -ForegroundColor Cyan
$stopWdBody = Get-FunctionBody $sidecar 'Stop-CursorProxySidecarWatchdog'
Assert ($stopWdBody.Length -gt 20) 'Stop-CursorProxySidecarWatchdog function exists in cursor-proxy-sidecar.ps1'
Assert ($stopWdBody -match 'ReleaseMutex\(') 'Stop-CursorProxySidecarWatchdog calls ReleaseMutex() on the held mutex'
Assert ($stopWdBody -match '\.Dispose\(\)|\.Close\(\)') 'Stop-CursorProxySidecarWatchdog Disposes/Closes the held mutex'
Assert ($stopWdBody -match '\$script:CursorProxyWatchdogMutex') 'Stop-CursorProxySidecarWatchdog operates on $script:CursorProxyWatchdogMutex'
Assert ($stopWdBody -match [regex]::Escape('claude-connect-sidecar-watchdog.ps1')) `
    "Stop-CursorProxySidecarWatchdog filters kill target by cmdline containing 'claude-connect-sidecar-watchdog.ps1'"
Assert ($stopWdBody -match 'CommandLine') 'Stop-CursorProxySidecarWatchdog process kill is CommandLine-scoped (not by bare process name)'
Assert ($stopWdBody -match 'Stop-Process|\.Kill\(\)') 'Stop-CursorProxySidecarWatchdog actually terminates the matched watchdog process(es)'

# ----------------------------------------------------------------------------
# #3 Stop-CursorProxySidecarRelays / Reap-CursorProxySidecarOrphans: cmdline-scoped reap
# ----------------------------------------------------------------------------
Write-Host '--- #3 Stop-CursorProxySidecarRelays / Reap-CursorProxySidecarOrphans: cmdline-scoped only ---' -ForegroundColor Cyan
$reapBody = Get-FunctionBody $sidecar 'Stop-CursorProxySidecarRelays'
$reapName = 'Stop-CursorProxySidecarRelays'
if ($reapBody.Length -le 20) {
    $reapBody = Get-FunctionBody $sidecar 'Reap-CursorProxySidecarOrphans'
    $reapName = 'Reap-CursorProxySidecarOrphans'
}
Assert ($reapBody.Length -gt 20) 'Stop-CursorProxySidecarRelays (or Reap-CursorProxySidecarOrphans) function exists'
Assert ($reapBody -match [regex]::Escape('claude-connect-sidecar-18998.ps1')) "$reapName filters by cmdline containing 'claude-connect-sidecar-18998.ps1'"
Assert ($reapBody -match [regex]::Escape('claude-connect-sidecar-18999.ps1')) "$reapName filters by cmdline containing 'claude-connect-sidecar-18999.ps1'"
Assert ($reapBody -match 'CommandLine') "$reapName kill is CommandLine-scoped (not a bare process-name kill)"
Assert (
    -not ($reapBody -match "Get-Process\s+(-Name\s+)?['`"]?powershell['`"]?\s*(\|\s*Stop-Process)?\s*$")
) "$reapName never does a blind 'Get-Process powershell | Stop-Process' (would kill foreign PS)"
Assert ($reapBody -match 'Stop-Process|\.Kill\(\)') "$reapName actually terminates matched relay process(es)"

# ----------------------------------------------------------------------------
# #5 connect.ps1: disconnect path calls Stop/Reap; keepTunnelForEditor path must NOT
# ----------------------------------------------------------------------------
Write-Host '--- #5 connect.ps1 finally/cleanup: Stop/Reap called on disconnect, not when keepTunnelForEditor ---' -ForegroundColor Cyan
$finallyMatch = [regex]::Match($connect, '(?s)\}\s*finally\s*\{.*?\r?\n    \}\r?\n\r?\n    while \(\[Console\]::KeyAvailable\)')
Assert $finallyMatch.Success 'located the sessionLoop finally{} block in connect.ps1'
$finallyBlock = if ($finallyMatch.Success) { $finallyMatch.Value } else { '' }

$kIdx = $finallyBlock.IndexOf('if ($keepTunnelForEditor) {')
Assert ($kIdx -ge 0) 'located "if ($keepTunnelForEditor) { ... } else { ... }" inside the finally block'
$keepAndElse = if ($kIdx -ge 0) { $finallyBlock.Substring($kIdx) } else { '' }
$elseIdx = $keepAndElse.IndexOf('} else {')
Assert ($elseIdx -ge 0) 'located the else-branch (disconnect path) of the keepTunnelForEditor check'
$keepBranch = if ($elseIdx -ge 0) { $keepAndElse.Substring(0, $elseIdx) } else { $keepAndElse }
$elseBranch = if ($elseIdx -ge 0) { $keepAndElse.Substring($elseIdx) } else { '' }

$stopOrReapPattern = 'Stop-CursorProxySidecarWatchdog|Stop-CursorProxySidecarRelays|Reap-CursorProxySidecarOrphans'
Assert ($elseBranch -match $stopOrReapPattern) 'disconnect (else) branch calls Stop-CursorProxySidecarWatchdog / Stop-CursorProxySidecarRelays / Reap-CursorProxySidecarOrphans'
Assert ($keepBranch -notmatch $stopOrReapPattern) 'keepTunnelForEditor branch must NOT stop/reap the sidecar watchdog (editor still open)'

# ============================================================================
# MUST-NOT regression guards
# ============================================================================
Write-Host '--- #14 Job Object present after #15 PASS ---' -ForegroundColor Cyan
Assert ($sidecar -match 'CreateJobObject|AssignProcessToJobObject|Initialize-CursorProxySidecarJob') 'cursor-proxy-sidecar.ps1 has Job Object APIs (#14)'
Assert ($connect -notmatch 'CreateJobObject|AssignProcessToJobObject') 'connect.ps1 has no Job Object Win32 API usage (job stays in sidecar module)'
Write-Host '--- MUST-NOT: no -ForceUnfreeze / Sepidz paths in this feature ---' -ForegroundColor Cyan
Assert ($sidecar -notmatch '-ForceUnfreeze') 'cursor-proxy-sidecar.ps1 has no -ForceUnfreeze flag'
Assert ($connect -notmatch '-ForceUnfreeze') 'connect.ps1 has no -ForceUnfreeze flag'
# Strip full-line comments before checking: a comment explaining that a substring match
# is intentionally generic across "...-Smart/-Sepidz" profile-name suffixes (so it does
# NOT need to special-case Sepidz) is the opposite of a Sepidz-specific code path - only
# flag the word appearing in actual code.
$sidecarCodeOnly = ($sidecar -split "`r?`n" | Where-Object { $_.Trim() -notmatch '^#' }) -join "`n"
Assert ($sidecarCodeOnly -notmatch '(?i)sepidz') 'cursor-proxy-sidecar.ps1 has no Sepidz-specific code paths'

Write-Host ''
if ($fail -gt 0) {
    Write-Host "FAILED: $fail assertion(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
