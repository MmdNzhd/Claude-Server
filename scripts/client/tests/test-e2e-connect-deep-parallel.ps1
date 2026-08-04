#Requires -Version 5.1
# test-e2e-connect-deep-parallel.ps1
# Deep Rank-1 Connect E2E: parallel boots + post-hoc day-log session parse.
# TEST ONLY. Does NOT modify product connect.ps1.
#
#   powershell -File test-e2e-connect-deep-parallel.ps1 -Parallel 3 -ProjectSlot 1
#   powershell -File test-e2e-connect-deep-parallel.ps1 -Parallel 3 -AlsoAgentHello
#   powershell -File test-e2e-connect-deep-parallel.ps1 -Parallel 3 -Strict -AlsoAgentHello -MaxSeconds 240
#   powershell -File test-e2e-connect-deep-parallel.ps1 -Parallel 3 -Precise -AlsoAgentHello
param(
    [int]$Parallel = 3,
    [int]$ProjectSlot = 1,
    # Distinct menu numbers (one folder per worker). Default: ProjectSlot..(ProjectSlot+Parallel-1)
    [int[]]$ProjectSlots = @(),
    [int]$MaxSeconds = 150,
    [int]$StaggerMs = 2500,
    # Strict: wait past SCORECARD for AGENT_PATH + MOUNT_BG; fail (not skip) on missing hygiene.
    [switch]$Strict,
    # Precise: implies Strict + WMCP every worker + listen_conf=1 + zero LOG_SYNC NRE.
    [switch]$Precise,
    [int]$SettleSeconds = 75,
    [switch]$AlsoAgentHello,
    [string]$Workspace = '',
    [string]$ConnectBootPath = ''
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
. (Join-Path $PSScriptRoot 'e2e\_e2e-common.ps1')
if ($Precise) { $Strict = $true }

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }
function SkipMsg([string]$Msg) { Write-Host "  SKIP  $Msg" -ForegroundColor Yellow; $script:Skip++ }

Write-Host ''
Write-Host '=== E2E DEEP PARALLEL Connect (test-only; post-hoc log parse) ===' -ForegroundColor Cyan
Write-Host ''

if ($Parallel -lt 1) { $Parallel = 1 }
if ($Parallel -gt 10) {
    SkipMsg "Parallel=$Parallel capped to 10 (ClaudeConnect# slot ceiling)"
    $Parallel = 10
}

$boot = Get-E2eConnectBootPath
if ($ConnectBootPath -and (Test-Path -LiteralPath $ConnectBootPath)) { $boot = $ConnectBootPath }
Assert ($null -ne $boot -and (Test-Path -LiteralPath $boot)) ("boot path: $boot")
$installCurrentVer = Get-E2eInstallCurrentVersion
if ($installCurrentVer -match '^\d{8}\.\d+$') {
    Assert ($boot -match [regex]::Escape($installCurrentVer)) ("boot path contains install-current version $installCurrentVer")
}
if (-not $boot -or -not (Test-Path -LiteralPath $boot)) {
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}

