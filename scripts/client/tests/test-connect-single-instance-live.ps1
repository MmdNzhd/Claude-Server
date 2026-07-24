# test-connect-single-instance-live.ps1 - LIVE: proves the real Enter-ConnectSingleInstance /
# Exit-ConnectSingleInstance functions (connect-ui.ps1) claim and release REAL named-mutex
# Global\ClaudeConnect#0..#9 slots at the OS level - without ever draining the live production
# slot pool that a real Connect session on this machine (possibly this very test's own
# launcher) may depend on. Safe-mode: probes free slots first and skips honestly if <2 are free.
#
# STEP 3 deliberately uses a SECOND real OS thread (a background Runspace) for the second real
# claim. Windows named-mutex ownership/recursion is per-OS-thread: a thread that already owns a
# named mutex will have any further WaitOne(0) on that same name succeed again immediately
# (recursive re-acquire), even via a brand-new Mutex object. Two same-thread sequential calls to
# the real Enter-ConnectSingleInstance would therefore always return the SAME slot, not two
# distinct ones - a real, deterministic Win32 behavior (never hit in production, where each
# Connect UI is its own OS process/thread), not a bug in connect-ui.ps1. A genuinely different
# OS thread is required to prove two distinct real slots are held simultaneously.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Connect single-instance slot mutex (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$enterSrc = Get-FunctionSource -Content $content -Name 'Enter-ConnectSingleInstance'
$exitSrc  = Get-FunctionSource -Content $content -Name 'Exit-ConnectSingleInstance'
if (-not $enterSrc -or -not $exitSrc) {
    Write-Host '  FAIL  could not extract Enter/Exit-ConnectSingleInstance - live test cannot run (source drifted)' -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($enterSrc))
. ([scriptblock]::Create($exitSrc))

$maxUi = 10
$origSlotEnv = $env:CLAUDE_CONNECT_UI_SLOT

# STEP 1 (safe probe, mandatory first action): count real free Global\ClaudeConnect#0..#9
# slots WITHOUT calling the real functions yet. We only ever ReleaseMutex a handle whose
# WaitOne(0) we personally just returned $true for - never touch a slot already held by
# someone else.
$freeCount = 0
for ($i = 0; $i -lt $maxUi; $i++) {
    $probeName = "Global\ClaudeConnect#$i"
    $pm = $null
    try {
        $pm = New-Object System.Threading.Mutex($false, $probeName)
        $gotIt = $false
        try { $gotIt = $pm.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $gotIt = $true }
        if ($gotIt) {
            $freeCount++
            try { $pm.ReleaseMutex() } catch { }
        }
    } catch {
        # Could not even open/probe this slot name - treat as not free, never touch it further.
    } finally {
        if ($pm) { try { $pm.Dispose() } catch { } }
    }
}
Write-Host ("  probe: {0}/{1} real Global\ClaudeConnect# slots currently free" -f $freeCount, $maxUi) -ForegroundColor DarkGray

# STEP 2 (decision gate): refuse to risk draining the live pool on this machine.
if ($freeCount -lt 2) {
    Write-Host ("SKIPPED: only {0} free real Global\ClaudeConnect slot(s) found; refusing to risk draining the live pool on this machine" -f $freeCount) -ForegroundColor Yellow
    if ($origSlotEnv) { $env:CLAUDE_CONNECT_UI_SLOT = $origSlotEnv } else { Remove-Item Env:\CLAUDE_CONNECT_UI_SLOT -ErrorAction SilentlyContinue }
    exit 0
}

# STEP 3 (only if >= 2 confirmed free): exercise the REAL, unmodified functions - the first real
# claim on THIS (main) OS thread, the second real claim on a genuinely different OS thread (a
# background Runspace), so two real slots can be held simultaneously without mutex recursion.
$sync = [hashtable]::Synchronized(@{ Cmd = 'idle'; State = 'idle'; Ok = $null; Slot = $null; Error = $null })
$rs = $null
$ps = $null
$asyncHandle = $null
$mutex1 = $null

