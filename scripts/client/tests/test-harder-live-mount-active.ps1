#Requires -Version 5.1
# test-harder-live-mount-active.ps1
# HARDER LIVE mount/ACTIVE_MOUNT gate: extracted Get-MountsCached + Get-ConnectProblemVerdict,
# live 8-project cache round-trip + PS5.1 collapse guard, live MOUNT_PENDING vs MOUNT_FAILED,
# structural ClearActiveMount + cold BG MOUNT_CHECK_SKIPPED, live non-blocking BG kickoff.
# Callers: manual / run-harder-battery (do NOT edit run-all.ps1 in this task).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== HARDER LIVE mount/ACTIVE_MOUNT ===' -ForegroundColor White

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gm      = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# 1-2) Extract cache helpers from shipped connect.ps1
Write-Host ''
Write-Host '--- Extract Get-MountsCached ---' -ForegroundColor Cyan

$fnPath   = Get-FunctionSource -Content $connect -Name 'Get-MountsCachePath'
$fnCached = Get-FunctionSource -Content $connect -Name 'Get-MountsCached'
Assert ($fnPath.Length -gt 40) 'extracted Get-MountsCachePath from connect.ps1'
Assert (
    ($fnCached.Length -gt 200) -and
    ($fnCached -match '\$parsed\s*=\s*\$raw\s*\|\s*ConvertFrom-Json')
) 'extracted Get-MountsCached with PS5.1-safe parse-then-wrap pattern'

# 2) Diagnostic Get-ConnectProblemVerdict (canon connect-diagnostic.ps1)
Write-Host ''
Write-Host '--- Extract Get-ConnectProblemVerdict ---' -ForegroundColor Cyan

. (Get-ClientFile 'connect-diagnostic.ps1')
Assert ($null -ne (Get-Command Get-ConnectProblemVerdict -ErrorAction SilentlyContinue)) `
    'Get-ConnectProblemVerdict defined after dot-source'

# 3) Structural: Push-ServerConnectConf ClearActiveMount on disconnect
Write-Host ''
Write-Host '--- Structural ACTIVE_MOUNT clear ---' -ForegroundColor Cyan

$pushFn = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
$clearFn = Get-FunctionSource -Content $gm -Name 'Clear-SessionMount'
Assert ($pushFn -match '\[switch\]\$ClearActiveMount') `
    'Push-ServerConnectConf exposes -ClearActiveMount switch'
Assert ($clearFn -match '(?ms)Push-ServerConnectConf\s+-ClearActiveMount') `
    'Clear-SessionMount clears ACTIVE_MOUNT on disconnect'

# 4) Structural: cold BG branch skips sync mount-check
Write-Host ''
Write-Host '--- Structural cold BG MOUNT_CHECK_SKIPPED ---' -ForegroundColor Cyan

$bgBranch = [regex]::Match(
    $connect,
    '(?ms)\} else \{\s*# User request \(2026-07-24\): don''t block.*?Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
).Value
if ($bgBranch.Length -lt 80) {
    $bgBranch = [regex]::Match(
        $connect,
        '(?ms)Step "Mounting files"\s*\r?\n\s*Write-ConnectLog ''MOUNT_CHECK_SKIPPED reason=bg_up''.*?Pending\s*=\s*\$true'
    ).Value
}
Assert (
    ($bgBranch -match 'MOUNT_CHECK_SKIPPED reason=bg_up') -and
    ($bgBranch -match 'Pending\s*=\s*\$true') -and
    ($bgBranch -notmatch 'Invoke-MountProject')
) 'cold BG branch: MOUNT_CHECK_SKIPPED reason=bg_up + Pending, no sync Invoke-MountProject'

# 7-10) Live diagnostic sandbox: MOUNT_PENDING vs MOUNT_FAILED
Write-Host ''
Write-Host '--- Live diagnostic verdicts ---' -ForegroundColor Cyan

$pending = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'started_in_background'
    MountPoint = ''; PathExists = ''; ServerReachable = $true
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true
    OnFolder = $false; AgentHome = $false; WindowOpen = $false; DidLaunch = $false
}
Assert ($pending.Code -eq 'MOUNT_PENDING') `
    'live: started_in_background => MOUNT_PENDING (not MOUNT_FAILED)'
Assert ($pending.Severity -eq 'INFO') `
    'live: MOUNT_PENDING is INFO severity (no red diagnostic box)'

$failedMount = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'fuse: mount failed'
    MountPoint = 'no'; PathExists = 'no'; ServerReachable = $true
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true; OnFolder = $false
}
Assert ($failedMount.Code -eq 'MOUNT_FAILED' -and $failedMount.Severity -eq 'ERROR') `
    'live: fuse mount failure => MOUNT_FAILED ERROR'

# 11-12) Live 8-project cache round-trip + PS5.1 collapse guard
Write-Host ''
Write-Host '--- Live mounts cache (8 projects) ---' -ForegroundColor Cyan

function Get-Mounts { return @() }
. ([ScriptBlock]::Create($fnPath))
. ([ScriptBlock]::Create($fnCached))

$tmpDir = Join-Path $env:TEMP ("harder-live-mount-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$script:CfgDir = $tmpDir
try {
    $rows = 1..8 | ForEach-Object {
        [PSCustomObject]@{
            Id = "hl$_"; Label = "Harder $_"; Rpath = "R$_"; Lpath = "L$_"
            Path = "P$_"; Active = ($_ -eq 1); Mounted = ($_ -le 2)
        }
    }
    (@($rows) | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Get-MountsCachePath) -Encoding UTF8
    $loaded = @(Get-MountsCached)
    Assert (
        $loaded.Count -eq 8 -and $loaded[0].Id -eq 'hl1' -and $loaded[7].Id -eq 'hl8'
    ) "live: Get-MountsCached round-trip preserves 8 distinct projects (got $($loaded.Count))"
    $raw = Get-Content -LiteralPath (Get-MountsCachePath) -Raw
    $buggy = @($raw | ConvertFrom-Json)
    Assert ($buggy.Count -eq 1) `
        'live: PS5.1 guard - buggy @($raw|ConvertFrom-Json) collapses array to 1 element'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmpDir -ErrorAction SilentlyContinue
}

# 13-14) Live Start-MountProjectBackground non-blocking kickoff
Write-Host ''
Write-Host '--- Live BG kickoff (<3s) ---' -ForegroundColor Cyan

$bgFn = Get-FunctionSource -Content $connect -Name 'Start-MountProjectBackground'
Assert ($bgFn.Length -gt 100) 'extracted Start-MountProjectBackground from connect.ps1'
. ([ScriptBlock]::Create($bgFn))

$tmpLog = Join-Path $env:TEMP ("cc-hlm-bg-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpLog | Out-Null
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $launched = Start-MountProjectBackground `
        -ProjectId 'harder-live-mount' `
        -Alias 'claude-connect-unreachable-harder-live-alias' `
        -LogDir $tmpLog `
        -SessionId 'hlm001'
    $sw.Stop()
    Assert ($launched -eq $true) 'live: Start-MountProjectBackground spawns detached runner'
    Assert ($sw.ElapsedMilliseconds -lt 3000) `
        "live: kickoff non-blocking ($($sw.ElapsedMilliseconds)ms, parent does not wait on ssh mount)"
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmpLog -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $env:TEMP 'claude-connect-mountbg') -Filter 'mount-bg-*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-1) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
