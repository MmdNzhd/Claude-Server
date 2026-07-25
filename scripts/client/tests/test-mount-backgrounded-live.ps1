# test-mount-backgrounded-live.ps1 - user request (2026-07-24): "Mounting files" only serves
# Cursor's remote file-tree UI (SSHFS mounts the laptop disk onto the server) - agent work goes
# through laptop-exec / SSH-first per CLAUDE.md, never through this mount, so nothing needs to
# wait on it. Cold mounts measured 13-25s in real sessions; Start-MountProjectBackground kicks
# the mount off detached instead of blocking the connect UI. This test proves the kickoff itself
# is genuinely non-blocking (returns near-instantly regardless of how long the real mount takes)
# AND that a real detached process is actually spawned and eventually logs its result - not just
# that the function exists in source.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Mount step backgrounded (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$src = Get-FunctionSource -Content $content -Name 'Start-MountProjectBackground'
if (-not $src) {
    Write-Host "  FAIL  could not extract Start-MountProjectBackground - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($src))

Assert ($content -notmatch '(?ms)else \{\s*Step "Mounting files"\s*\$mountSW = \[System\.Diagnostics\.Stopwatch\]::StartNew\(\)\s*\$mountResult = Invoke-MountProject') `
    'FIXED: the slow-path branch no longer blocks on a synchronous Invoke-MountProject call'
Assert ($content -match 'Start-MountProjectBackground -ProjectId \$go\.Id') 'connect.ps1 call site kicks off the background mount'

$tmpLogDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-mountbg-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpLogDir | Out-Null
$sessionId = 'mountbgtest01'
# Deliberately unreachable SSH alias (never configured) - proves the KICKOFF is non-blocking
# regardless of what the real ssh call eventually does; the runner should still spawn and log a
# real failure asynchronously, which is exactly the "don't block, but don't lose the failure
# either" behavior this fix is supposed to provide.
$fakeAlias = 'claude-connect-test-unreachable-alias-does-not-exist'

try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = Start-MountProjectBackground -ProjectId 'live-test-project' -Alias $fakeAlias -LogDir $tmpLogDir -SessionId $sessionId
    $sw.Stop()
    Write-Host "  INFO  Start-MountProjectBackground call wall-clock: $($sw.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
    Assert ($ok -eq $true) 'Start-MountProjectBackground reports the background process was launched'
    Assert ($sw.ElapsedMilliseconds -lt 3000) "FIXED: the kickoff call itself returned in $($sw.ElapsedMilliseconds)ms - genuinely non-blocking (real ssh to an unreachable host would take far longer to fail)"

    $runnerDir = Join-Path $env:TEMP 'claude-connect-mountbg'
    $recentRunner = Get-ChildItem -LiteralPath $runnerDir -Filter 'mount-bg-*.ps1' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Assert ($null -ne $recentRunner) 'a real detached runner script file was actually written to disk'

    Write-Host "  INFO  waiting up to 20s for the real detached background process to log its result..." -ForegroundColor DarkGray
    $dayLog = Join-Path $tmpLogDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
    $found = $false
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw2.ElapsedMilliseconds -lt 20000 -and -not $found) {
        if (Test-Path -LiteralPath $dayLog) {
            $logContent = Get-Content -LiteralPath $dayLog -Raw -ErrorAction SilentlyContinue
            if ($logContent -match "\[$sessionId\] MOUNT_BG_(OK|FAIL|EXCEPTION)") { $found = $true; break }
        }
        Start-Sleep -Milliseconds 500
    }
    Assert $found "the real detached background process actually wrote a MOUNT_BG_* result line to the day log within 20s (session=$sessionId)"
    if ($found) {
        $matchedLine = (Get-Content -LiteralPath $dayLog | Select-String "\[$sessionId\] MOUNT_BG_(OK|FAIL|EXCEPTION)" | Select-Object -First 1).Line
        Write-Host "  INFO  logged result: $matchedLine" -ForegroundColor DarkGray
        Assert ($matchedLine -match 'MOUNT_BG_(FAIL|EXCEPTION)') 'against the deliberately-unreachable alias, the background process correctly logs a failure (not a false OK)'
    }
} finally {
    Remove-Item -LiteralPath $tmpLogDir -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $env:TEMP 'claude-connect-mountbg') -Filter 'mount-bg-*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) } | Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): mount step is genuinely backgrounded - kickoff is non-blocking, a real detached process runs and logs its real result.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
