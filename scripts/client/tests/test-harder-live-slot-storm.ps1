#Requires -Version 5.1
# test-harder-live-slot-storm.ps1
# HARD LIVE: Global\ClaudeConnect# multi-process slot storm via the REAL
# Test-AcquireConnectUiSlot from connect-boot.ps1 (Get-FunctionSource / _paths.ps1).
# Probes free slots first; skips honestly if <4 free. Spawns 4 separate powershell.exe
# processes that acquire+hold 6s, then a 5th while four are still held. Never drains
# the production pool permanently — workers release in finally; parent kills stragglers.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: Global\ClaudeConnect# multi-process slot storm ===' -ForegroundColor White

$bootPath = Get-ClientFile 'windows\connect-boot.ps1'
$bootSrc = Get-Content -LiteralPath $bootPath -Raw
$acqFn = Get-FunctionSource -Content $bootSrc -Name 'Test-AcquireConnectUiSlot'
Assert ($null -ne $acqFn) 'extracted Test-AcquireConnectUiSlot from connect-boot.ps1 via Get-FunctionSource'
if (-not $acqFn) { exit 1 }

function Get-FreeConnectSlotCount {
    $free = 0
    for ($i = 0; $i -lt 10; $i++) {
        $pm = $null
        try {
            $pm = New-Object System.Threading.Mutex($false, "Global\ClaudeConnect#$i")
            $got = $false
            try { $got = $pm.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            if ($got) { $free++; try { $pm.ReleaseMutex() } catch {} }
        } catch {} finally { if ($pm) { try { $pm.Dispose() } catch {} } }
    }
    return $free
}

$maxUi = 10
$holdSec = 6
$free0 = Get-FreeConnectSlotCount
Note ("probe free slots before = $free0 / $maxUi")

if ($free0 -lt 4) {
    Write-Host ("SKIPPED: only {0} free ClaudeConnect# slots; need >=4 for four-process storm" -f $free0) -ForegroundColor Yellow
    $Skip++
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

$root = Join-Path $env:TEMP ("cc-slot-storm-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
$acqFile = Join-Path $root 'Test-AcquireConnectUiSlot.ps1'
$worker = Join-Path $root 'slot-storm-worker.ps1'
$markerDir = Join-Path $root 'markers'
$null = New-Item -ItemType Directory -Force -Path $markerDir
Set-Content -LiteralPath $acqFile -Value $acqFn -Encoding UTF8

$workerBody = @'
param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$MarkerDir,
    [Parameter(Mandatory)][int]$HoldSec,
    [Parameter(Mandatory)][string]$AcqFile
)
$ErrorActionPreference = 'Stop'
. $AcqFile
$acq = Test-AcquireConnectUiSlot -Max 10
if (-not $acq) {
    Set-Content -LiteralPath (Join-Path $MarkerDir ("{0}.blocked" -f $Id)) -Value 'all_busy' -Encoding ASCII
    exit 3
}
Set-Content -LiteralPath (Join-Path $MarkerDir ("{0}.slot" -f $Id)) -Value ([string]$acq.Slot) -Encoding ASCII
Start-Sleep -Seconds $HoldSec
try { $acq.Mutex.ReleaseMutex() } catch {}
try { $acq.Mutex.Dispose() } catch {}
Set-Content -LiteralPath (Join-Path $MarkerDir ("{0}.done" -f $Id)) -Value 'ok' -Encoding ASCII
exit 0
'@
Set-Content -LiteralPath $worker -Value $workerBody -Encoding UTF8

function Start-SlotWorker([string]$Id, [int]$Hold) {
    return Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$worker`"",
        '-Id', $Id,
        '-MarkerDir', "`"$markerDir`"",
        '-HoldSec', [string]$Hold,
        '-AcqFile', "`"$acqFile`""
    ) -PassThru -WindowStyle Hidden
}

function Wait-ForSlotMarkers([string[]]$Ids, [int]$TimeoutSec) {
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    while ([datetime]::UtcNow -lt $deadline) {
        $have = 0
        foreach ($id in $Ids) {
            if (Test-Path (Join-Path $markerDir ("{0}.slot" -f $id))) { $have++ }
            elseif (Test-Path (Join-Path $markerDir ("{0}.blocked" -f $id))) { $have++ }
        }
        if ($have -ge $Ids.Count) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

$procs = @()
try {
    Note 'PhaseA: spawn 4 separate OS processes — acquire via Test-AcquireConnectUiSlot, hold 6s'
    foreach ($id in @('w1', 'w2', 'w3', 'w4')) {
        $procs += Start-SlotWorker -Id $id -Hold $holdSec
        Start-Sleep -Milliseconds 80
    }
    Assert ($procs.Count -eq 4 -and ($procs | Where-Object { $null -ne $_ }).Count -eq 4) `
        'four separate powershell.exe storm workers spawned'

    $gotMarkers = Wait-ForSlotMarkers -Ids @('w1', 'w2', 'w3', 'w4') -TimeoutSec 12
    Assert $gotMarkers 'four workers wrote acquisition markers within deadline'

    $slotFiles = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.slot' -ErrorAction SilentlyContinue)
    $slotVals = @($slotFiles | ForEach-Object { (Get-Content $_.FullName -Raw).Trim() } | Sort-Object -Unique)
    Assert ($slotFiles.Count -eq 4 -and $slotVals.Count -eq 4) `
        ("four DISTINCT Global\ClaudeConnect# slots held ($($slotVals -join ','))")

    $blockedFirst = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.blocked' -ErrorAction SilentlyContinue)
    Assert ($blockedFirst.Count -eq 0) 'none of the first four storm workers were blocked'

    Start-Sleep -Milliseconds 350
    $freeMid = Get-FreeConnectSlotCount
    Note ("probe free slots while 4 held = $freeMid / $maxUi (baseline=$free0)")
    Assert ($freeMid -le ($free0 - 3)) ("free count dropped by ~4 while four held (before=$free0 mid=$freeMid)")

    Note 'PhaseB: 5th process while four still holding — distinct slot OR blocked'
    $stillHeld = @($procs | Where-Object { -not $_.HasExited })
    Assert ($stillHeld.Count -ge 4) ("four storm workers still running before 5th spawn (running=$($stillHeld.Count))")

    $p5 = Start-SlotWorker -Id 'w5' -Hold 4
    $procs += $p5
    Assert ($null -ne $p5) '5th storm worker spawned while four slots still held'

    $got5 = Wait-ForSlotMarkers -Ids @('w5') -TimeoutSec 8
    Assert $got5 '5th worker wrote slot or blocked marker within deadline'

    $w5SlotPath = Join-Path $markerDir 'w5.slot'
    $w5BlockedPath = Join-Path $markerDir 'w5.blocked'
    $w5GotSlot = Test-Path -LiteralPath $w5SlotPath
    $w5Blocked = Test-Path -LiteralPath $w5BlockedPath

    if ($free0 -ge 5) {
        $slot5 = if ($w5GotSlot) { (Get-Content -LiteralPath $w5SlotPath -Raw).Trim() } else { '' }
        $allFive = @($slotVals + @($slot5) | Where-Object { $_ } | Sort-Object -Unique)
        Assert ($w5GotSlot -and $allFive.Count -eq 5) `
            ("free0=$free0 >=5: 5th worker got distinct slot (all five=$($allFive -join ','))")
    } else {
        Assert ($w5Blocked -and -not $w5GotSlot) `
            ("free0=$free0 was exactly 4: 5th worker blocked when pool exhausted")
    }

    Note 'PhaseC: wait for all workers to release; verify pool restoration'
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) { $null = $p.WaitForExit([Math]::Max(20000, ($holdSec + 8) * 1000)) }
    }
    Start-Sleep -Milliseconds 400

    $exitCodes = @($procs | ForEach-Object { if ($_.HasExited) { $_.ExitCode } })
    Assert (@($exitCodes | Where-Object { $_ -eq 0 -or $_ -eq 3 }).Count -eq 5) `
        ("all five workers exited 0 (acquired) or 3 (blocked) (got: $($exitCodes -join ','))")

    $done = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.done' -ErrorAction SilentlyContinue)
    $expectedDone = if ($free0 -ge 5) { 5 } else { 4 }
    Assert ($done.Count -eq $expectedDone) `
        ("acquired workers released mutex and wrote .done ($($done.Count)/$expectedDone)")

    $freeEnd = Get-FreeConnectSlotCount
    Note ("probe free slots after full release = $freeEnd / $maxUi (baseline=$free0)")
    Assert ($freeEnd -eq $free0) 'free count fully restored to pre-storm baseline after release'

} catch {
    Write-Host ("  FAIL  exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    Start-Sleep -Milliseconds 300
    $freeCleanup = Get-FreeConnectSlotCount
    Note ("finally re-probe free = $freeCleanup / $maxUi (baseline=$free0)")
    if ($free0 -ge 4) {
        Assert ($freeCleanup -eq $free0) 'finally: production slot pool restored (zero net drain)'
    }
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARD LIVE slot-storm RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("HARD LIVE slot-storm RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
