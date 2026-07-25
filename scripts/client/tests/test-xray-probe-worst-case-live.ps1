# test-xray-probe-worst-case-live.ps1 - Bugs 3/4 LIVE: Test-RemoteXraySocksOpen's attempt+retry
# stacking (WaitForExit(5000) then, on timeout, a full retry WaitForExit(6000)) must be proven to
# exceed the ~8000ms worst-case budget the H10_proxy_health_timeout comment claims to protect,
# when the remote alias is genuinely unreachable (not merely slow, not a closed port).
#
# Research cited (see docs/superpowers/plans/2026-07-24-cursor-agent-fix-9-bugs.md "Research"):
#  - Win32-OpenSSH `ConnectTimeout` has a long-known upstream behavior/bug (PowerShell/
#    Win32-OpenSSH GitHub issue #1352) where the non-blocking poll()-based connect path can make
#    the ssh client wait the ENTIRE ConnectTimeout duration even in cases that would otherwise
#    resolve faster - i.e. "ConnectTimeout=2" is a "wait up to 2s" budget, not a tight fast-fail
#    guarantee, and is frequently fully consumed. That is consistent with this function's own
#    H19 comment attributing attempt-1 stalls to SSH `MaxStartups` throttling under a boot-time
#    connection burst (OpenSSH `sshd_config MaxStartups low:rate:high`, default `10:30:60` -
#    once the unauthenticated-connection count crosses the low watermark, sshd starts randomly
#    dropping/delaying a percentage of new connection attempts, worsening under bursts).
#  - Net effect for this test: even though the ssh-level ConnectTimeout is only 2s, the *process*
#    WaitForExit budgets this function stacked (5000ms, then on timeout another 6000ms for a full
#    second connection attempt) were what actually bound worst-case wall-clock here - and that
#    stacked worst case (attempt1 5000ms + retry 6000ms = up to 11000ms) was provably worse than
#    the ~8000ms the H10_proxy_health_timeout fix comment says it was tightening from (bug 4).
#    Bug 3 was that attempt-1 itself stalled/timed-out often against a target that was not
#    actually unreachable in production (cold SSH / MaxStartups), which is exactly why the retry
#    existed - but the retry's own budget then pushed the worst case above the original one.
#
# FIX (2026-07-24, git-mode.ps1 Test-RemoteXraySocksOpen): removed the attempt+retry stacking
# entirely. Single ssh attempt, ConnectTimeout=6 (giving genuinely-slow-but-alive cold SSH a fair
# single window per the MaxStartups research above) + a single WaitForExit(7000) process backstop
# (letting the ssh-level timeout fire on its own first). New worst case ~7000ms, safely under the
# original ~8000ms budget, with no second connection attempt. This test now asserts the FIXED
# (GREEN) bound: both scenarios must return $false AND complete in well under 8000ms.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Xray-probe worst-case retry-stacking bugs 3/4 (LIVE) ===' -ForegroundColor Cyan

# Test-RemoteXraySocksOpen only calls Write-GitModeLog on the timeout/retry path (never reached
# on a clean/fast pass). Stub it so the extracted function body can run standalone without
# pulling in the real logger's global state/file handles/mutex.
function Write-GitModeLog { param([string]$Message, [string]$Level = 'INFO') }

# The probe now hydrates/persists a disk cache of verdicts (Import-/Save-XrayProbeDiskCache).
# Stub both so the extracted body runs standalone without pulling in the real cache's file IO -
# and, critically, so a missing-command lookup does not trigger PowerShell's full PATH/module
# command-discovery scan on every call (which silently inflated this test's wall-clock timing).
function Import-XrayProbeDiskCache { }
function Save-XrayProbeDiskCache { }
$script:XrayProbeCache = @{}
$script:XrayProbeCacheTtlSec = 1800

$gmContent = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$src = Get-FunctionSource -Content $gmContent -Name 'Test-RemoteXraySocksOpen'
if (-not $src) {
    Write-Host '  FAIL  could not extract Test-RemoteXraySocksOpen - live test cannot run (source drifted)' -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($src))

# RFC5737 TEST-NET-1: reserved for documentation, expected non-routable/black-holed - real TCP
# SYNs go out and get no response. `-Alias` must be a real ssh config Host alias (not a raw IP),
# so we build a temp ssh_config with a `Host` block pointing at the black-hole IP instead, and
# pass it via the `-SshCfgPath` parameter the function already accepts.
$blackHoleIp = '192.0.2.1'
$alias = 'faketarget'
$tmpCfg = [System.IO.Path]::GetTempFileName()
@"
Host $alias
    HostName $blackHoleIp
    User nobody
"@ | Set-Content -LiteralPath $tmpCfg -Encoding ASCII

Write-Host "  INFO  temp ssh config: $tmpCfg -> Host $alias / HostName $blackHoleIp" -ForegroundColor DarkGray

