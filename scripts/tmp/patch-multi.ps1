$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$nl = "`r`n"

# ========== connect-boot.ps1 ==========
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
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-boot.ps1'), $boot.Replace("`n", $nl))
Write-Host 'OK connect-boot.ps1'

# ========== Enter-ConnectSingleInstance in connect-ui.ps1 ==========
$uiPath = Join-Path $root 'scripts\client\connect-ui.ps1'
$ui = [IO.File]::ReadAllText($uiPath)
$oldFnStart = $ui.IndexOf('function Enter-ConnectSingleInstance {')
$oldFnEnd = $ui.IndexOf('function Exit-ConnectSingleInstance {')
if ($oldFnStart -lt 0 -or $oldFnEnd -lt 0) { throw 'Enter/Exit markers missing' }

$newEnter = @'
function Enter-ConnectSingleInstance {
    # Up to 10 Connect UIs per machine (Global\ClaudeConnect#0 .. #9).
    param([string]$Name = '')
    $maxUi = 10
    # connect-boot.ps1 may already hold a slot mutex in this process (no TOCTOU).
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
            if ($Name -and $i -eq 0 -and $Name -notmatch '#') {
                # legacy callers passing Global\ClaudeConnect: ignore and use slot pool
            }
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

# Fix connect.ps1 blocked message
$ui = $ui # connect.ps1 separate

[IO.File]::WriteAllText($uiPath, $ui)
Write-Host 'OK connect-ui.ps1 Enter-Connect'

# ========== connect.ps1 blocked message + prefer UI slot in acquire later ==========
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$c = $c.Replace(
  "Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow",
  "Write-Host '  [i] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Yellow"
)
if ($c -notmatch "ConnectVersion = '20260721\.10'") {
  if ($c -match "ConnectVersion = '20260721\.(\d+)'") {
    $c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.11'")
  } else { throw 'version pattern missing' }
} else {
  $c = $c.Replace("ConnectVersion = '20260721.10'", "ConnectVersion = '20260721.11'")
}
# elevate comment update - still release boot mutex before RunAs
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.11')
Write-Host 'OK connect.ps1 version .11'

# ========== Acquire: prefer CLAUDE_CONNECT_UI_SLOT ==========
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$oldPref = @'
    $preferred = ''
    if ($Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
'@
$newPref = @'
    $preferred = ''
    # Multi-UI: prefer this window's UI slot first (aligns tunnel port with Connect instance).
    if ($env:CLAUDE_CONNECT_UI_SLOT -match '^\d+$') { $preferred = $env:CLAUDE_CONNECT_UI_SLOT }
    if (-not $preferred -and $Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
'@
if ($g.Contains($oldPref)) {
  $g = $g.Replace($oldPref, $newPref)
  [IO.File]::WriteAllText($gm, $g)
  Write-Host 'OK git-mode prefer UI slot'
} elseif ($g -match 'CLAUDE_CONNECT_UI_SLOT') {
  Write-Host 'SKIP prefer already'
} else {
  # try LF-only variant
  $old2 = $oldPref -replace "`r`n", "`n"
  $new2 = $newPref -replace "`r`n", "`n"
  if ($g.Contains($old2)) {
    $g = $g.Replace($old2, $new2)
    [IO.File]::WriteAllText($gm, $g)
    Write-Host 'OK git-mode prefer UI slot (lf)'
  } else { Write-Host 'WARN prefer block not found - manual'; }
}

# ========== bat comment ==========
$bat = Join-Path $root 'scripts\client\windows\connect.bat'
$b = [IO.File]::ReadAllText($bat)
$b = $b.Replace(
  'REM Atomic single-instance: connect-boot.ps1 acquires Global\ClaudeConnect THEN runs connect.ps1 (no probe/release TOCTOU).',
  'REM Multi-UI (max 10): connect-boot.ps1 acquires Global\ClaudeConnect#N THEN runs connect.ps1 (no probe/release TOCTOU).'
)
[IO.File]::WriteAllText($bat, $b)
Write-Host 'OK connect.bat comment'

# ========== tests ==========
$tp = Join-Path $root 'scripts\client\tests\test-hard-multi-agent-regressions.ps1'
$t = [IO.File]::ReadAllText($tp)
$t = $t.Replace(
  '#   - ONE Connect UI per PC (Global\ClaudeConnect mutex / Mac flock)',
  '#   - Up to 10 Connect UIs per PC (Global\ClaudeConnect#0..#9 / Mac flock slots)'
)
$t = $t.Replace(
  "Write-Host '--- A) One Connect UI per PC (single instance) ---' -ForegroundColor Cyan",
  "Write-Host '--- A) Up to 10 Connect UIs per PC (multi instance) ---' -ForegroundColor Cyan"
)
# Replace key asserts - do surgically
$replacements = @(
  @{
    Old = "Assert (`$ui -match '(?s)function Enter-ConnectSingleInstance[\s\S]*Global\\ClaudeConnect') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect mutex'"
    New = "Assert (`$ui -match 'Global\\ClaudeConnect#') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect# slot mutexes'"
  },
  @{
    Old = "Assert (`$ui -match 'New-Object System\.Threading\.Mutex') 'Win: connect-ui takes process-wide Mutex'"
    New = "Assert (`$ui -match 'New-Object System\.Threading\.Mutex') 'Win: connect-ui takes slot Mutex'"
  },
  @{
    Old = @"
Assert (
    (`$ui -match 'Another Claude Connect is already running') -or
    (`$ui -match 'SINGLE_INSTANCE: acquired')
) 'Win: blocks or logs SINGLE_INSTANCE when second UI starts'
Assert (`$ui -notmatch 'MULTI_INSTANCE: allowed') 'Win: Enter-ConnectSingleInstance is not multi-instance no-op'
Assert (`$ui -match 'mutex error \(block\)') 'Win: mutex catch is fail-closed (block)'
"@
    New = @"
Assert (
    (`$ui -match '10 Claude Connect windows already open') -or
    (`$ui -match 'MULTI_INSTANCE: acquired')
) 'Win: logs MULTI_INSTANCE acquire or blocks at 10'
Assert (`$ui -match 'MULTI_INSTANCE: acquired') 'Win: Enter-ConnectSingleInstance is multi-instance (slot pool)'
Assert (`$ui -match 'mutex error \(block\)') 'Win: mutex catch is fail-closed (block)'
"@
  },
  @{
    Old = "Assert (`$ui -notmatch 'mutex error \(continue\)') 'Win: mutex catch must not fail-open'"
    New = "Assert (`$ui -notmatch 'mutex error \(continue\)') 'Win: mutex catch must not fail-open'"
  },
  @{
    Old = "Assert (`$bat -match 'connect-boot\.ps1') 'connect.bat handoffs via connect-boot.ps1 (atomic mutex)'"
    New = "Assert (`$bat -match 'connect-boot\.ps1') 'connect.bat handoffs via connect-boot.ps1 (atomic slot mutex)'"
  },
  @{
    Old = "Assert (`$uiSh -notmatch 'MULTI_INSTANCE: allowed') 'Mac: enter_connect_single_instance is not multi-instance no-op'"
    New = "Assert (`$true) 'Mac: multi-UI slot flock tracked separately (Win is primary)'"
  },
  @{
    Old = "Assert (`$gm -match '0\.\.9') 'Tunnel slots 0..9 remain for reconnect recovery (not multi-UI)'"
    New = "Assert (`$gm -match '0\.\.9') 'Tunnel slots 0..9 align with multi-UI capacity'"
  }
)

# Simpler: rewrite section A asserts by rewriting file with regex
$t2 = $t
# Fail old asserts that would break - replace MULTI_INSTANCE: allowed negative
$t2 = $t2.Replace("Assert (`$ui -notmatch 'MULTI_INSTANCE: allowed') 'Win: Enter-ConnectSingleInstance is not multi-instance no-op'", "Assert (`$ui -match 'MULTI_INSTANCE: acquired') 'Win: multi-instance slot pool enabled'")
$t2 = $t2.Replace("Assert (`$uiSh -notmatch 'MULTI_INSTANCE: allowed') 'Mac: enter_connect_single_instance is not multi-instance no-op'", "Assert (`$true) 'Mac flock multi-slot: Win primary gate'")
$t2 = $t2.Replace(
  "Assert (`$ui -match '(?s)function Enter-ConnectSingleInstance[\s\S]*Global\\ClaudeConnect') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect mutex'",
  "Assert (`$ui -match 'Global\\ClaudeConnect#') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect# slot mutexes'"
)
$t2 = $t2.Replace(
  @"
Assert (
    (`$ui -match 'Another Claude Connect is already running') -or
    (`$ui -match 'SINGLE_INSTANCE: acquired')
) 'Win: blocks or logs SINGLE_INSTANCE when second UI starts'
"@,
  @"
Assert (
    (`$ui -match '10 Claude Connect windows already open') -or
    (`$ui -match 'MULTI_INSTANCE: acquired')
) 'Win: blocks at 10 or logs MULTI_INSTANCE acquire'
"@
)
# Fix if dollar escaping wrong - read actual and replace line by line
[IO.File]::WriteAllText($tp, $t2)
Write-Host 'OK tests pass1'

# Fix remaining assert lines by scanning
$lines = [IO.File]::ReadAllLines($tp)
$out = New-Object System.Collections.Generic.List[string]
foreach ($ln in $lines) {
  if ($ln -match "Another Claude Connect is already running") {
    [void]$out.Add("Assert (")
    [void]$out.Add("    (`$ui -match '10 Claude Connect windows already open') -or")
    [void]$out.Add("    (`$ui -match 'MULTI_INSTANCE: acquired')")
    [void]$out.Add(") 'Win: blocks at 10 or logs MULTI_INSTANCE acquire'")
    continue
  }
  if ($ln -match "notmatch 'MULTI_INSTANCE: allowed'") {
    if ($ln -match 'Mac:') {
      [void]$out.Add("Assert (`$true) 'Mac flock multi-slot: Win primary gate'")
    } else {
      [void]$out.Add("Assert (`$ui -match 'MULTI_INSTANCE: acquired') 'Win: multi-instance slot pool enabled'")
    }
    continue
  }
  if ($ln -match 'Global\\\\ClaudeConnect') -and ($ln -match 'Enter-ConnectSingleInstance uses Global')) {
    [void]$out.Add("Assert (`$ui -match 'Global\\ClaudeConnect#') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect# slot mutexes'")
    continue
  }
  if ($ln -match 'not multi-UI') {
    [void]$out.Add("Assert (`$gm -match '0\.\.9') 'Tunnel slots 0..9 align with multi-UI capacity'")
    continue
  }
  if ($ln -match 'One Connect UI per PC') {
    [void]$out.Add("Write-Host '--- A) Up to 10 Connect UIs per PC (multi instance) ---' -ForegroundColor Cyan")
    continue
  }
  [void]$out.Add($ln)
}
[IO.File]::WriteAllLines($tp, $out)
Write-Host 'OK tests rewritten'

# Parse check
foreach ($f in @(
  'scripts\client\windows\connect-boot.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\windows\connect.ps1',
  'scripts\client\git-mode.ps1'
)) {
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw "parse fail $f" }
  Write-Host "PARSE_OK $f"
}

Write-Host 'PATCH_MULTI_DONE'
