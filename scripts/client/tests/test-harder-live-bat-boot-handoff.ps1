#Requires -Version 5.1
# test-harder-live-bat-boot-handoff.ps1
# HARD LIVE: connect.bat -> connect-boot.ps1 handoff with real mutex slots.
# Static asserts on production scripts; live sandbox uses stub connect.ps1 + real bat/boot.
# Skips live block when <2 free ClaudeConnect# slots (never drains production pool).

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: connect.bat -> connect-boot handoff ===' -ForegroundColor White

$batPath = Get-ClientFile 'windows\connect.bat'
$bootPath = Get-ClientFile 'windows\connect-boot.ps1'
$verPath = Get-ClientFile 'windows\connect-version.txt'

$bat = Get-Content -LiteralPath $batPath -Raw
$boot = Get-Content -LiteralPath $bootPath -Raw

$innerStart = $bat.IndexOf('if not defined CLAUDE_CONNECT_BAT_INNER')
$innerBlock = if ($innerStart -ge 0) {
    $innerEnd = $bat.IndexOf('set "HERE=%~dp0"', $innerStart)
    if ($innerEnd -lt 0) { $bat.Substring($innerStart) } else { $bat.Substring($innerStart, $innerEnd - $innerStart) }
} else { '' }

Write-Host ''
Write-Host '--- Static asserts (6) ---' -ForegroundColor Cyan

# 1) BAT_INNER VBS style-0 hide relaunch (no /MIN taskbar console)
Assert (
    $innerBlock -match 'connect-hide-relaunch\.vbs' -and
    $innerBlock -match 'wscript\.exe //B //Nologo' -and
    $innerBlock -match 'exit /b 0' -and
    $innerBlock -notmatch '/MIN'
) 'BAT_INNER outer uses VBS style-0 hide relaunch then exit /b 0'

# 2) Inner path cannot re-enter outer relaunch loop
Assert (($bat -split 'CLAUDE_CONNECT_BAT_INNER').Count -le 3) 'BAT_INNER token bounded (guard + set only)'

# 3-4) Mutex ownership: boot releases, bat must not
Assert ($bat -notmatch 'ReleaseMutex') 'connect.bat has no ReleaseMutex (no TOCTOU probe)'
Assert (
    $boot -match 'ReleaseMutex' -and
    $boot -match 'finally' -and
    $boot -match 'ClaudeConnectBootMutex'
) 'connect-boot owns mutex acquire/release'

# 5) Bat async handoff to connect-boot
Assert (
    $bat -match 'start "" /D "%HERE_NOTRAIL%" powershell(\.exe)? -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-boot\.ps1"'
) 'connect.bat detaches connect-boot.ps1 (async handoff)'

# 6) Version guard: connect-version.txt matches connect.ps1 ConnectVersion when present
$expectVer = if (Test-Path -LiteralPath $verPath) {
    (Get-Content -LiteralPath $verPath -TotalCount 1).Trim()
} else { '' }
$ps1Ver = Get-ConnectVersion
Assert (
    $bat -match "ConnectVersion = '!EXPECT_VER!'" -and
    $expectVer -and ($ps1Ver -eq $expectVer)
) ("version guard: bat findstr EXPECT_VER + live parity ($ps1Ver)")

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

function New-BatBootSandbox {
    param(
        [string]$Root,
        [string]$Ver,
        [string]$MarkerDir
    )
    $null = New-Item -ItemType Directory -Force -Path $Root
    $null = New-Item -ItemType Directory -Force -Path $MarkerDir

    foreach ($rel in @('connect.bat', 'connect-boot.ps1', 'connect-version.txt')) {
        Copy-Item -LiteralPath (Get-ClientFile "windows\$rel") -Destination (Join-Path $Root $rel) -Force
    }
    Set-Content -LiteralPath (Join-Path $Root 'connect-version.txt') -Value $Ver -Encoding ASCII

    # Minimal OUTDATED-guard stubs (connect.bat findstr / exist checks only).
    Set-Content -LiteralPath (Join-Path $Root 'editor-launch.ps1') -Value '# Path.Combine OUTDATED guard marker' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'connect-ui.ps1') -Value '# H hygiene menu key' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'git-mode.ps1') -Value 'function Acquire-TunnelPort { }' -Encoding ASCII
    foreach ($name in @(
        'windows-mcp-laptop.ps1', 'cursor-auth-laptop.ps1',
        'connect-diagnostic.ps1', 'cursor-proxy-sidecar.ps1'
    )) {
        Set-Content -LiteralPath (Join-Path $Root $name) -Value "# stub $name" -Encoding ASCII
    }

    $preStub = @'
# stub preflight: happy path exit 0 -> bat sets SKIP_HEAL and jumps to AFTER_CLIENT_UPDATE
exit 0
'@
    Set-Content -LiteralPath (Join-Path $Root 'connect-preflight.ps1') -Value $preStub -Encoding ASCII

    $psStub = @"
