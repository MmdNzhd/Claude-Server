$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$nl = "`r`n"

# Check if boot already patched
$bootPath = Join-Path $root 'scripts\client\windows\connect-boot.ps1'
$bootNow = [IO.File]::ReadAllText($bootPath)
if ($bootNow -notmatch 'ClaudeConnect#') {
$boot = @'
#Requires -Version 5.1
# connect-boot.ps1 - acquire one of Global\ClaudeConnect#0..#9 THEN run connect.ps1.
# Up to 10 Connect UIs per PC. Abandoned mutex frees a dead slot automatically.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$maxUi = 10

function Test-AcquireConnectUiSlot {
    param([int]$Max = 10)
    for ($i = 0; $i -lt $Max; $i++) {
        $name = "Global\ClaudeConnect#$i"
        $created = $false
        $cand = $null
        try {
            $cand = New-Object System.Threading.Mutex($false, $name, [ref]$created)
        } catch {
            continue
        }
        $got = $false
        try {
            try { $got = $cand.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        } catch {
            try { $cand.Dispose() } catch { }
            continue
        }
        if ($got) {
            return @{ Mutex = $cand; Slot = $i; Name = $name }
        }
        try { $cand.Dispose() } catch { }
    }
    return $null
}

$acq = Test-AcquireConnectUiSlot -Max $maxUi
if (-not $acq) {
    Write-Host ''
    Write-Host '  [i] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

$m = $acq.Mutex
$slot = [int]$acq.Slot
$global:ClaudeConnectBootMutex = $m
$env:CLAUDE_CONNECT_BOOT_MUTEX = '1'
$env:CLAUDE_CONNECT_UI_SLOT = [string]$slot

$connectPs1 = Join-Path $here 'connect.ps1'
if (-not (Test-Path -LiteralPath $connectPs1)) {
    try { $m.ReleaseMutex() } catch { }
    try { $m.Dispose() } catch { }
    Write-Host ''
    Write-Host '  [X] connect.ps1 missing next to connect-boot.ps1.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

try {
    & $connectPs1 @args
    $ec = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
} catch {
    $ec = 1
    Write-Host ("  [X] connect.ps1 failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($global:ClaudeConnectBootMutex) {
        try { $global:ClaudeConnectBootMutex.ReleaseMutex() } catch { }
        try { $global:ClaudeConnectBootMutex.Dispose() } catch { }
        $global:ClaudeConnectBootMutex = $null
    }
    $env:CLAUDE_CONNECT_BOOT_MUTEX = $null
}
exit $ec
'@
  [IO.File]::WriteAllText($bootPath, ($boot -replace "`n", $nl))
  Write-Host 'OK connect-boot'
} else { Write-Host 'SKIP boot already' }

# connect-ui Enter function
$uiPath = Join-Path $root 'scripts\client\connect-ui.ps1'
$ui = [IO.File]::ReadAllText($uiPath)
if ($ui -notmatch 'MULTI_INSTANCE: acquired') {
  $oldFnStart = $ui.IndexOf('function Enter-ConnectSingleInstance {')
  $oldFnEnd = $ui.IndexOf('function Exit-ConnectSingleInstance {')
  if ($oldFnStart -lt 0 -or $oldFnEnd -lt 0) { throw 'Enter/Exit markers missing' }
  $newEnter = @'
function Enter-ConnectSingleInstance {
    # Up to 10 Connect UIs per machine (Global\ClaudeConnect#0 .. #9).
    param([string]$Name = '')
    $maxUi = 10
    if ($env:CLAUDE_CONNECT_BOOT_MUTEX -eq '1' -and $global:ClaudeConnectBootMutex) {
        $script:ConnectInstanceMutex = $global:ClaudeConnectBootMutex
        $global:ClaudeConnectBootMutex = $null
        $slot = ($env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("MULTI_INSTANCE: acquired pid={0} via=connect-boot slot={1}" -f $PID, $slot) 'INFO'
        }
        return $true
    }
    $script:ConnectInstanceMutex = $null
    try {
        for ($i = 0; $i -lt $maxUi; $i++) {
            $slotName = "Global\ClaudeConnect#$i"
            $created = $false
            $m = $null
            try {
                $m = New-Object System.Threading.Mutex($false, $slotName, [ref]$created)
            } catch { continue }
            $got = $false
            try {
                try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            } catch {
                try { $m.Dispose() } catch { }
                continue
            }
            if ($got) {
                $script:ConnectInstanceMutex = $m
                $env:CLAUDE_CONNECT_UI_SLOT = [string]$i
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog ("MULTI_INSTANCE: acquired pid={0} slot={1}" -f $PID, $i) 'INFO'
                }
                return $true
            }
            try { $m.Dispose() } catch { }
        }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("MULTI_INSTANCE: blocked pid={0} reason=all_slots_busy max={1}" -f $PID, $maxUi) 'ERROR'
        }
        Write-Host ''
        Write-Host '  [X] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Red
        Write-Host ''
        return $false
    } catch {
        $script:ConnectInstanceMutex = $null
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("MULTI_INSTANCE: mutex error (block): {0}" -f $_.Exception.Message) 'ERROR'
        }
        Write-Host ''
        Write-Host '  [X] Could not acquire Connect lock - close other Claude Connect windows.' -ForegroundColor Red
        Write-Host ''
        return $false
    }
}

'@
  if ($ui.Contains("`r`n")) { $newEnter = $newEnter -replace "(?<!\r)\n", "`r`n" }
  $ui = $ui.Remove($oldFnStart, $oldFnEnd - $oldFnStart).Insert($oldFnStart, $newEnter)
  [IO.File]::WriteAllText($uiPath, $ui)
  Write-Host 'OK connect-ui'
} else { Write-Host 'SKIP ui already' }