try {
    Write-Host ''
    Write-Host '--- Scenario A: TCP-level black hole (192.0.2.1, per task spec) ---' -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Test-RemoteXraySocksOpen -Alias $alias -SshCfgPath $tmpCfg -RemotePort 10808
    $sw.Stop()

    Write-Host ''
    Write-Host "  MEASURED elapsed wall-clock: $($sw.ElapsedMilliseconds) ms" -ForegroundColor Yellow
    Write-Host '  (code-declared worst case: attempt1 WaitForExit=5000ms + on-timeout retry WaitForExit=6000ms => 11000ms; the H10_proxy_health_timeout comment claims this replaced a flat ~8000ms design)' -ForegroundColor DarkGray
    Write-Host ''

    Assert ($result -eq $false) "Scenario A: Test-RemoteXraySocksOpen against a genuinely unreachable alias correctly returns `$false (got: $result)"
    # BUG 3/4 FIX (Worker G, 2026-07-24): this assert originally required >=8500ms as a
    # RED characterization of the pre-fix retry-stacking worst case (it was already
    # unreliable pre-fix on this network - see comment above about ConnectTimeout=2 firing
    # cleanly against a pure TCP black hole). Post-fix there is no retry to stack, and the
    # single attempt is bounded by ConnectTimeout=6 + WaitForExit(7000), so the real
    # regression guard is simply: never get anywhere near the old ~11000ms worst case.
    Assert ($sw.ElapsedMilliseconds -lt 8000) "Scenario A FIXED: measured $($sw.ElapsedMilliseconds)ms stays under the 8000ms single-attempt budget (ConnectTimeout=6 / WaitForExit(7000)), nowhere near the old ~11000ms stacked-retry worst case"
}
finally {
    Start-Sleep -Milliseconds 500
    $leaked = @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($alias) })
    Assert ($leaked.Count -eq 0) "Scenario A: no orphaned ssh.exe left targeting alias '$alias' ($blackHoleIp) after the timed call (found $($leaked.Count))"

    Remove-Item -LiteralPath $tmpCfg -Force -ErrorAction SilentlyContinue
}

# --- Scenario B: SSH banner exchange completes, then KEX stalls forever -----------------------
# This is the faithful reproduction of the bug's own stated root cause ("cold SSH connection
# stalls under boot-time MaxStartups throttling" / "genuinely slow cold SSH connection setup").
# Verified by hand with `ssh -vv` against this exact listener shape before writing this test:
# `ConnectTimeout` is a single alarm that covers TCP connect() AND the version-banner exchange -
# but the alarm is disarmed the moment the banner exchange completes. Once ssh sends
# SSH2_MSG_KEXINIT and is waiting on the peer's KEXINIT reply, there is NO further ssh-side
# timeout at all - confirmed live: a raw `ssh -vv` client against a listener that sends a valid
# SSH-2.0 banner and then never replies to KEXINIT hung for the full lifetime of the listener
# (15000ms+) until the socket was force-closed, entirely unbounded by ConnectTimeout=2. That means
# the ONLY thing capping this hang in production is this function's own WaitForExit() calls - this
# scenario is what actually proves whether the WaitForExit(5000)+retry WaitForExit(6000) stacking
# (bug 4) reaches ~11s in real practice, not just on paper.
Write-Host ''
Write-Host '--- Scenario B: SSH banner sent, then KEX stalls forever (protocol-level stall) ---' -ForegroundColor Cyan

$probe = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
$probe.Start()
$stallPort = $probe.LocalEndpoint.Port
$probe.Stop()

