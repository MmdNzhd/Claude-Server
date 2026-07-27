#Requires -Version 5.1
# test-multi-agent-boot-slots-live.ps1
# MULTI-AGENT LIVE: separate OS processes acquire distinct Global\ClaudeConnect# slots
# via the REAL Test-AcquireConnectUiSlot from connect-boot.ps1 (not same-thread runspace).
# Probes free slots first; skips if <3 free (never drains production Connect pool).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== MULTI-AGENT LIVE: connect-boot slot acquire (separate processes) ===' -ForegroundColor White

$bootPath = Get-ClientFile 'windows\connect-boot.ps1'
$bootSrc = Get-Content -LiteralPath $bootPath -Raw
$acqFn = Get-FunctionSource -Content $bootSrc -Name 'Test-AcquireConnectUiSlot'
Assert ($null -ne $acqFn) 'extracted Test-AcquireConnectUiSlot from connect-boot.ps1'
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

$free0 = Get-FreeConnectSlotCount
Note ("probe free slots before = $free0 / 10")
if ($free0 -lt 3) {
    Write-Host ("SKIPPED: only {0} free ClaudeConnect# slots; need >=3 for dual-process proof" -f $free0) -ForegroundColor Yellow
    $Skip++
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

$root = Join-Path $env:TEMP ("cc-ma-boot-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
$acqFile = Join-Path $root 'Test-AcquireConnectUiSlot.ps1'
$worker = Join-Path $root 'slot-worker.ps1'
$markerDir = Join-Path $root 'markers'
$null = New-Item -ItemType Directory -Force -Path $markerDir
Set-Content -LiteralPath $acqFile -Value $acqFn -Encoding UTF8

$workerBody = @'
$ErrorActionPreference = 'Stop'
. $args[3]
$id = $args[0]
$markerDir = $args[1]
$holdSec = [int]$args[2]
$acq = Test-AcquireConnectUiSlot -Max 10
if (-not $acq) {
    Set-Content -LiteralPath (Join-Path $markerDir ("{0}.blocked" -f $id)) -Value 'all_busy' -Encoding ASCII
    exit 3
}
Set-Content -LiteralPath (Join-Path $markerDir ("{0}.slot" -f $id)) -Value ([string]$acq.Slot) -Encoding ASCII
Start-Sleep -Seconds $holdSec
try { $acq.Mutex.ReleaseMutex() } catch {}
try { $acq.Mutex.Dispose() } catch {}
Set-Content -LiteralPath (Join-Path $markerDir ("{0}.done" -f $id)) -Value 'ok' -Encoding ASCII
exit 0
'@
Set-Content -LiteralPath $worker -Value $workerBody -Encoding UTF8

$procs = @()
try {
    Note 'CaseA: start 3 parallel OS processes acquiring boot slots'
    foreach ($id in @('a', 'b', 'c')) {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$worker`"", $id, "`"$markerDir`"", '8', "`"$acqFile`""
        ) -PassThru -WindowStyle Hidden
        $procs += $p
        Start-Sleep -Milliseconds 120
    }

    $deadline = [datetime]::UtcNow.AddSeconds(10)
    while ([datetime]::UtcNow -lt $deadline) {
        $slots = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.slot' -ErrorAction SilentlyContinue)
        if ($slots.Count -ge 3) { break }
        Start-Sleep -Milliseconds 100
    }

    $slotFiles = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.slot' -ErrorAction SilentlyContinue)
    Assert ($slotFiles.Count -eq 3) ("CaseA three processes wrote slot markers (got $($slotFiles.Count))")
    $slotVals = @($slotFiles | ForEach-Object { (Get-Content $_.FullName -Raw).Trim() } | Sort-Object -Unique)
    Assert ($slotVals.Count -eq 3) ("CaseA three DISTINCT slots ($($slotVals -join ','))")
    foreach ($s in $slotVals) {
        Assert ($s -match '^[0-9]$') ("CaseA slot value is 0..9 ($s)")
    }

    $blocked = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.blocked' -ErrorAction SilentlyContinue)
    Assert ($blocked.Count -eq 0) 'CaseA none of the 3 were blocked (pool had room)'

    Start-Sleep -Milliseconds 400
    $freeMid = Get-FreeConnectSlotCount
    Note ("probe free slots while held = $freeMid / 10")
    Assert ($freeMid -le ($free0 - 2)) ("CaseA free slots dropped while 3 held (before=$free0 mid=$freeMid)")

    Note 'CaseB: wait for workers to release; slots return'
    foreach ($p in $procs) {
        if (-not $p.HasExited) { $null = $p.WaitForExit(20000) }
    }
    Start-Sleep -Milliseconds 300
    $done = @(Get-ChildItem -LiteralPath $markerDir -Filter '*.done' -ErrorAction SilentlyContinue)
    Assert ($done.Count -eq 3) 'CaseB all 3 workers released cleanly'
    $freeEnd = Get-FreeConnectSlotCount
    Note ("probe free slots after release = $freeEnd / 10")
    Assert ($freeEnd -ge ($free0 - 1)) ("CaseB slots returned after release (before=$free0 after=$freeEnd)")

} catch {
    Write-Host ("  FAIL  exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("MULTI-AGENT boot-slots RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("MULTI-AGENT boot-slots RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