$free = Get-E2eFreeConnectSlotCount
Note ("free ClaudeConnect# slots = $free / 10 (need >= $Parallel)")
if ($free -lt $Parallel) {
    SkipMsg "not enough free slots ($free < $Parallel) - refuse parallel storm"
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

$dayLog = Get-E2eDayLogPath
$resultsDir = Get-E2eResultsDir
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$protectedCursor = @(Get-E2eProtectedCursorRootPids)
$protectedTunnel = @(Get-E2eMainTunnelPids)
Note ("protect cursor=[$($protectedCursor -join ',')] tunnel=[$($protectedTunnel -join ',')]")

# One DISTINCT project menu slot per worker (same folder => skip_launch already_on_folder - NOT a 3-Cursor test).
# Argv quirks under powershell -File / parent expansion — normalize to small menu ints (1..N).
$slotAcc = New-Object System.Collections.Generic.List[int]
foreach ($x in @($ProjectSlots)) {
    $raw = ("$x").Trim()
    if (-not $raw) { continue }
    foreach ($p in ($raw -split '[,\s;]+')) {
        $p = "$p".Trim()
        if ($p -match '^\d{1,2}$') { [void]$slotAcc.Add([int]$p) }  # menu # are 1-2 digits; reject 123 from bad casts
    }
}
$ProjectSlots = @($slotAcc | Select-Object -Unique)
if ($ProjectSlots.Count -eq 1 -and $Parallel -gt 1) {
    $start = [int]$ProjectSlots[0]
    $ProjectSlots = @()
    for ($s = 0; $s -lt $Parallel; $s++) { $ProjectSlots += ($start + $s) }
}
if (-not $ProjectSlots -or $ProjectSlots.Count -lt 1) {
    $ProjectSlots = @()
    for ($s = 0; $s -lt $Parallel; $s++) { $ProjectSlots += ($ProjectSlot + $s) }
}
if ($ProjectSlots.Count -lt $Parallel) {
    Assert $false ("ProjectSlots count $($ProjectSlots.Count) < Parallel=$Parallel - need one folder menu # per worker")
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}
$uniqSlots = @($ProjectSlots | Select-Object -Unique)
if ($uniqSlots.Count -lt $Parallel) {
    Assert $false ("ProjectSlots must be DISTINCT for parallel Cursor opens (got: $($ProjectSlots -join ','))")
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}
Note ("project menu slots (distinct folders) = [$($ProjectSlots[0..($Parallel-1)] -join ',')]")
if ($Strict -and $MaxSeconds -lt 200) {
    Note "Strict: raising MaxSeconds $MaxSeconds -> 240"
    $MaxSeconds = 240
}
if ($Precise -and $Parallel -ge 6 -and $MaxSeconds -lt 360) {
    Note ("Precise x{0}: raising MaxSeconds {1} -> 420" -f $Parallel, $MaxSeconds)
    $MaxSeconds = 420
}
if ($Precise -and $Parallel -ge 6 -and $StaggerMs -lt 3500) {
    Note ("Precise x{0}: raising StaggerMs {1} -> 4000" -f $Parallel, $StaggerMs)
    $StaggerMs = 4000
}
if ($Strict) {
    Note ("Strict hygiene settle={0}s (wait AGENT_PATH + MOUNT_BG after SCORECARD)" -f $SettleSeconds)
}
if ($Precise) {
    if ($SettleSeconds -lt 100) { $SettleSeconds = 100 }
    if ($Parallel -ge 6 -and $SettleSeconds -lt 180) { $SettleSeconds = 180 }
    Note ("Precise: settle={0}s WMCP+listen_conf+SCORECARD agent_path + zero WARN/NRE/ERROR" -f $SettleSeconds)
}

# --- Launch parallel connect-boot processes ---
# CRITICAL: parent shell may have sticky CLAUDE_CONNECT_RUN_ID (e.g. OPT_PipeY2_193918).
# Each worker MUST get a unique RUN_ID or all log lines collide on one session tag.
$workers = @()
$t0 = Get-Date
for ($i = 1; $i -le $Parallel; $i++) {
    if ($i -gt 1) { Start-Sleep -Milliseconds $StaggerMs }
    $runId = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $slotForWorker = [int]$ProjectSlots[$i - 1]
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $boot + '"'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    foreach ($key in [System.Environment]::GetEnvironmentVariables().Keys) {
        try { $psi.EnvironmentVariables[$key] = [string][System.Environment]::GetEnvironmentVariable($key) } catch {}
    }
    $psi.EnvironmentVariables['CLAUDE_CONNECT_RUN_ID'] = $runId
    $proc = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Milliseconds 700
    foreach ($delayMs in @(200, 500, 1000, 2000)) {
        try { $proc.StandardInput.WriteLine([string]$slotForWorker) } catch {}
        Start-Sleep -Milliseconds $delayMs
    }
    try { $proc.StandardInput.Close() } catch {}
    $workers += [pscustomobject]@{
        N             = $i
        Proc          = $proc
        RootPid       = $proc.Id
        RunId         = $runId
        SessionId     = $runId
        ProjectSlot   = $slotForWorker
        Sw            = [Diagnostics.Stopwatch]::StartNew()
        Done          = $false
        Report        = $null
        T0            = Get-Date
        ScorecardAt   = $null
    }
    Note ("launched worker $i/$Parallel root_pid=$($proc.Id) run_id=$runId menu_slot=$slotForWorker")
}

# --- Wait / resolve session ids / stop on SCORECARD (+ Strict hygiene settle) or timeout ---
$deadline = $t0.AddSeconds($MaxSeconds)
while ((Get-Date) -lt $deadline) {
    $allDone = $true
    foreach ($w in $workers) {
        if ($w.Done) { continue }
        $allDone = $false
        # Confirm our unique RUN_ID actually appeared with this root pid (or child relaunch pid)
        $sid = Resolve-E2eSessionId -DayLog $dayLog -RootPid $w.RootPid -NotBefore $w.T0 -ExpectedSession $w.RunId
        if (-not $sid) {
            # connect-boot may relaunch into a child powershell - scan for ExpectedSession alone after T0
            $probe0 = Get-E2eSessionDeepReportWindowed -DayLog $dayLog -SessionId $w.RunId -RootPid $w.RootPid -NotBefore $w.T0
            if ($probe0.SessionStartCount -ge 1) { $sid = $w.RunId }
        }
        if ($sid) { $w.SessionId = $sid }
        if ($w.SessionId) {
            $probe = Get-E2eSessionDeepReportWindowed -DayLog $dayLog -SessionId $w.SessionId -RootPid $w.RootPid -NotBefore $w.T0
            $rankReady = [bool]($probe.Scorecard -or $probe.VerdictCode -eq 'CURSOR_ON_FOLDER_OK')
            if ($rankReady -and -not $w.ScorecardAt) {
                $w.ScorecardAt = Get-Date
                Note ("worker $($w.N) SCORECARD/verdict seen session=$($w.SessionId) - settle hygiene")
            }
            $hygieneReady = $true
            if ($Strict) {
                $mountReady = [bool](
                    $probe.MountBgOk -or $probe.MountBgFail -or $probe.MountBgSkip -or $probe.MountVerifyBound
                )
                $hygieneReady = [bool](
                    ($probe.AgentPathOk -or $probe.AgentPathBad) -and $mountReady
                )
                if ($Precise) {
                    $wmcpHealthy = [bool]($probe.WmcpProbe -and -not $probe.WmcpSixZeros -and $probe.WmcpProbe -notmatch '^0+$')
                    $hygieneReady = [bool]($hygieneReady -and $wmcpHealthy -and $probe.AgentListenConf -and $probe.ScorecardAgentOk)
                }
                if (-not $hygieneReady -and $w.ScorecardAt) {
                    $elapsedSettle = ((Get-Date) - $w.ScorecardAt).TotalSeconds
                    if ($elapsedSettle -ge $SettleSeconds) {
                        Note ("worker $($w.N) settle timeout ${SettleSeconds}s (agent=$($probe.AgentPathOk)/bad=$($probe.AgentPathBad) bgok=$($probe.MountBgOk)/fail=$($probe.MountBgFail) wmcp=$($probe.WmcpProbe) listen=$($probe.AgentListenConf) sc_agent=$($probe.ScorecardAgentOk))")
                        $hygieneReady = $true  # stop waiting; asserts will fail hard below
                    }
                }
            }
            if ($rankReady -and $hygieneReady) {
                $w.Report = $probe
                $w.Done = $true
                $w.Sw.Stop()
                Note ("worker $($w.N) complete session=$($w.SessionId) scorecard=$($probe.Scorecard) verdict=$($probe.VerdictCode) strict=$Strict")
                if (-not $w.Proc.HasExited) { Stop-E2eProcessTree -RootPid $w.RootPid }
            }
        }
        if ($w.Proc.HasExited -and -not $w.Done) {
            $w.Done = $true
            $w.Sw.Stop()
        }
    }
    if ($allDone) { break }
    Start-Sleep -Seconds 2
}

# Force-stop stragglers
foreach ($w in $workers) {
    if (-not $w.Proc.HasExited) { Stop-E2eProcessTree -RootPid $w.RootPid }
    $w.Sw.Stop()
    $w.Done = $true
}
Start-Sleep -Seconds 2

# Cleanup only NEW cursor/tunnel litter (keep protected)
$afterCursor = @(Get-E2eProtectedCursorRootPids)
foreach ($ncp in @($afterCursor | Where-Object { $protectedCursor -notcontains $_ })) {
    try { Stop-Process -Id $ncp -Force -ErrorAction SilentlyContinue } catch {}
}
$afterTunnel = @(Get-E2eMainTunnelPids)
foreach ($nt in @($afterTunnel | Where-Object { $protectedTunnel -notcontains $_ })) {
    try { Stop-Process -Id $nt -Force -ErrorAction SilentlyContinue } catch {}
}

# --- Post-hoc deep parse (authoritative) ---
Write-Host ''
Note 'POST-HOC deep day-log parse (authoritative Rank-1)'
$reports = @()
foreach ($w in $workers) {
    $w.SessionId = $w.RunId
    # Confirm session actually logged
    $probeConfirm = Get-E2eSessionDeepReportWindowed -DayLog $dayLog -SessionId $w.RunId -RootPid $w.RootPid -NotBefore $w.T0
    Write-Host ("--- worker {0} root_pid={1} run_id={2} menu_slot={3} ms={4} ---" -f $w.N, $w.RootPid, $w.RunId, $w.ProjectSlot, [int]$w.Sw.ElapsedMilliseconds) -ForegroundColor White
    if ($probeConfirm.LineCount -lt 1 -and $probeConfirm.SessionStartCount -lt 1) {
        $alt = Resolve-E2eSessionId -DayLog $dayLog -RootPid $w.RootPid -NotBefore $w.T0
        if ($alt -and ($alt -ne $w.RunId)) {
            Assert $false ("worker $($w.N): sticky RUN_ID / lost RunId (expected=$($w.RunId) alt=$alt pid=$($w.RootPid))")
            continue
        }
    }
    if ($probeConfirm.LineCount -lt 1) {
        Assert $false ("worker $($w.N): no day-log lines for run_id=$($w.RunId) pid=$($w.RootPid) after $($w.T0.ToString('HH:mm:ss'))")
        continue
    }
    $rep = $probeConfirm
    $w.Report = $rep
    $reports += $rep
    Write-E2eDeepReportHost -Report $rep
    Assert ([bool]$rep.Rank1Pass) ("worker $($w.N) Rank-1 deep pass (SCORECARD/verdict/on_folder+mount+keep)")
    if ($rep.Scorecard) {
        Assert $true ("worker $($w.N) SCORECARD present am=$($rep.ScorecardProject)")
    } else {
        SkipMsg "worker $($w.N) no SCORECARD line (may still Rank-1 via verdict)"
    }
    # Distinct-folder parallel: each worker must REALLY launch, not reuse another window.
    if ($rep.LaunchSkipReuse -and -not $rep.DidRealLaunch) {
        Assert $false ("worker $($w.N) skip_launch/already_on_folder without LAUNCH_ATTEMPT (same-folder reuse - not a distinct open)")
    } elseif ($rep.DidRealLaunch) {
        Assert $true ("worker $($w.N) real Cursor launch (LAUNCH_OK/ATTEMPT)")
    } else {
        Assert $false ("worker $($w.N) no LAUNCH_OK/ATTEMPT in day log - did not open Cursor for its folder")
    }
    if ($rep.LaunchForceNw) {
        Assert $false ("worker $($w.N) saw force_new_window in log - product ForceNewWindow must stay reverted")
    }
    if ($rep.AgentPathOk) {
        Assert $true ("worker $($w.N) AGENT_PATH ok")
    } elseif ($rep.AgentPathBad) {
        Assert $false ("worker $($w.N) AGENT_PATH bad without later ok: $($rep.AgentPathLine)")
    } elseif ($Strict) {
        Assert $false ("worker $($w.N) AGENT_PATH not logged (Strict requires boot probe)")
    } else {
        SkipMsg "worker $($w.N) AGENT_PATH not logged"
    }
    if ($rep.MountBgFail -and -not $rep.MountBgOk) {
        Assert $false ("worker $($w.N) MOUNT_BG_FAIL without MOUNT_BG_OK")
    } elseif ($rep.MountBgOk) {
        Assert $true ("worker $($w.N) MOUNT_BG_OK$(if ($rep.MountBgRetry) { ' (after retry)' } else { '' })")
    } elseif ($rep.MountBgSkip -or $rep.MountVerifyBound) {
        Assert $true ("worker $($w.N) mount ready via skip/bound (skip=$($rep.MountBgSkip) bound=$($rep.MountVerifyBound))")
    } elseif ($Strict) {
        Assert $false ("worker $($w.N) MOUNT_BG_* / bound not logged (Strict)")
    } else {
        SkipMsg "worker $($w.N) MOUNT_BG_* not logged (may still be in-flight)"
    }
    if ($Strict) {
        if ($rep.MountVerifyBound -or ($rep.MountVerifyOk -and $rep.MountBgOk)) {
            Assert $true ("worker $($w.N) mount verified (bound=$($rep.MountVerifyBound) ls_ok=$($rep.MountVerifyOk))")
        } else {
            Assert $false ("worker $($w.N) Strict needs MountVerifyBound or (ls_ok+MOUNT_BG_OK)")
        }
    }
    if ($rep.KeyAvailableCrash) {
        Assert $false ("worker $($w.N) KeyAvailable/UNHANDLED after success (must be zero after console-key-safe fix)")
    } else {
        Assert $true ("worker $($w.N) no KeyAvailable crash")
    }
    if ($rep.UnhandledFail) {
        Assert $false ("worker $($w.N) FAIL UNHANDLED or UPDATE_UNHANDLED in day log")
    } else {
        Assert $true ("worker $($w.N) no unhandled fail marker")
    }
    if ($rep.LogSyncException) {
        Assert $false ("worker $($w.N) LOG_SYNC_FAIL detail=exception in day log")
    } else {
        Assert $true ("worker $($w.N) no LOG_SYNC_FAIL exception")
    }
    if ($Precise) {
        if ($rep.LogSyncNre) {
            Assert $false ("worker $($w.N) LOG_SYNC_FAIL NullReferenceException (Precise forbids)")
        } else {
            Assert $true ("worker $($w.N) no LOG_SYNC NRE")
        }
        if ($rep.AgentListenConf) {
            Assert $true ("worker $($w.N) AGENT_PATH listen_conf=1")
        } else {
            Assert $false ("worker $($w.N) AGENT_PATH missing listen_conf=1")
        }
        if ($rep.ScorecardAgentOk) {
            Assert $true ("worker $($w.N) SCORECARD agent_path=ok")
        } else {
            Assert $false ("worker $($w.N) SCORECARD missing agent_path=ok")
        }
    }
    if ($rep.WmcpProbe) {
        if ($rep.WmcpSixZeros) {
            Assert $false ("worker $($w.N) WMCP_PROBE=$($rep.WmcpProbe) is six zeros (broken forward)")
        } elseif ($rep.WmcpProbe -eq '000' -or $rep.WmcpProbe -match '^0+$') {
            if ($Strict) {
                Assert $false ("worker $($w.N) WMCP_PROBE=$($rep.WmcpProbe) (curl/forward dead; Strict)")
            } else {
                SkipMsg "worker $($w.N) WMCP_PROBE=$($rep.WmcpProbe) zeros (non-Strict soft)"
            }
        } else {
            Assert $true ("worker $($w.N) WMCP_PROBE=$($rep.WmcpProbe) not six zeros")
        }
    } elseif ($Precise) {
        Assert $false ("worker $($w.N) WMCP_PROBE not logged (Precise requires every worker)")
    } elseif ($Strict) {
        # Primary worker usually logs WMCP; peers may race. Require at least one of 3 later.
        SkipMsg "worker $($w.N) WMCP_PROBE not logged (Strict peer soft-skip; fleet check below)"
    } else {
        SkipMsg "worker $($w.N) WMCP_PROBE not logged"
    }
    if ($installCurrentVer -match '^\d{8}\.\d+$' -and $rep.ConnectVersion) {
        Assert ($rep.ConnectVersion -eq $installCurrentVer) `
            ("worker $($w.N) CONNECT_VERSION=$($rep.ConnectVersion) matches install-current $installCurrentVer")
    } elseif ($installCurrentVer -match '^\d{8}\.\d+$') {
        SkipMsg "worker $($w.N) CONNECT_VERSION not logged (install-current=$installCurrentVer)"
    }
    $outFile = Join-Path $resultsDir ("deep-parallel-{0}-w{1}.json" -f $stamp, $w.N)
    $rep | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outFile -Encoding UTF8
    Note ("wrote $outFile")
}

$rank1Ok = @($reports | Where-Object { $_.Rank1Pass }).Count
$launchOkN = @($reports | Where-Object { $_.DidRealLaunch }).Count
$projects = @($reports | ForEach-Object { $_.ScorecardProject } | Where-Object { $_ } | Select-Object -Unique)
Assert ($rank1Ok -ge 1) ("at least 1/$Parallel workers Rank-1 deep-pass (got $rank1Ok)")
Assert ($rank1Ok -eq $Parallel -or $rank1Ok -ge [Math]::Ceiling($Parallel * 0.66)) `
    ("majority Rank-1: $rank1Ok / $Parallel (>=66%)")
Assert ($launchOkN -eq $Parallel) ("every worker real-launched Cursor: $launchOkN / $Parallel")
if ($projects.Count -ge 2) {
    Assert $true ("distinct SCORECARD projects: [$($projects -join ',')] count=$($projects.Count)")
} elseif ($Parallel -gt 1) {
    Assert $false ("expected distinct project folders in SCORECARD am= (got only: [$($projects -join ',')]) - pass distinct -ProjectSlots")
}

if ($Parallel -ge 2 -and $reports.Count -ge 2) {
    $anyLaunchGate = @($reports | Where-Object { $_.LaunchGate -or $_.LaunchGatePeer }).Count -gt 0
    Assert $anyLaunchGate ("parallel>=2: at least one LaunchGate or LaunchGatePeer across workers")
    $coldNoNwSum = ($reports | ForEach-Object { [int]$_.ColdStartNoNwCount } | Measure-Object -Sum).Sum
    $anyLaunchGatePeer = @($reports | Where-Object { $_.LaunchGatePeer }).Count -gt 0
    $gateAcquiredN = @($reports | Where-Object { $_.LaunchGate -eq 'acquired' }).Count
    if (($coldNoNwSum -le 1) -or $anyLaunchGatePeer -or ($Parallel -ge 4 -and $gateAcquiredN -ge [Math]::Ceiling($Parallel * 0.66))) {
        Assert $true ("parallel cold_start+no_nw sum=$coldNoNwSum gate_peer=$anyLaunchGatePeer gate_acq=$gateAcquiredN")
    } else {
        Assert $false ("parallel cold_start use_new_window=False sum=$coldNoNwSum >1 without LaunchGatePeer")
    }
}

if ($Strict) {
    $agentOkN = @($reports | Where-Object { $_.AgentPathOk }).Count
    $bgOkN = @($reports | Where-Object { $_.MountBgOk }).Count
    $wmcpOkN = @($reports | Where-Object { $_.WmcpProbe -and -not $_.WmcpSixZeros -and $_.WmcpProbe -notmatch '^0+$' }).Count
    $mountReadyN = @($reports | Where-Object { $_.MountBgOk -or $_.MountBgSkip -or $_.MountVerifyBound }).Count
    Assert ($agentOkN -eq $Parallel) ("Strict: every worker AGENT_PATH ok ($agentOkN / $Parallel)")
    Assert ($mountReadyN -eq $Parallel) ("Strict: every worker mount ready BG_OK/skip/bound ($mountReadyN / $Parallel; bg_ok=$bgOkN)")
    Assert ($wmcpOkN -ge 1) ("Strict: at least one worker WMCP_PROBE healthy (got $wmcpOkN)")
    $badResidual = @($reports | Where-Object {
        $_.KeyAvailableCrash -or $_.UnhandledFail -or $_.LogSyncException -or $_.WmcpSixZeros -or ($_.MountBgFail -and -not $_.MountBgOk)
    }).Count
    Assert ($badResidual -eq 0) ("Strict: zero residual crash/logsync/wmcp6z/mount_fail workers (got $badResidual)")
}
if ($Precise) {
    $wmcpAll = @($reports | Where-Object { $_.WmcpProbe -eq '200' }).Count
    $listenAll = @($reports | Where-Object { $_.AgentListenConf }).Count
    $scAgentAll = @($reports | Where-Object { $_.ScorecardAgentOk }).Count
    $nreN = @($reports | Where-Object { $_.LogSyncNre }).Count
    $errN = @($reports | Where-Object { $_.ErrorCount -gt 0 }).Count
    $warnN = @($reports | Where-Object { $_.WarnCount -gt 0 }).Count
    $warnSum = ($reports | ForEach-Object { [int]$_.WarnCount } | Measure-Object -Sum).Sum
    Assert ($wmcpAll -eq $Parallel) ("Precise: every worker WMCP_PROBE=200 ($wmcpAll / $Parallel)")
    Assert ($listenAll -eq $Parallel) ("Precise: every worker listen_conf=1 ($listenAll / $Parallel)")
    Assert ($scAgentAll -eq $Parallel) ("Precise: every SCORECARD agent_path=ok ($scAgentAll / $Parallel)")
    Assert ($nreN -eq 0) ("Precise: zero LOG_SYNC NullReferenceException workers (got $nreN)")
    Assert ($errN -eq 0) ("Precise: zero [ERROR] lines across workers (got $errN)")
    # Zero-noise: after demoting expected multi-Connect chatter to INFO, day-log [WARN] must be 0.
    Assert ($warnSum -eq 0) ("Precise zero-noise: total [WARN] lines across workers = $warnSum (noisy workers=$warnN / $Parallel)")
    if ($warnSum -gt 0) {
        foreach ($r in @($reports | Where-Object { $_.WarnCount -gt 0 })) {
            Note ("noise session=$($r.SessionId) warn=$($r.WarnCount)")
            foreach ($wl in @($r.Warns | Select-Object -First 6)) {
                Note ("  WARN: $($wl -replace '^.*?\]\s*','')")
            }
        }
    }
}

# --- Optional parallel agent hello ---
if ($AlsoAgentHello) {
    Write-Host ''
    Note 'PARALLEL agent hello (Rank-2 CLI; not GUI Chat)'
    $agent = Get-E2eAgentCommand
    if (-not $agent) {
        SkipMsg 'agent CLI missing - skip AlsoAgentHello'
    } else {
        if (-not $Workspace) { $Workspace = $script:RepoRoot }
        $Workspace = [IO.Path]::GetFullPath($Workspace)
        $helloJobs = @()
        for ($i = 1; $i -le $Parallel; $i++) {
            $token = 'PONG-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
            $stdoutFile = Join-Path $resultsDir ("deep-agent-{0}-w{1}.out.txt" -f $stamp, $i)
            $stderrFile = Join-Path $resultsDir ("deep-agent-{0}-w{1}.err.txt" -f $stamp, $i)
            $prompt = "Reply with exactly one line containing this token and nothing else before it: $token"
            $argList = @(
                '--print', '--trust', '--output-format', 'text', '--mode', 'ask',
                '--workspace', $Workspace, $prompt
            )
            if ($agent -match '\.ps1$') {
                $p = Start-Process -FilePath 'powershell.exe' `
                    -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agent) + $argList) `
                    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
                    -PassThru -WindowStyle Hidden
            } else {
                $p = Start-Process -FilePath $agent -ArgumentList $argList `
                    -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile `
                    -PassThru -WindowStyle Hidden
            }
            $helloJobs += [pscustomobject]@{ N = $i; Proc = $p; Token = $token; Out = $stdoutFile; Err = $stderrFile }
            Note ("agent worker $i started pid=$($p.Id) token=$token")
        }
        $helloDeadline = (Get-Date).AddSeconds(150)
        while ((Get-Date) -lt $helloDeadline) {
            $left = @($helloJobs | Where-Object { -not $_.Proc.HasExited }).Count
            if ($left -eq 0) { break }
            Start-Sleep -Seconds 3
        }
        foreach ($hj in $helloJobs) {
            if (-not $hj.Proc.HasExited) {
                try {
                    # Kill tree: agent leaves ssh -D socks that starve MaxStartups on next round.
                    Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/F', '/T', '/PID', "$($hj.Proc.Id)") -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
                } catch {}
                try { Stop-Process -Id $hj.Proc.Id -Force -ErrorAction SilentlyContinue } catch {}
                SkipMsg ("agent worker {0} timed out" -f $hj.N)
                continue
            }
            $body = ''
            if (Test-Path -LiteralPath $hj.Out) { $body = Get-Content -LiteralPath $hj.Out -Raw -ErrorAction SilentlyContinue }
            $errBody = ''
            if (Test-Path -LiteralPath $hj.Err) { $errBody = Get-Content -LiteralPath $hj.Err -Raw -ErrorAction SilentlyContinue }
            if ($body -and ($body -match [regex]::Escape($hj.Token))) {
                Assert $true ("agent worker $($hj.N) token $($hj.Token)")
            } else {
                Note ("agent worker $($hj.N) out_len=$(if($body){$body.Length}else{0}) err_head=$([string]$errBody.Substring(0,[Math]::Min(80,[string]$errBody.Length)))")
                Assert $false ("agent worker $($hj.N) missing token $($hj.Token)")
            }
        }
        # Always reap leftover agent SOCKS ssh (-T -D N claude-server); R2 hung under 37 orphans (20260804.32).
        try {
            $sockOrphans = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -and $_.CommandLine -match '-T\s+-D\s+\d+' -and $_.CommandLine -match 'claude-server' })
            foreach ($so in $sockOrphans) {
                try { Stop-Process -Id $so.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
            }
            if ($sockOrphans.Count -gt 0) {
                Note ("agent hello reaped {0} leftover ssh -D claude-server process(es)" -f $sockOrphans.Count)
            }
        } catch { }
    }
}

# Summary table
Write-Host ''
Write-Host '=== DEEP SUMMARY ===' -ForegroundColor White
foreach ($r in $reports) {
    Write-Host ("  {0} rank1={1} scorecard={2} verdict={3} keep={4} keycrash={5} err={6} warn={7} ver={8} gate={9} peer={10}" -f `
        $r.SessionId, $r.Rank1Pass, $r.Scorecard, $r.VerdictCode, $r.KeepMarker, $r.KeyAvailableCrash, $r.ErrorCount, $r.WarnCount, $r.ConnectVersion, $r.LaunchGate, $r.LaunchGatePeer)
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip | parallel={3} rank1_ok={4}" -f $Pass, $Fail, $Skip, $Parallel, $rank1Ok) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
