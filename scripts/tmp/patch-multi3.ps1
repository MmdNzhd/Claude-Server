$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
if ($g -notmatch 'CLAUDE_CONNECT_UI_SLOT') {
  $acq = $g.IndexOf('function Acquire-TunnelPort')
  $pref = $g.IndexOf('$preferred = ''''', $acq)
  if ($pref -lt 0) { throw 'preferred not found' }
  # find end of line after $preferred = ''
  $eol = $g.IndexOf("`n", $pref)
  $insert = '    if ($env:CLAUDE_CONNECT_UI_SLOT -match ''^\d+$'') { $preferred = $env:CLAUDE_CONNECT_UI_SLOT }'
  $nl = if ($g[$eol-1] -eq "`r") { "`r`n" } else { "`n" }
  # Also change next `if ($Cfg` to `if (-not $preferred -and $Cfg`
  $after = $eol + 1
  $g = $g.Insert($after, $insert + $nl)
  # now fix the Cfg condition - find first if ($Cfg after preferred in Acquire
  $acq2 = $g.IndexOf('function Acquire-TunnelPort')
  $cfgIf = $g.IndexOf('if ($Cfg -and (Test-Path $Cfg))', $acq2)
  # only first one after preferred
  $pref2 = $g.IndexOf('CLAUDE_CONNECT_UI_SLOT', $acq2)
  if ($cfgIf -gt $pref2 -and $cfgIf -lt ($pref2 + 200)) {
    $g = $g.Remove($cfgIf, 'if ($Cfg -and (Test-Path $Cfg))'.Length).Insert($cfgIf, 'if (-not $preferred -and $Cfg -and (Test-Path $Cfg))')
  }
  [IO.File]::WriteAllText($gm, $g)
  Write-Host 'OK prefer UI slot'
} else { Write-Host 'SKIP prefer' }

# finish tests if needed
$tp = Join-Path $root 'scripts\client\tests\test-hard-multi-agent-regressions.ps1'
$t = [IO.File]::ReadAllText($tp)
if ($t -notmatch 'Up to 10 Connect UIs') {
  $aStart = $t.IndexOf("Write-Host '--- A)")
  $bStart = $t.IndexOf("Write-Host '--- B)")
  if ($aStart -lt 0 -or $bStart -lt 0) { throw "markers a=$aStart b=$bStart" }
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
  $t = $t.Replace(
    '#   - ONE Connect UI per PC (Global\ClaudeConnect mutex / Mac flock)',
    '#   - Up to 10 Connect UIs per PC (Global\ClaudeConnect#0..#9)'
  )
  [IO.File]::WriteAllText($tp, $t)
  Write-Host 'OK tests'
} else { Write-Host 'SKIP tests' }

# bat comment
$bat = Join-Path $root 'scripts\client\windows\connect.bat'
$b = [IO.File]::ReadAllText($bat)
$b2 = $b.Replace(
  'REM Atomic single-instance: connect-boot.ps1 acquires Global\ClaudeConnect THEN runs connect.ps1 (no probe/release TOCTOU).',
  'REM Multi-UI (max 10): connect-boot.ps1 acquires Global\ClaudeConnect#N THEN runs connect.ps1 (no probe/release TOCTOU).'
)
[IO.File]::WriteAllText($bat, $b2)

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

# verify markers
$ui = [IO.File]::ReadAllText((Join-Path $root 'scripts\client\connect-ui.ps1'))
$boot = [IO.File]::ReadAllText((Join-Path $root 'scripts\client\windows\connect-boot.ps1'))
$g2 = [IO.File]::ReadAllText($gm)
@(
  @{n='ui multi'; ok=($ui -match 'MULTI_INSTANCE: acquired')},
  @{n='boot hash'; ok=($boot -match 'ClaudeConnect#')},
  @{n='gm slot'; ok=($g2 -match 'CLAUDE_CONNECT_UI_SLOT')},
  @{n='ver'; ok=((Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim() -eq '20260721.11')}
) | ForEach-Object { if (-not $_.ok) { throw "FAIL $($_.n)" }; "HAS $($_.n)" }

Write-Host 'DONE'
