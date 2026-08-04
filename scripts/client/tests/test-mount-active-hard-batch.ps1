#Requires -Version 5.1
# test-mount-active-hard-batch.ps1
# HARD batch gate: ACTIVE_MOUNT single-project, BG mount kickoff, failfast probes,
# mounts cache, MOUNT_PENDING vs MOUNT_FAILED diagnostic, disconnect clear, hash seed,
# skip mount-check on bg_up. Mixes structural extraction + live sandbox (no shallow greps alone).
# Callers: manual / future run-all wiring (do not edit run-all.ps1 in this task).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Mount ACTIVE hard batch (static + live) ===' -ForegroundColor White

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gm      = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# 1-3) ACTIVE_MOUNT single-project: remote CLEAR wipe, live guard, disconnect clear
Write-Host ''
Write-Host '--- ACTIVE_MOUNT single-project ---' -ForegroundColor Cyan

$pushFn = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
$remoteBody = ''
$rbMark = '$remoteBody = @"'
$rbIdx = $pushFn.IndexOf($rbMark)
if ($rbIdx -ge 0) {
    $rbStart = $pushFn.IndexOf("`n", $rbIdx) + 1
    $rbEnd = $pushFn.IndexOf("`n`"@", $rbStart)
    if ($rbEnd -gt $rbStart) { $remoteBody = $pushFn.Substring($rbStart, $rbEnd - $rbStart) }
}
Assert (
    ($remoteBody -match '(?ms)if \[ "`\$CLEAR" = "1" \]; then\s+AM=') -and
    ($remoteBody -match 'mountpoint -q "`\$HOME/mounts/`\$CUR_AM"') -and
    ($remoteBody -match 'reason=other_still_mounted')
) 'PushConf remote: CLEAR wipes AM; guard uses mountpoint -q before clobber'

$clearFn = Get-FunctionSource -Content $gm -Name 'Clear-SessionMount'
Assert ($clearFn -match '(?ms)if \(\$Port\).*?Push-ServerConnectConf\s+-ClearActiveMount') `
    'disconnect Clear-SessionMount clears ACTIVE_MOUNT via Push-ServerConnectConf'

# 4) Hash seed from Server setup MOUNT_HASH
Write-Host ''
Write-Host '--- MOUNT_HASH hash seed ---' -ForegroundColor Cyan

$initFn = Get-FunctionSource -Content $connect -Name 'Initialize-ServerSession'
Assert (
    ($initFn -match 'MOUNT_HASH:') -and
    ($initFn -match '\$script:ClaudeMountSyncVerifiedHash\s*=\s*\$remoteHash')
) 'Initialize-ServerSession seeds ClaudeMountSyncVerifiedHash from MOUNT_HASH batch line'

# 5-6) Failfast mount health
Write-Host ''
Write-Host '--- Failfast mount health ---' -ForegroundColor Cyan

$mountHealth = Get-FunctionSource -Content $gm -Name 'Test-ProjectMountHealthy'
Assert ($mountHealth -match 'timeout 12.*-NoRetryOnTimeout|-NoRetryOnTimeout.*timeout 12') `
    'Test-ProjectMountHealthy: bounded timeout 12 + NoRetryOnTimeout'

$sshX = Get-FunctionSource -Content $connect -Name 'SshX'
Assert ($sshX -match '(?s)Exit\s*-eq\s*124.*?-not\s+\$NoRetryOnTimeout') `
    'SshX skips timeout retry when NoRetryOnTimeout (failfast contract)'

# 7-8) Cold BG branch skips sync mount-check
Write-Host ''
Write-Host '--- BG mount skip sync check ---' -ForegroundColor Cyan

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
    ($bgBranch -match 'Ok\s*=\s*\$false') -and
    ($bgBranch -match 'Pending\s*=\s*\$true') -and
    ($bgBranch -notmatch 'Test-ProjectMountHealthy|Invoke-MountProject')
) 'cold BG branch: MOUNT_CHECK_SKIPPED + Pending Ok=$false, no sync mount/up'

$bgFn = Get-FunctionSource -Content $connect -Name 'Start-MountProjectBackground'
Assert ($bgFn -match 'MOUNT_BG_STARTED project=') `
    'Start-MountProjectBackground logs MOUNT_BG_STARTED on parent kickoff'
Assert ($bgFn -match 'MOUNT_BG_RETRY project=') `
    'mount-bg runner retries transient SSH/mount failures (MOUNT_BG_RETRY)'
Assert ($bgFn -match 'maxAttempts = 3') `
    'mount-bg runner caps retries at 3 total attempts'
Assert ($connect -match '(?ms)if \(\$skipRemount\).*?skip_remount_healthy') `
    'healthy git_mode=off skipRemount branch skips BG kick (single mounted project reuse)'

# 9-10) Live diagnostic: MOUNT_PENDING vs MOUNT_FAILED
Write-Host ''
Write-Host '--- Live diagnostic sandbox ---' -ForegroundColor Cyan

. (Get-ClientFile 'connect-diagnostic.ps1')
$pending = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'started_in_background'
    MountPoint = ''; PathExists = ''; ServerReachable = $true
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true
    OnFolder = $false; AgentHome = $false; WindowOpen = $false; DidLaunch = $false
}
Assert ($pending.Code -eq 'MOUNT_PENDING' -and $pending.Severity -eq 'INFO') `
    'live: bg kickoff alone => MOUNT_PENDING INFO (not red MOUNT_FAILED)'

$failedMount = Get-ConnectProblemVerdict -Ctx @{
    TunnelUp = $true; MountOk = $false; MountOut = 'fuse: mount failed'
    MountPoint = 'no'; PathExists = 'no'; ServerReachable = $true
    EditorCmd = 'cursor'; CursorExeFound = $true; AuthOk = $true; OnFolder = $false
}
Assert ($failedMount.Code -eq 'MOUNT_FAILED' -and $failedMount.Severity -eq 'ERROR') `
    'live: real fuse failure => MOUNT_FAILED ERROR'

# 11-12) Live mounts cache round-trip (real extracted functions)
Write-Host ''
Write-Host '--- Live mounts cache ---' -ForegroundColor Cyan

$fnPath   = Get-FunctionSource -Content $connect -Name 'Get-MountsCachePath'
$fnCached = Get-FunctionSource -Content $connect -Name 'Get-MountsCached'
function Get-Mounts { return @() }
. ([ScriptBlock]::Create($fnPath))
. ([ScriptBlock]::Create($fnCached))

$tmpDir = Join-Path $env:TEMP ("mount-active-hard-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$script:CfgDir = $tmpDir
try {
    $rows = 1..8 | ForEach-Object {
        [PSCustomObject]@{
            Id = "p$_"; Label = "L $_"; Rpath = "R$_"; Lpath = "L$_"
            Path = "P$_"; Active = ($_ -eq 1); Mounted = ($_ -le 2)
        }
    }
    (@($rows) | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Get-MountsCachePath) -Encoding UTF8
    $loaded = @(Get-MountsCached)
    Assert ($loaded.Count -eq 8 -and $loaded[0].Id -eq 'p1' -and $loaded[7].Id -eq 'p8') `
        "live Get-MountsCached round-trip preserves 8 distinct projects (got $($loaded.Count))"
    $raw = Get-Content -LiteralPath (Get-MountsCachePath) -Raw
    $buggy = @($raw | ConvertFrom-Json)
    Assert ($buggy.Count -eq 1) `
        'PS5.1 guard: buggy @($raw|ConvertFrom-Json) collapses array to 1 element'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmpDir -ErrorAction SilentlyContinue
}

# 13-14) Live BG kickoff non-blocking
Write-Host ''
Write-Host '--- Live BG kickoff ---' -ForegroundColor Cyan

. ([ScriptBlock]::Create($bgFn))
$tmpLog = Join-Path $env:TEMP ("cc-mah-bg-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpLog | Out-Null
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $launched = Start-MountProjectBackground `
        -ProjectId 'hard-batch-live' `
        -Alias 'claude-connect-unreachable-hard-batch-alias' `
        -LogDir $tmpLog `
        -SessionId 'mahbg01'
    $sw.Stop()
    Assert ($launched -eq $true) 'live: Start-MountProjectBackground spawns detached runner'
    Assert ($sw.ElapsedMilliseconds -lt 3000) `
        "live: kickoff non-blocking ($($sw.ElapsedMilliseconds)ms, not waiting on ssh mount)"
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