#Requires -Version 5.1
# stub connect.ps1 for bat-boot handoff live test (fast exit, records UI_SLOT)
`$ErrorActionPreference = 'Stop'
`$script:ConnectVersion = '$Ver'
# ConnectVersion = '$Ver'
# @(Choose-Project pipeline-safe
# Show-ConnectHygieneInteractive
`$markerDir = Join-Path `$PSScriptRoot 'markers'
`$testId = (`$env:CLAUDE_CONNECT_TEST_ID + '').Trim()
if (-not `$testId) { `$testId = 'default' }
`$slot = (`$env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
`$skipHeal = (`$env:CLAUDE_CONNECT_SKIP_HEAL + '').Trim()
`$line = "slot=`$slot skip_heal=`$skipHeal pid=`$PID"
Set-Content -LiteralPath (Join-Path `$markerDir "`$testId.marker") -Value `$line -Encoding ASCII
exit 0
"@
    Set-Content -LiteralPath (Join-Path $Root 'connect.ps1') -Value $psStub -Encoding ASCII
}

function Wait-ForMarker {
    param(
        [string]$MarkerDir,
        [string]$Id,
        [int]$TimeoutSec = 15
    )
    $path = Join-Path $MarkerDir "$Id.marker"
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $path) { return $path }
        Start-Sleep -Milliseconds 120
    }
    return $null
}

function Read-MarkerSlot([string]$MarkerPath) {
    if (-not $MarkerPath -or -not (Test-Path -LiteralPath $MarkerPath)) { return $null }
    $raw = (Get-Content -LiteralPath $MarkerPath -Raw).Trim()
    if ($raw -match 'slot=(\d+)') { return $Matches[1] }
    return $null
}

$free0 = Get-FreeConnectSlotCount
Note ("probe free slots before live = $free0 / 10")
if ($free0 -lt 2) {
    $waitDeadline = [datetime]::UtcNow.AddSeconds(45)
    while ($free0 -lt 2 -and [datetime]::UtcNow -lt $waitDeadline) {
        Start-Sleep -Seconds 2
        $free0 = Get-FreeConnectSlotCount
    }
    Note ("probe free slots after wait = $free0 / 10")
}

