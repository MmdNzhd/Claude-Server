#Requires -Version 5.1
# test-bat-preflight-heal-hard-batch.ps1
# HARD batch gate: connect.bat + connect-preflight/heal/boot contracts (Stage 6).
# Failures here mean "do not ship" the bat preflight/heal/update handoff path.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Get-PreflightBatBlock([string]$Bat) {
    $start = $Bat.IndexOf('if exist "%HERE%connect-preflight.ps1"')
    if ($start -lt 0) { return $null }
    $end = $Bat.IndexOf('REM Stable run id fallback', $start)
    if ($end -lt 0) { $end = $Bat.IndexOf(':AFTER_CLIENT_UPDATE', $start) }
    if ($end -le $start) { return $null }
    return $Bat.Substring($start, $end - $start)
}

Write-Host ''
Write-Host '=== HARD batch: connect.bat preflight / heal / boot ===' -ForegroundColor White

$batPath = Get-ClientFile 'windows\connect.bat'
$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
$bootPath = Get-ClientFile 'windows\connect-boot.ps1'
$verPath = Get-ClientFile 'windows\connect-version.txt'

$bat = Get-Content -LiteralPath $batPath -Raw
$pre = Get-Content -LiteralPath $prePath -Raw
$boot = Get-Content -LiteralPath $bootPath -Raw
$preflightBlock = Get-PreflightBatBlock $bat

$innerStart = $bat.IndexOf('if not defined CLAUDE_CONNECT_BAT_INNER')
$innerBlock = if ($innerStart -ge 0) {
    $innerEnd = $bat.IndexOf('set "HERE=%~dp0"', $innerStart)
    if ($innerEnd -lt 0) { $bat.Substring($innerStart) } else { $bat.Substring($innerStart, $innerEnd - $innerStart) }
} else { '' }

Write-Host ''
Write-Host '--- HARD batch asserts (14) ---' -ForegroundColor Cyan

# 1) CLAUDE_CONNECT_BAT_INNER: VBS style-0 (or Hidden Start-Process fallback); never /MIN
Assert (
    $innerBlock -match 'connect-hide-relaunch\.vbs' -and
    $innerBlock -match 'wscript\.exe //B //Nologo' -and
    $innerBlock -match 'exit /b 0' -and
    $innerBlock -notmatch '/MIN'
) 'BAT_INNER outer uses VBS style-0 hide relaunch then exit /b 0'
Assert ($bat -match 'connect-hide-console\.ps1') 'BAT_INNER belt calls connect-hide-console.ps1'

# 2) Inner path cannot re-enter outer relaunch loop
Assert (($bat -split 'CLAUDE_CONNECT_BAT_INNER').Count -le 3) 'BAT_INNER token bounded (guard + set only)'

# 3) Preflight happy-path PS start budget
$psStarts = 0
if ($preflightBlock) {
    $lines = $preflightBlock -split "`r?`n" | Where-Object { $_ -notmatch '^\s*REM' -and $_ -notmatch '^\s*::' }
    $psStarts = @($lines | Where-Object { $_ -match '(?i)powershell(\.exe)?' }).Count
}
Assert ($null -ne $preflightBlock -and $psStarts -le 3) ("preflight early-path powershell starts <=3 (got $psStarts)")

# 4) Preflight exit 2 heal -> bat HEAL_RELAUNCH (Smart)
Assert (
    $pre -match 'if \(\$healExit -eq 2\) \{ exit 2 \}' -and
    $preflightBlock -match 'if "!PRE_EC!"=="2"' -and
    $preflightBlock -match 'goto HEAL_RELAUNCH'
) 'preflight exit 2 heal routes Smart bat to HEAL_RELAUNCH'

# 5) Preflight exit 3 update relaunch + depth limit
Assert (
    $pre -match 'if \(\$updateExit -eq 2\) \{ exit 3 \}' -and
    $preflightBlock -match 'if "!PRE_EC!"=="3"' -and
    $preflightBlock -match 'if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3'
) 'preflight exit 3 update relaunch bounded by UPDATE_DEPTH>=3'

