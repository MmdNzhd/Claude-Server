#Requires -Version 5.1
# test-e2e-precise-soak.ps1
# Run Precise Parallel Connect E2E for N consecutive rounds; stop on first fail.
#
#   powershell -File test-e2e-precise-soak.ps1 -Rounds 20 -Parallel 6 -Precise -AlsoAgentHello
param(
    [int]$Rounds = 20,
    [int]$Parallel = 6,
    [switch]$Precise,
    [switch]$AlsoAgentHello,
    [switch]$StopOnFirstFail,
    [int]$MaxSeconds = 420,
    [int]$SettleSeconds = 75,
    [int]$CooldownSeconds = 25,
    [string]$Workspace = ''
)
$ErrorActionPreference = 'Continue'
if (-not $Precise) { $Precise = $true }
if (-not $PSBoundParameters.ContainsKey('StopOnFirstFail')) { $StopOnFirstFail = $true }

$deep = Join-Path $PSScriptRoot 'test-e2e-connect-deep-parallel.ps1'
if (-not (Test-Path -LiteralPath $deep)) {
    Write-Host "FAIL  missing $deep" -ForegroundColor Red
    exit 1
}

$harnessDir = Join-Path $env:USERPROFILE '.config\claude-connect\e2e-harness'
if (-not (Test-Path -LiteralPath $harnessDir)) {
    New-Item -ItemType Directory -Force -Path $harnessDir | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $harnessDir ("precise-soak-{0}.log" -f $stamp)
$summaryPath = Join-Path $harnessDir ("precise-soak-{0}.json" -f $stamp)

Write-Host ''
Write-Host ("=== Precise soak: rounds={0} parallel={1} stop_on_fail={2} ===" -f $Rounds, $Parallel, [bool]$StopOnFirstFail) -ForegroundColor Cyan
Write-Host ("log: {0}" -f $logPath) -ForegroundColor DarkGray
Write-Host ''

$roundResults = New-Object System.Collections.Generic.List[object]
$passed = 0
$failed = 0
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

for ($r = 1; $r -le $Rounds; $r++) {
    $roundTag = "ROUND $r / $Rounds"
    Write-Host ("-------- {0} --------" -f $roundTag) -ForegroundColor Yellow
    Add-Content -LiteralPath $logPath -Value ("======== {0} start {1} ========" -f $roundTag, (Get-Date -Format 'o')) -Encoding UTF8

    # Pre-round: kill orphan local reverse tunnels in the Connect port block so
    # STALE_FORWARD zombies from a prior soak do not WARN every worker (Precise×6).
    try {
        $orphans = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                (
                    $_.CommandLine -match '-R\s+2002[0-9]:' -or
                    ($_.CommandLine -match '-T\s+-D\s+\d+' -and $_.CommandLine -match 'claude-server')
                )
            })
        foreach ($op in $orphans) {
            try { Stop-Process -Id $op.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
        if ($orphans.Count -gt 0) {
            Write-Host ("  pre-clean killed {0} orphan ssh -R/-D process(es)" -f $orphans.Count) -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
        }
    } catch { }

    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $deep,
        '-Parallel', "$Parallel",
        '-MaxSeconds', "$MaxSeconds",
        '-SettleSeconds', "$SettleSeconds"
    )
    if ($Precise) { $args += '-Precise' }
    if ($AlsoAgentHello) { $args += '-AlsoAgentHello' }
    if ($Workspace) { $args += @('-Workspace', $Workspace) }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $out = & powershell.exe @args 2>&1 | ForEach-Object { "$_" }
    $ec = $LASTEXITCODE
    $sw.Stop()
    $out | ForEach-Object { Add-Content -LiteralPath $logPath -Value $_ -Encoding UTF8 }

    $resultLine = ($out | Where-Object { $_ -match 'RESULT:\s+\d+\s+pass' } | Select-Object -Last 1)
    $ok = ($ec -eq 0) -and ($resultLine -match 'RESULT:\s+(\d+)\s+pass\s*/\s*(\d+)\s+fail') -and ([int]$Matches[2] -eq 0)
    if ($resultLine -match 'RESULT:\s+(\d+)\s+pass\s*/\s*(\d+)\s+fail') {
        $p = [int]$Matches[1]; $f = [int]$Matches[2]
    } else {
        $p = 0; $f = 1
        $ok = $false
    }

    $entry = [pscustomobject]@{
        round = $r
        exit_code = $ec
        pass = $p
        fail = $f
        ok = [bool]$ok
        ms = [int]$sw.ElapsedMilliseconds
        result_line = "$resultLine"
    }
    [void]$roundResults.Add($entry)

    if ($ok) {
        $passed++
        Write-Host ("  OK    {0} ({1}ms) {2}" -f $roundTag, $sw.ElapsedMilliseconds, $resultLine) -ForegroundColor Green
    } else {
        $failed++
        Write-Host ("  FAIL  {0} exit={1} ({2}ms) {3}" -f $roundTag, $ec, $sw.ElapsedMilliseconds, $resultLine) -ForegroundColor Red
        Add-Content -LiteralPath $logPath -Value ("======== {0} FAIL ========" -f $roundTag) -Encoding UTF8
        if ($StopOnFirstFail) { break }
    }

    if ($r -lt $Rounds -and $CooldownSeconds -gt 0) {
        # Drain leftover server-profile Cursor windows so round N+1 is not starved
        # (R8/R1 after long soaks: LAUNCH_FAIL started_but_no_process under profile load).
        try {
            $prot = @()
            if (Get-Command Get-E2eProtectedCursorRootPids -ErrorAction SilentlyContinue) {
                $prot = @(Get-E2eProtectedCursorRootPids)
            }
            $litter = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.CommandLine -and
                    $_.CommandLine -match 'ClaudeServerCursorProfile' -and
                    ($prot -notcontains [int]$_.ProcessId)
                })
            foreach ($lp in $litter) {
                try { Stop-Process -Id $lp.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
            }
            if ($litter.Count -gt 0) {
                Write-Host ("  drained {0} server-profile Cursor process(es)" -f $litter.Count) -ForegroundColor DarkGray
            }
        } catch { }
        Write-Host ("  cooldown {0}s..." -f $CooldownSeconds) -ForegroundColor DarkGray
        Start-Sleep -Seconds $CooldownSeconds
    }
}

