#Requires -Version 5.1
# test-multi-agent-deferred-slot-live.ps1
# MULTI-AGENT LIVE: DeferredServerSetupOnly child must NOT consume a second
# Global\ClaudeConnect# slot while parent holds one (would cut 10-UI capacity ~in half).
# Mirrors the real gate ordering from connect.ps1 using extracted Enter/Exit helpers.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== MULTI-AGENT LIVE: deferred setup must not steal UI slot ===' -ForegroundColor White

$uiPath = Get-ClientFile 'connect-ui.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$uiSrc = Get-Content -LiteralPath $uiPath -Raw
$winSrc = Get-Content -LiteralPath $winPath -Raw
Assert ($winSrc -match 'deferred_setup_skip_mutex') 'static: deferred_setup_skip_mutex present'
Assert ($winSrc -match '(?s)if \(\$DeferredServerSetupOnly\)[\s\S]{0,900}elseif \(-not \(Enter-ConnectSingleInstance\)\)') `
    'static: Enter gated behind DeferredServerSetupOnly'

$enterSrc = Get-FunctionSource -Content $uiSrc -Name 'Enter-ConnectSingleInstance'
$exitSrc = Get-FunctionSource -Content $uiSrc -Name 'Exit-ConnectSingleInstance'
Assert ($null -ne $enterSrc -and $null -ne $exitSrc) 'extracted Enter/Exit-ConnectSingleInstance'
if (-not $enterSrc) { exit 1 }

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
Note ("probe free before = $free0 / 10")
if ($free0 -lt 2) {
    Write-Host ("SKIPPED: only {0} free slots; need >=2" -f $free0) -ForegroundColor Yellow
    $Skip++
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

$root = Join-Path $env:TEMP ("cc-ma-def-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
$helpers = Join-Path $root 'helpers.ps1'
Set-Content -LiteralPath $helpers -Value ($enterSrc + "`r`n" + $exitSrc) -Encoding UTF8

# Child mirrors connect.ps1 gate: DeferredServerSetupOnly => skip Enter; else Enter.
$child = Join-Path $root 'deferred-child.ps1'
$childBody = @'
param([switch]$DeferredServerSetupOnly)
$ErrorActionPreference = 'Stop'
. $env:CC_MA_HELPERS
$marker = $env:CC_MA_MARKER
$holdSec = [int]$env:CC_MA_HOLD
if ($DeferredServerSetupOnly) {
    $line = 'MULTI_INSTANCE: deferred_setup_skip_mutex pid={0} inherit_slot={1}' -f $PID, ($env:CLAUDE_CONNECT_UI_SLOT + '')
    Set-Content -LiteralPath $marker -Value $line -Encoding ASCII
    Start-Sleep -Seconds $holdSec
    exit 0
}
if (-not (Enter-ConnectSingleInstance)) {
    Set-Content -LiteralPath $marker -Value 'blocked' -Encoding ASCII
    exit 2
}
Set-Content -LiteralPath $marker -Value ('acquired slot={0}' -f $env:CLAUDE_CONNECT_UI_SLOT) -Encoding ASCII
Start-Sleep -Seconds $holdSec
Exit-ConnectSingleInstance
exit 0
'@
Set-Content -LiteralPath $child -Value $childBody -Encoding UTF8

# Parent takes a real slot (same process) then spawns deferred child.
. ([scriptblock]::Create((Get-Content -LiteralPath $helpers -Raw)))
$parentOk = Enter-ConnectSingleInstance
Assert $parentOk 'parent Enter-ConnectSingleInstance succeeded'
$parentSlot = ($env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
Assert ($parentSlot -match '^[0-9]$') ("parent holds slot ($parentSlot)")
$freeAfterParent = Get-FreeConnectSlotCount
Note ("free after parent = $freeAfterParent (was $free0)")

$marker = Join-Path $root 'child.marker'
$env:CC_MA_HELPERS = $helpers
$env:CC_MA_MARKER = $marker
$env:CC_MA_HOLD = '5'
# Inherit parent slot into child env (real Start-DeferredServerSetup preserves this).
$env:CLAUDE_CONNECT_UI_SLOT = $parentSlot

try {
    Note 'CaseA: DeferredServerSetupOnly child must skip mutex'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$child`"", '-DeferredServerSetupOnly'
    ) -PassThru -WindowStyle Hidden
    Assert ($null -ne $p) 'spawned deferred child process'

    $deadline = [datetime]::UtcNow.AddSeconds(8)
    while ([datetime]::UtcNow -lt $deadline -and -not (Test-Path $marker)) { Start-Sleep -Milliseconds 80 }
    Assert (Test-Path $marker) 'CaseA child wrote marker'
    $txt = (Get-Content -LiteralPath $marker -Raw).Trim()
    Assert ($txt -match 'deferred_setup_skip_mutex') 'CaseA marker has deferred_setup_skip_mutex'
    Assert ($txt -match ("inherit_slot=$parentSlot")) ("CaseA inherit_slot=$parentSlot in marker")

    Start-Sleep -Milliseconds 400
    $freeDuring = Get-FreeConnectSlotCount
    Note ("free while deferred child runs = $freeDuring")
    Assert ($freeDuring -eq $freeAfterParent) `
        ("CaseA free slots unchanged during deferred child (parent=$freeAfterParent during=$freeDuring); no 2nd slot stolen")

    $null = $p.WaitForExit(15000)
    Assert ($p.ExitCode -eq 0) ("CaseA deferred child exit=0 (got $($p.ExitCode))")

    # Contrast: non-deferred child WOULD take another slot
    Note 'CaseB: contrast — non-deferred child DOES take a second slot'
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $p2 = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$child`""
    ) -PassThru -WindowStyle Hidden
    $deadline2 = [datetime]::UtcNow.AddSeconds(8)
    while ([datetime]::UtcNow -lt $deadline2 -and -not (Test-Path $marker)) { Start-Sleep -Milliseconds 80 }
    Assert (Test-Path $marker) 'CaseB contrast child wrote marker'
    $txt2 = (Get-Content -LiteralPath $marker -Raw).Trim()
    Assert ($txt2 -match 'acquired slot=') 'CaseB contrast child acquired a slot'
    $m2 = [regex]::Match($txt2, 'acquired slot=(\d+)')
    if ($m2.Success) {
        Assert ($m2.Groups[1].Value -ne $parentSlot) ("CaseB contrast slot != parent ($($m2.Groups[1].Value) vs $parentSlot)")
    }
    Start-Sleep -Milliseconds 300
    $freeContrast = Get-FreeConnectSlotCount
    Note ("free while contrast child runs = $freeContrast")
    Assert ($freeContrast -lt $freeAfterParent) `
        ("CaseB free slots dropped when non-deferred child acquires (parent=$freeAfterParent contrast=$freeContrast)")
    $null = $p2.WaitForExit(15000)

} catch {
    Write-Host ("  FAIL  exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    try { Exit-ConnectSingleInstance } catch {}
    Remove-Item Env:CC_MA_HELPERS -ErrorAction SilentlyContinue
    Remove-Item Env:CC_MA_MARKER -ErrorAction SilentlyContinue
    Remove-Item Env:CC_MA_HOLD -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("MULTI-AGENT deferred-slot RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("MULTI-AGENT deferred-slot RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
