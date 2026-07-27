#Requires -Version 5.1
# test-harder-live-deferred-slot.ps1
# HARDER than test-multi-agent-deferred-slot-live.ps1:
# - Parent calls real Enter-ConnectSingleInstance from connect-ui.ps1 (full dot-source)
# - Free-slot probes run in a SEPARATE process (Start-Process helper -> count file) so the
#   parent thread's named-mutex recursion cannot inflate the free count while it holds a slot
# - DeferredServerSetupOnly child mirrors connect.ps1 gate; external probe must stay flat
# - Contrast non-deferred child must drop free count by 1 (external probe)
# - Static connect.ps1 ordering: if Deferred then elseif Enter
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARDER LIVE: deferred setup must not steal UI slot (external probe) ===' -ForegroundColor White

$uiPath = Get-ClientFile 'connect-ui.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$uiSrc = Get-Content -LiteralPath $uiPath -Raw
$winSrc = Get-Content -LiteralPath $winPath -Raw

Assert ($winSrc -match 'deferred_setup_skip_mutex') 'static: deferred_setup_skip_mutex present'
Assert ($winSrc -match '(?s)if \(\$DeferredServerSetupOnly\)[\s\S]{0,900}elseif \(-not \(Enter-ConnectSingleInstance\)\)') `
    'static: connect.ps1 if Deferred elseif Enter (Enter gated behind deferred skip)'

$root = Join-Path $env:TEMP ("cc-hard-def-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root

$probeScript = Join-Path $root 'slot-probe.ps1'
$probeBody = @'
param([Parameter(Mandatory)][string]$OutFile)
$ErrorActionPreference = 'Stop'
$free = 0
for ($i = 0; $i -lt 10; $i++) {
    $pm = $null
    try {
        $pm = New-Object System.Threading.Mutex($false, ("Global\ClaudeConnect#{0}" -f $i))
        $got = $false
        try { $got = $pm.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        if ($got) {
            $free++
            try { $pm.ReleaseMutex() } catch { }
        }
    } catch { } finally {
        if ($pm) { try { $pm.Dispose() } catch { } }
    }
}
Set-Content -LiteralPath $OutFile -Value ([string]$free) -Encoding ASCII
'@
Set-Content -LiteralPath $probeScript -Value $probeBody -Encoding UTF8

function Invoke-ExternalFreeSlotProbe {
    param([int]$TimeoutSec = 12)
    $outFile = Join-Path $root ("probe-{0}.txt" -f [guid]::NewGuid().ToString('N').Substring(0, 6))
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$probeScript`"", '-OutFile', "`"$outFile`""
    ) -PassThru -WindowStyle Hidden
    if (-not $p) { return $null }
    $null = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $p.HasExited -or $p.ExitCode -ne 0) { return $null }
    if (-not (Test-Path -LiteralPath $outFile)) { return $null }
    $raw = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    if ($null -eq $raw) { return $null }
    return [int]($raw.Trim())
}

$free0 = Invoke-ExternalFreeSlotProbe
Note ("external probe free before = $(if ($null -eq $free0) { '?' } else { $free0 }) / 10")
if ($null -eq $free0 -or $free0 -lt 2) {
    Write-Host ("SKIPPED: only {0} free slots; need >=2" -f $(if ($null -eq $free0) { '?' } else { $free0 })) -ForegroundColor Yellow
    $Skip++
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

Assert ($null -ne $free0) 'external probe baseline succeeded (>=2 free slots confirmed)'

# Real connect-ui.ps1 Enter/Exit (production bodies, not a re-implementation).
. $uiPath
Assert (
    $null -ne (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue)
) 'dot-sourced real Enter/Exit-ConnectSingleInstance from connect-ui.ps1'

$child = Join-Path $root 'deferred-child.ps1'
$childBody = @'
param([switch]$DeferredServerSetupOnly)
$ErrorActionPreference = 'Stop'
. $env:CC_HARD_UI_PATH
$marker = $env:CC_HARD_MARKER
$holdSec = [int]$env:CC_HARD_HOLD
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

$origSlotEnv = $env:CLAUDE_CONNECT_UI_SLOT
$parentOk = Enter-ConnectSingleInstance
$parentSlot = ($env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
Assert ($parentOk -and ($parentSlot -match '^[0-9]$')) ("parent real Enter-ConnectSingleInstance holds slot ($parentSlot)")

$freeAfterParent = Invoke-ExternalFreeSlotProbe
Note ("external probe free after parent = $freeAfterParent (baseline before parent was $free0)")
Assert ($null -ne $freeAfterParent -and ($freeAfterParent + 1) -eq $free0) `
    ("external probe dropped by 1 after parent (before=$free0 after=$freeAfterParent)")