$swAll.Stop()
$roundArr = @($roundResults | ForEach-Object {
    @{
        round = [int]$_.round
        exit_code = [int]$_.exit_code
        pass = [int]$_.pass
        fail = [int]$_.fail
        ok = [bool]$_.ok
        ms = [int]$_.ms
        result_line = [string]$_.result_line
    }
})
$summary = @{
    stamp = [string]$stamp
    rounds_requested = [int]$Rounds
    rounds_run = [int]$roundResults.Count
    rounds_passed = [int]$passed
    rounds_failed = [int]$failed
    parallel = [int]$Parallel
    precise = [bool]$Precise
    also_agent_hello = [bool]$AlsoAgentHello
    stop_on_first_fail = [bool]$StopOnFirstFail
    total_ms = [int]$swAll.ElapsedMilliseconds
    log = [string]$logPath
    rounds = $roundArr
}
($summary | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ''
Write-Host ("SOAK RESULT: {0}/{1} rounds passed (failed={2}) total_ms={3}" -f $passed, $Rounds, $failed, $swAll.ElapsedMilliseconds) `
    -ForegroundColor $(if ($failed -eq 0 -and $passed -eq $Rounds) { 'Green' } else { 'Red' })
Write-Host ("summary: {0}" -f $summaryPath) -ForegroundColor DarkGray
Write-Host ("log: {0}" -f $logPath) -ForegroundColor DarkGray

if ($failed -eq 0 -and $passed -eq $Rounds) { exit 0 }
exit 1