function Wait-BgState {
    param([string]$Expect, [int]$TimeoutMs = 5000)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if ($sync.State -eq $Expect -or $sync.State -eq 'error') { return $true }
        Start-Sleep -Milliseconds 20
    }
    return $false
}

try {
    # Real claim #1, on the main OS thread - held through all of STEP 3 and released in STEP 4.
    $ok1 = Enter-ConnectSingleInstance
    Assert $ok1 'first real Enter-ConnectSingleInstance call (main thread) succeeded'
    $slot1 = $env:CLAUDE_CONNECT_UI_SLOT
    $mutex1 = $script:ConnectInstanceMutex
    Assert (-not [string]::IsNullOrEmpty($slot1)) 'first call recorded a CLAUDE_CONNECT_UI_SLOT value'

    # Background Runspace = a genuinely different real OS thread. The extracted real function
    # source is dot-sourced INSIDE that runspace's own session state, so it calls the same real,
    # unmodified function bodies - just on a different thread, avoiding the same-thread mutex
    # recursion quirk. Enter/Exit/re-Enter for slot #2 all run inside ONE continuous background
    # pipeline invocation (one while loop, driven by $sync), so they stay pinned to that same one
    # background OS thread for their whole lifetime - required because ReleaseMutex() must be
    # called from the same thread that originally acquired it via WaitOne().
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('enterSrc', $enterSrc)
    $rs.SessionStateProxy.SetVariable('exitSrc', $exitSrc)
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $bgScript = @'
. ([scriptblock]::Create($enterSrc))
. ([scriptblock]::Create($exitSrc))
while ($true) {
    switch ($sync.Cmd) {
        'enter' {
            if ($sync.State -ne 'entered' -and $sync.State -ne 'error') {
                try {
                    $ok = Enter-ConnectSingleInstance
                    $sync.Ok = $ok
                    $sync.Slot = $env:CLAUDE_CONNECT_UI_SLOT
                    $sync.State = 'entered'
                } catch { $sync.Error = $_.Exception.Message; $sync.State = 'error' }
            }
        }
        'exit' {
            if ($sync.State -ne 'exited' -and $sync.State -ne 'error') {
                try {
                    Exit-ConnectSingleInstance
                    $sync.Ok = ($null -eq $script:ConnectInstanceMutex)
                    $sync.State = 'exited'
                } catch { $sync.Error = $_.Exception.Message; $sync.State = 'error' }
            }
        }
        'stop' { break }
    }
    if ($sync.Cmd -eq 'stop' -or $sync.State -eq 'error') { break }
    Start-Sleep -Milliseconds 20
}
'@
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($bgScript)
    $asyncHandle = $ps.BeginInvoke()
    Start-Sleep -Milliseconds 150
    Assert (-not ($ps.InvocationStateInfo.State -eq [System.Management.Automation.PSInvocationState]::Failed)) 'background runspace pipeline started without failing'

    # Real claim #2, on the background OS thread.
    $sync.Cmd = 'enter'
    $gotEntered2 = Wait-BgState -Expect 'entered' -TimeoutMs 5000
    Assert $gotEntered2 'second real Enter-ConnectSingleInstance call (background OS thread) completed'
    if ($sync.Error) { Assert $false ("background thread reported an error: {0}" -f $sync.Error) }
    Assert ([bool]$sync.Ok) 'second real Enter-ConnectSingleInstance call (background OS thread) succeeded'
    $slot2 = $sync.Slot
    Assert (-not [string]::IsNullOrEmpty($slot2)) 'second call (background thread) recorded a CLAUDE_CONNECT_UI_SLOT value'
    Assert ($slot1 -ne $slot2) ("distinct real slots held simultaneously by two different real OS threads: slot1={0} (main thread) slot2={1} (background thread)" -f $slot1, $slot2)

    # Release ONE of the two real slots just claimed (slot2), via the real Exit fn, on the SAME
    # background OS thread that acquired it (ReleaseMutex must run on the owning thread).
    $sync.State = 'idle'
    $sync.Cmd = 'exit'
    $gotExited2 = Wait-BgState -Expect 'exited' -TimeoutMs 5000
    Assert $gotExited2 'Exit-ConnectSingleInstance (background OS thread) completed for the released slot'
    if ($sync.Error) { Assert $false ("background thread reported an error during exit: {0}" -f $sync.Error) }
    Assert ([bool]$sync.Ok) 'Exit-ConnectSingleInstance (background thread) cleared its own tracked mutex handle'

    # Third real claim, again on the background OS thread (not main, which still owns slot1 and
    # would just hit the same recursion quirk from the other side). Proves the release was a
    # real OS-level release, not just a PowerShell variable clear.
    $sync.State = 'idle'
    $sync.Cmd = 'enter'
    $gotEntered3 = Wait-BgState -Expect 'entered' -TimeoutMs 5000
    Assert $gotEntered3 'third real Enter-ConnectSingleInstance call (background OS thread) completed'
    if ($sync.Error) { Assert $false ("background thread reported an error on reacquire: {0}" -f $sync.Error) }
    Assert ([bool]$sync.Ok) 'third real Enter-ConnectSingleInstance call succeeded after the release'
    $slot3 = $sync.Slot
    Assert ($slot3 -eq $slot2) ("released slot was really freed at the OS level: reacquired slot={0} (== released slot2={1}), proving this was a real mutex release, not just a variable clear" -f $slot3, $slot2)
    Assert ($slot3 -ne $slot1) 'reacquired slot does not collide with the still-held first (main-thread) slot'
} finally {
    # STEP 4 (mandatory cleanup, always runs): release every slot THIS TEST claimed during STEP 3,
    # explicitly, on the OS thread that actually acquired each one - never rely on process exit.
    if ($ps) {
        try {
            $sync.State = 'idle'
            $sync.Cmd = 'exit'
            [void](Wait-BgState -Expect 'exited' -TimeoutMs 5000)
            $sync.Cmd = 'stop'
            if ($asyncHandle) {
                try { [void]$ps.EndInvoke($asyncHandle) } catch { }
            }
        } catch { }
        try { $ps.Dispose() } catch { }
    }
    if ($rs) {
        try { $rs.Close() } catch { }
        try { $rs.Dispose() } catch { }
    }
    if ($mutex1) {
        try { $mutex1.ReleaseMutex() } catch { }
        try { $mutex1.Dispose() } catch { }
    }
    $script:ConnectInstanceMutex = $null
    if ($origSlotEnv) { $env:CLAUDE_CONNECT_UI_SLOT = $origSlotEnv } else { Remove-Item Env:\CLAUDE_CONNECT_UI_SLOT -ErrorAction SilentlyContinue }

    # Re-probe to prove the net effect on the real machine is zero additional held slots.
    $freeAfter = 0
    for ($i = 0; $i -lt $maxUi; $i++) {
        $pm2 = $null
        try {
            $pm2 = New-Object System.Threading.Mutex($false, "Global\ClaudeConnect#$i")
            $gotIt2 = $false
            try { $gotIt2 = $pm2.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $gotIt2 = $true }
            if ($gotIt2) {
                $freeAfter++
                try { $pm2.ReleaseMutex() } catch { }
            }
        } catch {
        } finally {
            if ($pm2) { try { $pm2.Dispose() } catch { } }
        }
    }
    Write-Host ("  re-probe: {0}/{1} free after cleanup (pre-test baseline was {2})" -f $freeAfter, $maxUi, $freeCount) -ForegroundColor DarkGray
    Assert ($freeAfter -eq $freeCount) 'net slot count after cleanup matches the pre-test baseline (zero additional slots left held)'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