$marker = Join-Path $root 'child.marker'
$env:CC_HARD_UI_PATH = $uiPath
$env:CC_HARD_MARKER = $marker
$env:CC_HARD_HOLD = '5'
$env:CLAUDE_CONNECT_UI_SLOT = $parentSlot

try {
    Note 'CaseA: DeferredServerSetupOnly child must skip mutex (external probe flat)'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$child`"", '-DeferredServerSetupOnly'
    ) -PassThru -WindowStyle Hidden
    Assert ($null -ne $p) 'CaseA spawned DeferredServerSetupOnly child process'

    $deadline = [datetime]::UtcNow.AddSeconds(8)
    while ([datetime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $marker)) {
        Start-Sleep -Milliseconds 80
    }
    $txt = if (Test-Path -LiteralPath $marker) { (Get-Content -LiteralPath $marker -Raw).Trim() } else { '' }
    Assert ($txt -match 'deferred_setup_skip_mutex') 'CaseA marker has deferred_setup_skip_mutex'
    Assert ($txt -match ("inherit_slot=$parentSlot")) ("CaseA inherit_slot=$parentSlot in marker")

    Start-Sleep -Milliseconds 400
    $freeDuring = Invoke-ExternalFreeSlotProbe
    Note ("external probe free while deferred child runs = $freeDuring (expect $freeAfterParent)")
    Assert ($null -ne $freeDuring -and $freeDuring -eq $freeAfterParent) `
        ("CaseA external free unchanged during deferred child (parent=$freeAfterParent during=$freeDuring); no 2nd slot stolen")

    $null = $p.WaitForExit(15000)
    Assert ($p.ExitCode -eq 0) ("CaseA deferred child exit=0 (got $($p.ExitCode))")

    Note 'CaseB: contrast — non-deferred child DOES take a second slot (external probe -1)'
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $p2 = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$child`""
    ) -PassThru -WindowStyle Hidden
    $deadline2 = [datetime]::UtcNow.AddSeconds(8)
    while ([datetime]::UtcNow -lt $deadline2 -and -not (Test-Path -LiteralPath $marker)) {
        Start-Sleep -Milliseconds 80
    }
    $txt2 = if (Test-Path -LiteralPath $marker) { (Get-Content -LiteralPath $marker -Raw).Trim() } else { '' }
    Assert ($txt2 -match 'acquired slot=') 'CaseB contrast child acquired a slot'
    $m2 = [regex]::Match($txt2, 'acquired slot=(\d+)')
    if ($m2.Success) {
        Assert ($m2.Groups[1].Value -ne $parentSlot) ("CaseB contrast slot != parent ($($m2.Groups[1].Value) vs $parentSlot)")
    }
    Start-Sleep -Milliseconds 300
    $freeContrast = Invoke-ExternalFreeSlotProbe
    Note ("external probe free while contrast child runs = $freeContrast (expect < $freeAfterParent)")
    Assert ($null -ne $freeContrast -and $freeContrast -lt $freeAfterParent) `
        ("CaseB external free dropped when non-deferred child acquires (parent=$freeAfterParent contrast=$freeContrast)")
    $null = $p2.WaitForExit(15000)

} catch {
    Write-Host ("  FAIL  exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    try { Exit-ConnectSingleInstance } catch { }
    if ($origSlotEnv) { $env:CLAUDE_CONNECT_UI_SLOT = $origSlotEnv } else { Remove-Item Env:CLAUDE_CONNECT_UI_SLOT -ErrorAction SilentlyContinue }
    Remove-Item Env:CC_HARD_UI_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:CC_HARD_MARKER -ErrorAction SilentlyContinue
    Remove-Item Env:CC_HARD_HOLD -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARDER deferred-slot RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("HARDER deferred-slot RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