if ($free0 -lt 2) {
    Write-Host ("SKIPPED live: only {0} free ClaudeConnect# slots; need >=2" -f $free0) -ForegroundColor Yellow
    $Skip++
    Write-Host ''
    if ($Fail -eq 0) {
        Write-Host ("BAT-BOOT handoff RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
        exit 0
    }
    Write-Host ("BAT-BOOT handoff RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}

$ver = if ($expectVer) { $expectVer } else { Get-ConnectVersion }
$root = Join-Path $env:TEMP ("cc-bat-boot-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$markerDir = Join-Path $root 'markers'
$sandboxBat = Join-Path $root 'connect.bat'
$sandboxBoot = Join-Path $root 'connect-boot.ps1'
$procs = @()

try {
    New-BatBootSandbox -Root $root -Ver $ver -MarkerDir $markerDir

    Write-Host ''
    Write-Host '--- Live asserts (8) ---' -ForegroundColor Cyan

    # 7-9) INNER bat path: pre-set BAT_INNER so cmd runs inner body once (no outer relaunch loop)
    Note 'CaseA: cmd /c INNER connect.bat -> connect-boot -> stub connect.ps1'
    $batCmd = 'set CLAUDE_CONNECT_BAT_INNER=1& set CLAUDE_CONNECT_TEST_ID=inner& call "' + $sandboxBat + '"'
    $pInner = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @(
        '/d', '/c', $batCmd
    ) -WorkingDirectory $root -PassThru -WindowStyle Hidden
    $procs += $pInner

    $innerMarker = Wait-ForMarker -MarkerDir $markerDir -Id 'inner' -TimeoutSec 18
    Assert ($null -ne $innerMarker) 'LIVE INNER bat: stub connect.ps1 wrote marker'
    $innerSlot = Read-MarkerSlot $innerMarker
    Assert ($innerSlot -match '^[0-9]$') ("LIVE INNER bat: marker slot 0..9 (got $innerSlot)")
    if ($innerMarker) {
        $innerRaw = (Get-Content -LiteralPath $innerMarker -Raw).Trim()
        Assert ($innerRaw -match 'skip_heal=1') 'LIVE INNER bat: SKIP_HEAL=1 reached stub connect.ps1'
    }

    if (-not $pInner.HasExited) { $null = $pInner.WaitForExit(10000) }

    # 10-11) Direct connect-boot.ps1 (no bat preflight SKIP_HEAL requirement on this path)
    Note 'CaseB: direct powershell connect-boot.ps1'
    Remove-Item -LiteralPath (Join-Path $markerDir 'direct.marker') -Force -ErrorAction SilentlyContinue
    $bootCmd = 'set CLAUDE_CONNECT_TEST_ID=direct& powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' + $sandboxBoot + '"'
    $pBoot = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @(
        '/d', '/c', $bootCmd
    ) -WorkingDirectory $root -PassThru -WindowStyle Hidden
    $procs += $pBoot

    $bootMarker = Wait-ForMarker -MarkerDir $markerDir -Id 'direct' -TimeoutSec 15
    Assert ($null -ne $bootMarker) 'LIVE direct boot: stub connect.ps1 wrote marker'
    $bootSlot = Read-MarkerSlot $bootMarker
    Assert ($bootSlot -match '^[0-9]$') ("LIVE direct boot: marker slot 0..9 (got $bootSlot)")

    if (-not $pBoot.HasExited) { $null = $pBoot.WaitForExit(10000) }

    Start-Sleep -Milliseconds 300

    # 12-14) Two parallel INNER bat launches -> distinct slots
    Note 'CaseC: two parallel INNER connect.bat launches'
    foreach ($id in @('par-a', 'par-b')) {
        Remove-Item -LiteralPath (Join-Path $markerDir "$id.marker") -Force -ErrorAction SilentlyContinue
    }
    $holdStub = Join-Path $root 'connect-hold.ps1'
    Set-Content -LiteralPath $holdStub -Value @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$script:ConnectVersion = '$Ver'
# ConnectVersion = '$Ver'
# @(Choose-Project pipeline-safe
# Show-ConnectHygieneInteractive
`$markerDir = Join-Path `$PSScriptRoot 'markers'
`$testId = (`$env:CLAUDE_CONNECT_TEST_ID + '').Trim()
if (-not `$testId) { `$testId = 'default' }
`$slot = (`$env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
Set-Content -LiteralPath (Join-Path `$markerDir "`$testId.marker") -Value ("slot=" + `$slot) -Encoding ASCII
Start-Sleep -Seconds 6
exit 0
"@ -Encoding ASCII
    Copy-Item -LiteralPath $holdStub -Destination (Join-Path $root 'connect.ps1') -Force

    $parProcs = @()
    foreach ($id in @('par-a', 'par-b')) {
        $parCmd = 'set CLAUDE_CONNECT_BAT_INNER=1& set CLAUDE_CONNECT_TEST_ID=' + $id + '& call "' + $sandboxBat + '"'
        $pp = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @(
            '/d', '/c', $parCmd
        ) -WorkingDirectory $root -PassThru -WindowStyle Hidden
        $parProcs += $pp
        $procs += $pp
        Start-Sleep -Milliseconds 150
    }

    $deadline = [datetime]::UtcNow.AddSeconds(12)
    while ([datetime]::UtcNow -lt $deadline) {
        $n = @(Get-ChildItem -LiteralPath $markerDir -Filter 'par-*.marker' -ErrorAction SilentlyContinue).Count
        if ($n -ge 2) { break }
        Start-Sleep -Milliseconds 100
    }

    $parFiles = @(Get-ChildItem -LiteralPath $markerDir -Filter 'par-*.marker' -ErrorAction SilentlyContinue)
    Assert ($parFiles.Count -eq 2) ("LIVE parallel: two markers written (got $($parFiles.Count))")
    $parSlots = @($parFiles | ForEach-Object { Read-MarkerSlot $_.FullName } | Where-Object { $_ -match '^[0-9]$' })
    Assert ($parSlots.Count -eq 2) ("LIVE parallel: both markers slot 0..9 ($($parSlots -join ','))")
    $uniq = @($parSlots | Sort-Object -Unique)
    Assert ($uniq.Count -eq 2) ("LIVE parallel: two DISTINCT slots ($($parSlots -join ','))")

    foreach ($pp in $parProcs) {
        if ($pp -and -not $pp.HasExited) { $null = $pp.WaitForExit(20000) }
    }
    # Mutex reclaim can lag briefly after stub connect.ps1 exits; poll before asserting.
    $freeEnd = Get-FreeConnectSlotCount
    $reclaimDeadline = [datetime]::UtcNow.AddSeconds(20)
    while ($freeEnd -lt ($free0 - 1) -and [datetime]::UtcNow -lt $reclaimDeadline) {
        Start-Sleep -Milliseconds 500
        $freeEnd = Get-FreeConnectSlotCount
    }
    Note ("probe free slots after release = $freeEnd / 10")
    Assert ($freeEnd -ge ($free0 - 1)) ("LIVE parallel: slots returned after exit (before=$free0 after=$freeEnd)")

} catch {
    Write-Host ("  FAIL  live exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $Fail++
} finally {
    Remove-Item Env:CLAUDE_CONNECT_TEST_ID -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("BAT-BOOT handoff RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("BAT-BOOT handoff RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