# 6) SKIP_HEAL / SKIP_UPDATE handoff from bootstrap
Assert (
    $preflightBlock -match 'claude-connect-preflight\.ok' -and
    $preflightBlock -match 'SKIP_UPDATE' -and
    $preflightBlock -match 'SKIP_HEAL' -and
    $pre -match 'skipHealFromHandoff|SKIP_HEAL' -and
    $pre -match 'skipUpdateFromHandoff|SKIP_UPDATE'
) 'bat+preflight honor SKIP_HEAL/SKIP_UPDATE handoff file'

# 7) Preflight success sets bat skip flags before connect-boot path
Assert (
    $preflightBlock -match 'set "CLAUDE_CONNECT_SKIP_HEAL=1"' -and
    $preflightBlock -match 'set "CLAUDE_CONNECT_SKIP_BOOTSTRAP=1"' -and
    $preflightBlock -match 'goto AFTER_CLIENT_UPDATE'
) 'preflight happy path sets SKIP_HEAL/SKIP_BOOTSTRAP then AFTER_CLIENT_UPDATE'

# 8) FAIL UPDATE_BAT_EXIT on non-preflight update exit 1
$updEcBlock = [regex]::Match($bat, '(?s)if !UPD_EC! EQU 1 \(.*?FAIL UPDATE_BAT_EXIT').Value
Assert ($updEcBlock) 'bat logs FAIL UPDATE_BAT_EXIT when UPD_EC=1'

# 9) FAIL OUTDATED_SCRIPTS when version/file guard fails
$outdatedBlock = [regex]::Match($bat, '(?s)if "%OUTDATED%"=="1" \(.*?FAIL OUTDATED_SCRIPTS').Value
Assert ($outdatedBlock) 'bat logs FAIL OUTDATED_SCRIPTS inside OUTDATED block'

# 10) Mutex ownership: boot releases, bat must not
Assert (
    $bat -notmatch 'ReleaseMutex' -and
    $boot -match 'ReleaseMutex' -and
    $boot -match 'finally' -and
    $boot -match 'ClaudeConnectBootMutex'
) 'connect-boot owns mutex release; connect.bat has no ReleaseMutex'

# 11) Bat async handoff to connect-boot (not inline connect.ps1 slot probe)
Assert (
    $bat -match 'start "" /D "%HERE_NOTRAIL%" powershell(\.exe)? -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-boot\.ps1"' -and
    $bat -notmatch '-WindowStyle Hidden -ExecutionPolicy Bypass -File "%HERE%connect\.ps1"'
) 'connect.bat detaches connect-boot.ps1 (no inline hidden connect.ps1)'

# 12) Sepidz: skip heal relaunch on preflight exit 2
Assert (
    $preflightBlock -match 'claude-code-sepidz' -and
    $preflightBlock -match 'goto AFTER_CLIENT_UPDATE'
) 'preflight exit 2 Sepidz skips HEAL_RELAUNCH'

# 13) Sepidz: no Smart bootstrap/heal copy + skip client update
Assert (
    $bat -match 'HERE_IS_SEPIDZ' -and
    $bat -match 'Never pull/copy Smart Claude-Connect bootstrap into a Sepidz tree' -and
    $bat -match 'SKIP_CLIENT_UPDATE=1' -and
    $pre -match '\$isSepidz'
) 'Sepidz guards block Smart copy and skip auto-update'

# 14) Version guard: connect-version.txt must match connect.ps1 ConnectVersion
$expectVer = if (Test-Path -LiteralPath $verPath) {
    (Get-Content -LiteralPath $verPath -TotalCount 1).Trim()
} else { '' }
$ps1Ver = Get-ConnectVersion
Assert (
    $bat -match "ConnectVersion = '!EXPECT_VER!'" -and
    $expectVer -and ($ps1Ver -eq $expectVer) -and
    $pre -match 'Test-HealthyDeploy'
) ("version guard: findstr EXPECT_VER + live parity ($ps1Ver)")

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL PASS (14 bat preflight heal hard batch asserts)' -ForegroundColor Green
    exit 0
}
Write-Host "$fail FAIL (bat preflight heal hard batch)" -ForegroundColor Red
exit 1
