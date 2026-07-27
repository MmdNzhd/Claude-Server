#Requires -Version 5.1
# test-harder-live-runid-bat.ps1
# HARD LIVE dual connect.bat-like chain: mint-before-preflight, per-PID handoff,
# gated shared adopt, and parallel cmd races (0ms + 50ms stagger).
# 14 Assert calls. Does NOT modify run-all.ps1.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

$failed = 0
$passed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

function Invoke-DualMintRace {
    param(
        [int]$StaggerMs,
        [string]$Label
    )

    $tag = [guid]::NewGuid().ToString('N')
    $workDir = Join-Path $env:TEMP ("claude-runid-harder-$tag")
    $out1 = Join-Path $env:TEMP ("rid-harder-out1-$tag.txt")
    $out2 = Join-Path $env:TEMP ("rid-harder-out2-$tag.txt")
    $shared = Join-Path $env:TEMP 'claude-connect-run-id.txt'
    $poison = 'deadbeefcafe'
    $probeBat = Join-Path $workDir 'probe-chain.bat'
    $handoffPs1 = Join-Path $workDir 'preflight-runid-handoff.ps1'

    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    # Real RUN_ID handoff block extracted verbatim from connect-preflight.ps1 (lines 75-88).
    $preSrc = Get-Content -LiteralPath (Get-ClientFile 'windows\connect-preflight.ps1') -Raw
    $handoffStart = $preSrc.IndexOf('# Prefer RUN_ID from parent connect.bat')
    $handoffEnd = $preSrc.IndexOf("try {`r`n    `$logDir = Join-Path `$env:USERPROFILE '.config\claude-connect\logs'")
    if ($handoffEnd -lt 0) {
        $handoffEnd = $preSrc.IndexOf("try {`n    `$logDir = Join-Path `$env:USERPROFILE '.config\claude-connect\logs'")
    }
    $handoffBlock = if ($handoffStart -ge 0 -and $handoffEnd -gt $handoffStart) {
        $preSrc.Substring($handoffStart, $handoffEnd - $handoffStart).TrimEnd()
    } else {
        throw 'Could not extract RUN_ID handoff block from connect-preflight.ps1'
    }
    Set-Content -LiteralPath $handoffPs1 -Value ($handoffBlock + [Environment]::NewLine) -Encoding UTF8

    # Real mint-before-preflight + gated shared adopt extracted from connect.bat.
    $probeBody = @"
@echo off
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "HERE_NOTRAIL=%HERE:~0,-1%"
REM Fresh UI: parent must not leak a sticky RUN_ID into this process.
set "CLAUDE_CONNECT_RUN_ID="
REM Multi-UI: mint a unique RUN_ID in THIS bat process BEFORE preflight.
if not defined CLAUDE_CONNECT_RUN_ID (
    for /f %%I in ('powershell -NoProfile -WindowStyle Hidden -Command "[guid]::NewGuid().ToString('N').Substring(0,12)"') do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
if exist "%HERE%preflight-runid-handoff.ps1" (
    powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%HERE%preflight-runid-handoff.ps1"
)
REM Only adopt preflight handoff file when bat still has no RUN_ID (should not happen).
if not defined CLAUDE_CONNECT_RUN_ID if exist "%TEMP%\claude-connect-run-id.txt" (
    for /f "usebackq delims=" %%I in ("%TEMP%\claude-connect-run-id.txt") do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
echo !CLAUDE_CONNECT_RUN_ID!
"@
    Set-Content -LiteralPath $probeBat -Value $probeBody -Encoding ASCII

    # Poison the shared handoff so a mint-first UI cannot be forced to the same stale id.
    Set-Content -LiteralPath $shared -Value $poison -Encoding ASCII

    $prevRunId = $env:CLAUDE_CONNECT_RUN_ID
    Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue
    $p1 = $null
    $p2 = $null
    try {
        $p1 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probeBat`"") `
            -PassThru -WindowStyle Hidden -WorkingDirectory $workDir `
            -RedirectStandardOutput $out1 -RedirectStandardError ($out1 + '.err')
        if ($StaggerMs -gt 0) { Start-Sleep -Milliseconds $StaggerMs }
        $p2 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probeBat`"") `
            -PassThru -WindowStyle Hidden -WorkingDirectory $workDir `
            -RedirectStandardOutput $out2 -RedirectStandardError ($out2 + '.err')
    } finally {
        if ($null -ne $prevRunId -and "$prevRunId" -ne '') {
            $env:CLAUDE_CONNECT_RUN_ID = $prevRunId
        }
    }

    if ($p1) { $null = $p1.WaitForExit(20000) }
    if ($p2) { $null = $p2.WaitForExit(20000) }

    $id1 = ''
    $id2 = ''
    if ((Test-Path -LiteralPath $out1)) {
        $id1 = ((Get-Content -LiteralPath $out1 -ErrorAction SilentlyContinue | Select-Object -First 1) + '').Trim()
    }
    if ((Test-Path -LiteralPath $out2)) {
        $id2 = ((Get-Content -LiteralPath $out2 -ErrorAction SilentlyContinue | Select-Object -First 1) + '').Trim()
    }

    return @{
        Label = $Label
        P1 = $p1
        P2 = $p2
        Id1 = $id1
        Id2 = $id2
        Poison = $poison
        Out1 = $out1
        Out2 = $out2
        WorkDir = $workDir
    }
}

Write-Host ''
Write-Host '=== test-harder-live-runid-bat ===' -ForegroundColor Cyan
Write-Host ''

$batPath = Get-ClientFile 'windows\connect.bat'
$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
$bat = Get-Content -LiteralPath $batPath -Raw
$pre = Get-Content -LiteralPath $prePath -Raw

Write-Host '--- Static bat/preflight contracts (6) ---' -ForegroundColor DarkCyan

Assert ($bat -match 'Multi-UI: mint a unique RUN_ID') 'bat documents multi-UI RUN_ID mint'

$mintAt = $bat.IndexOf('Multi-UI: mint a unique RUN_ID')
$preAt = $bat.IndexOf('if exist "%HERE%connect-preflight.ps1"')
Assert ($mintAt -ge 0 -and $preAt -gt $mintAt) 'connect.bat mints RUN_ID before preflight'

Assert (
    $bat -match 'if not defined CLAUDE_CONNECT_RUN_ID if exist "%TEMP%\\claude-connect-run-id\.txt"'
) 'bat adopts shared RUN_ID handoff only when unset (double-gated)'

Assert ($pre -match 'claude-connect-run-id\.\{0\}\.txt') 'preflight per-PID RUN_ID handoff file'

Assert (
    $pre -match 'if \(-not \(Test-Path -LiteralPath \$sharedHandoff\)\)'
) 'preflight writes shared handoff only when absent (no stomp)'

Assert (
    $bat -match 'REM Stable run id fallback when preflight\.ps1 is absent' -and
    ($bat -match '(?s)REM Stable run id fallback[\s\S]*if not defined CLAUDE_CONNECT_RUN_ID')
) 'bat fallback mint when preflight.ps1 absent'

Write-Host '--- LIVE dual-mint race: 0ms stagger (4) ---' -ForegroundColor DarkCyan

$round0 = $null
try {
    $round0 = Invoke-DualMintRace -StaggerMs 0 -Label '0ms'
    Assert ($round0.P1.HasExited -and $round0.P2.HasExited) '0ms: both probe-chain processes exited'
    Assert ($round0.Id1 -match '^[0-9a-fA-F]{12}$') "0ms: ui1 RUN_ID 12-hex ($($round0.Id1))"
    Assert ($round0.Id2 -match '^[0-9a-fA-F]{12}$') "0ms: ui2 RUN_ID 12-hex ($($round0.Id2))"
    Assert (
        ($round0.Id1 -ne $round0.Id2) -and
        ($round0.Id1 -ne $round0.Poison) -and
        ($round0.Id2 -ne $round0.Poison)
    ) "0ms: distinct ids, shared poison ignored ($($round0.Id1) vs $($round0.Id2) poison=$($round0.Poison))"
}
finally {
    if ($round0) {
        Remove-Item -LiteralPath $round0.WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $round0.Out1, ($round0.Out1 + '.err'), $round0.Out2, ($round0.Out2 + '.err') `
            -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '--- LIVE dual-mint race: 50ms stagger (4) ---' -ForegroundColor DarkCyan

$round50 = $null
try {
    $round50 = Invoke-DualMintRace -StaggerMs 50 -Label '50ms'
    Assert ($round50.P1.HasExited -and $round50.P2.HasExited) '50ms: both probe-chain processes exited'
    Assert ($round50.Id1 -match '^[0-9a-fA-F]{12}$') "50ms: ui1 RUN_ID 12-hex ($($round50.Id1))"
    Assert ($round50.Id2 -match '^[0-9a-fA-F]{12}$') "50ms: ui2 RUN_ID 12-hex ($($round50.Id2))"
    Assert (
        ($round50.Id1 -ne $round50.Id2) -and
        ($round50.Id1 -ne $round50.Poison) -and
        ($round50.Id2 -ne $round50.Poison)
    ) "50ms: distinct ids, shared poison ignored ($($round50.Id1) vs $($round50.Id2) poison=$($round50.Poison))"
}
finally {
    if ($round50) {
        Remove-Item -LiteralPath $round50.WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $round50.Out1, ($round50.Out1 + '.err'), $round50.Out2, ($round50.Out2 + '.err') `
            -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host ("=== RESULT pass={0} fail={1} asserts={2} ===" -f $passed, $failed, ($passed + $failed)) `
    -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