# connect.ps1 messages + version
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$c = $c.Replace(
  "Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow",
  "Write-Host '  [i] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Yellow"
)
$c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.11'")
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.11')
Write-Host 'OK connect.ps1 .11'

# git-mode prefer UI slot
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
if ($g -notmatch 'CLAUDE_CONNECT_UI_SLOT') {
  $needle = '    $preferred = '''''
  # find Acquire preferred block
  $idx = $g.IndexOf("function Acquire-TunnelPort")
  $chunkStart = $g.IndexOf('$preferred = ', $idx)
  $chunk = $g.Substring($chunkStart, 350)
  Write-Host "PREF_CHUNK=$chunk"
  $old = @'
    $preferred = ''
    if ($Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
'@
  $new = @'
    $preferred = ''
    if ($env:CLAUDE_CONNECT_UI_SLOT -match '^\d+$') { $preferred = $env:CLAUDE_CONNECT_UI_SLOT }
    if (-not $preferred -and $Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
'@
  $ok = $false
  foreach ($pair in @(@($old,$new), @(($old -replace "`r`n","`n"), ($new -replace "`r`n","`n")))) {
    if ($g.Contains($pair[0])) { $g = $g.Replace($pair[0], $pair[1]); $ok = $true; break }
  }
  if (-not $ok) { throw 'prefer block not found' }
  [IO.File]::WriteAllText($gm, $g)
  Write-Host 'OK git-mode prefer'
} else { Write-Host 'SKIP git-mode prefer' }

# bat
$bat = Join-Path $root 'scripts\client\windows\connect.bat'
$b = [IO.File]::ReadAllText($bat)
$b = $b.Replace(
  'REM Atomic single-instance: connect-boot.ps1 acquires Global\ClaudeConnect THEN runs connect.ps1 (no probe/release TOCTOU).',
  'REM Multi-UI (max 10): connect-boot.ps1 acquires Global\ClaudeConnect#N THEN runs connect.ps1 (no probe/release TOCTOU).'
)
[IO.File]::WriteAllText($bat, $b)

# Rewrite hard multi-agent test section A with a clean block
$tp = Join-Path $root 'scripts\client\tests\test-hard-multi-agent-regressions.ps1'
$t = [IO.File]::ReadAllText($tp)
# Replace from "--- A)" through designer mac assert before "--- B)"
$aStart = $t.IndexOf("Write-Host '--- A)")
if ($aStart -lt 0) { $aStart = $t.IndexOf('Write-Host "--- A)') }
$bStart = $t.IndexOf("Write-Host '--- B)")
if ($aStart -lt 0 -or $bStart -lt 0) { throw "section markers a=$aStart b=$bStart" }
$newA = @'
Write-Host '--- A) Up to 10 Connect UIs per PC (multi instance) ---' -ForegroundColor Cyan
Assert ($ui -match 'Global\\ClaudeConnect#') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect# slot mutexes'
Assert ($ui -match 'New-Object System\.Threading\.Mutex') 'Win: connect-ui takes slot Mutex'
Assert (
    ($ui -match '10 Claude Connect windows already open') -or
    ($ui -match 'MULTI_INSTANCE: acquired')
) 'Win: blocks at 10 or logs MULTI_INSTANCE acquire'
Assert ($ui -match 'MULTI_INSTANCE: acquired') 'Win: multi-instance slot pool enabled'
Assert ($ui -match 'mutex error \(block\)') 'Win: mutex catch is fail-closed (block)'
Assert ($ui -notmatch 'mutex error \(continue\)') 'Win: mutex catch must not fail-open'
Assert ($gm -match 'no result line') 'git-mode: pushLine null-safe fallback'
Assert ($bat -match 'connect-boot\.ps1') 'connect.bat handoffs via connect-boot.ps1 (atomic slot mutex)'
Assert ($bat -notmatch 'ReleaseMutex') 'connect.bat must not probe/release mutex (TOCTOU)'
Assert ($win -match 'ReleaseMutex' -and $win -match 'CLAUDE_CONNECT_BOOT_MUTEX' -and $win -match "connect-boot\.ps1") 'connect.ps1 releases boot mutex and elevates via connect-boot before UAC'

Assert (Test-Path (Join-Path $Client 'windows\connect-boot.ps1')) 'connect-boot.ps1 exists'
Assert ((Get-Content (Join-Path $Client 'windows\connect-boot.ps1') -Raw) -match 'ClaudeConnect#') 'connect-boot acquires ClaudeConnect# slot pool'
Assert ((Get-Content (Join-Path $Client '..\..\publish\deploy-client-bundles.ps1') -Raw) -match "connect-boot\.ps1") 'deploy-client-bundles includes connect-boot.ps1 in WinBundleFiles'
Assert (
    ($uiSh -match 'connect\.lock') -or
    ($uiSh -match 'Another Claude Connect is already running') -or
    ($uiSh -match 'SINGLE_INSTANCE: acquired') -or
    ($uiSh -match 'MULTI_INSTANCE')
) 'Mac: enter_connect_single_instance uses flock or instance message'
Assert ($desPs -match 'Enter-ConnectSingleInstance') 'Designer Win: shares main instance gate'
Assert ($desPs -match '(?s)Enter-ConnectSingleInstance[\s\S]{0,200}-not \(Enter-ConnectSingleInstance\)') 'Designer Win: honors mutex false (exits)'
Assert ($desPs -notmatch '\$null = Enter-ConnectSingleInstance') 'Designer Win: must not discard mutex result'
Assert ($desSh -match 'enter_connect_single_instance') 'Designer Mac: shares main instance gate'
Assert ($gm -match '0\.\.9') 'Tunnel slots 0..9 align with multi-UI capacity'
Assert ($gm -match 'CLAUDE_CONNECT_UI_SLOT') 'git-mode prefers CLAUDE_CONNECT_UI_SLOT for tunnel acquire'

'@
if ($t.Contains("`r`n")) { $newA = $newA -replace "(?<!\r)\n", "`r`n" }
$t = $t.Remove($aStart, $bStart - $aStart).Insert($aStart, $newA)
# header comment
$t = $t.Replace(
  '#   - ONE Connect UI per PC (Global\ClaudeConnect mutex / Mac flock)',
  '#   - Up to 10 Connect UIs per PC (Global\ClaudeConnect#0..#9)'
)
[IO.File]::WriteAllText($tp, $t)
Write-Host 'OK tests'

# session-log-contracts may still want SINGLE_INSTANCE|Global\ClaudeConnect - # still matches ClaudeConnect
# parse
foreach ($f in @(
  'scripts\client\windows\connect-boot.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\windows\connect.ps1',
  'scripts\client\git-mode.ps1'
)) {
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw "parse fail $f" }
  "PARSE_OK $f"
}

# Quick unit: can acquire 2 slots
$m1=$null;$m2=$null
$c1=$false;$c2=$false
$m1 = New-Object System.Threading.Mutex($false,'Global\ClaudeConnect#0',[ref]$c1)
$g1=$false; try{$g1=$m1.WaitOne(0)}catch [System.Threading.AbandonedMutexException]{$g1=$true}
$m2 = New-Object System.Threading.Mutex($false,'Global\ClaudeConnect#1',[ref]$c2)
$g2=$false; try{$g2=$m2.WaitOne(0)}catch [System.Threading.AbandonedMutexException]{$g2=$true}
Write-Host "SLOT_TEST g1=$g1 g2=$g2"
if ($g1) { $m1.ReleaseMutex() }; $m1.Dispose()
if ($g2) { $m2.ReleaseMutex() }; $m2.Dispose()

Write-Host 'PATCH_MULTI_DONE'