$stallJob = Start-Job -ScriptBlock {
    param($port, $durationSec)
    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, $port)
    $listener.Start()
    $held = New-Object System.Collections.Generic.List[System.Net.Sockets.TcpClient]
    $deadline = (Get-Date).AddSeconds($durationSec)
    while ((Get-Date) -lt $deadline) {
        if ($listener.Pending()) {
            $c = $listener.AcceptTcpClient()
            try {
                $stream = $c.GetStream()
                $banner = [System.Text.Encoding]::ASCII.GetBytes("SSH-2.0-OpenSSH_for_Testing`r`n")
                $stream.Write($banner, 0, $banner.Length)
                $stream.Flush()
            } catch {}
            $held.Add($c)
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    foreach ($c in $held) { try { $c.Close() } catch {} }
    $listener.Stop()
} -ArgumentList $stallPort, 30

$stallReady = $false
for ($i = 0; $i -lt 40; $i++) {
    try {
        $tc = New-Object System.Net.Sockets.TcpClient
        $tc.Connect('127.0.0.1', $stallPort)
        if ($tc.Connected) { $stallReady = $true; $tc.Close(); break }
    } catch {}
    Start-Sleep -Milliseconds 250
}

$alias2 = 'stalltarget'
$tmpCfg2 = [System.IO.Path]::GetTempFileName()
@"
Host $alias2
    HostName 127.0.0.1
    Port $stallPort
    User nobody
"@ | Set-Content -LiteralPath $tmpCfg2 -Encoding ASCII

try {
    if (-not $stallReady) {
        Write-Host '  FAIL  local stall listener never became ready - Scenario B skipped' -ForegroundColor Red
        $script:fail++
    } else {
        Write-Host "  INFO  temp ssh config: $tmpCfg2 -> Host $alias2 / HostName 127.0.0.1 Port $stallPort (local listener accepts, sends nothing)" -ForegroundColor DarkGray
        $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
        $result2 = Test-RemoteXraySocksOpen -Alias $alias2 -SshCfgPath $tmpCfg2 -RemotePort 10808
        $sw2.Stop()

        Write-Host ''
        Write-Host "  MEASURED elapsed wall-clock: $($sw2.ElapsedMilliseconds) ms" -ForegroundColor Yellow
        Write-Host ''

        Assert ($result2 -eq $false) "Scenario B: Test-RemoteXraySocksOpen against a protocol-level-stalled target correctly returns `$false (got: $result2)"
        # BUG 3/4 FIX (Worker G, 2026-07-24): this assert originally required >=8500ms as a
        # RED characterization of the pre-fix retry-stacking worst case. Real measurement on
        # this network/ssh-client build showed the single first attempt self-terminates via
        # ServerAliveInterval/ServerAliveCountMax dead-peer detection around ~4.1s (well under
        # even the OLD attempt1 WaitForExit(5000) cap), so the retry path was not reliably
        # exercised by this exact scenario either before or after the fix on this build - see
        # the "Fix verification" section below for the unambiguous source-level proof that the
        # retry code is gone. The regression guard that IS meaningful here: stay comfortably
        # under the old ~11000ms worst case regardless of which mechanism ends the attempt.
        Assert ($sw2.ElapsedMilliseconds -lt 8000) "Scenario B FIXED: measured $($sw2.ElapsedMilliseconds)ms stays under the 8000ms single-attempt budget, nowhere near the old ~11000ms stacked-retry worst case"
    }
}
finally {
    Start-Sleep -Milliseconds 500
    $leaked2 = @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($alias2) })
    Assert ($leaked2.Count -eq 0) "Scenario B: no orphaned ssh.exe left targeting alias '$alias2' (127.0.0.1:$stallPort) after the timed call (found $($leaked2.Count))"

    Remove-Item -LiteralPath $tmpCfg2 -Force -ErrorAction SilentlyContinue
    Wait-Job $stallJob -Timeout 25 | Out-Null
    Remove-Job $stallJob -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Bug 3/4 FIX VERIFICATION (Worker G, 2026-07-24, appended - see report). The
# scenario assertions above document raw real-network timing (which the test's
# own comments acknowledge varies run to run and does not always trigger the
# retry path on every network). This section adds unambiguous fix-verification
# on top of that:
#   1. The retry-stacking code (a full second ssh process + its own WaitForExit)
#      must be entirely gone from the real, currently-shipping source.
#   2. The dead H19/H10_proxy_health_timeout debug-log instrumentation writing
#      to debug-c46ba1.log must be entirely gone from the real source.
#   3. Both real measured elapsed times already captured above (Scenario A $sw,
#      Scenario B $sw2) must stay comfortably under the original ~8000ms budget.
#      This is the actual unambiguous regression guard: regardless of raw
#      per-run network timing, a single-attempt design (ConnectTimeout=6,
#      WaitForExit(7000)) can never reach the old 5000+6000=11000ms worst case.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- Fix verification: no retry-stacking, no dead debug-log instrumentation, real worst-case < 8000ms ---' -ForegroundColor Cyan
$srcPostFix = Get-FunctionSource -Content (Get-Content (Get-ClientFile 'git-mode.ps1') -Raw) -Name 'Test-RemoteXraySocksOpen'
Assert ($srcPostFix -notmatch 'retryProc') 'BUG 4 FIXED: real Test-RemoteXraySocksOpen source no longer contains a retry ssh process (retryProc)'
Assert (@($srcPostFix -split "`n" | Where-Object { $_ -match 'Start-Process' }).Count -eq 1) 'BUG 4 FIXED: real source now starts exactly ONE ssh process (no second/retry Start-Process call)'
Assert ($srcPostFix -notmatch 'debug-c46ba1\.log') 'consolidation: real source no longer writes to the dead debug-c46ba1.log artifact'
Assert ($srcPostFix -notmatch 'H19|H10_proxy_health_timeout') 'consolidation: real source no longer contains H19/H10_proxy_health_timeout debug-log tags'
if ($null -ne $sw) {
    Assert ($sw.ElapsedMilliseconds -lt 8000) "BUG 3/4 FIXED: Scenario A real measured elapsed ($($sw.ElapsedMilliseconds)ms) stays under the 8000ms budget with the single-attempt design"
}
if ($null -ne $sw2) {
    Assert ($sw2.ElapsedMilliseconds -lt 8000) "BUG 3/4 FIXED: Scenario B real measured elapsed ($($sw2.ElapsedMilliseconds)ms) stays under the 8000ms budget with the single-attempt design (old stacked design could reach ~11000ms here)"
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
