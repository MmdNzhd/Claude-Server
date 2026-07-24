# test-update-check-failfast-live.ps1 - #P1 LIVE: fail-fast update-check cache must actually
# skip repeat work while cached, self-heal once the cached window expires, and fail open on
# malformed data - exercising the real functions against an isolated fake $env:USERPROFILE
# (never touches the real user cache).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Update-check fail-fast cache #P1 (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
foreach ($n in @('Get-UpdateMissCachePath', 'Test-UpdateCheckRecentlyMissed', 'Save-UpdateCheckMiss', 'Clear-UpdateCheckMiss')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Stub the logger dependency so these live functions run standalone, without loading
# connect-update.ps1's full UI module (WinForms progress bar, etc).
function Write-UpdateFileLog { param([string]$Msg, [string]$Level = 'INFO') }

$fakeHome = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-p1-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $fakeHome | Out-Null
$origUserProfile = $env:USERPROFILE
$env:USERPROFILE = $fakeHome

try {
    $cachePath = Get-UpdateMissCachePath
    Assert ($cachePath -like "$fakeHome*") 'cache path is derived from (isolated, fake) USERPROFILE - will not touch the real user cache'
    Assert (-not (Test-Path -LiteralPath $cachePath)) 'no stale cache file pre-existing in the fresh fake home'
    Assert (-not (Test-UpdateCheckRecentlyMissed)) 'fresh state: not recently missed (a real check would be attempted)'

    Save-UpdateCheckMiss -Hours 6 -Reason 'live_test_miss'
    Assert (Test-Path -LiteralPath $cachePath) 'Save-UpdateCheckMiss actually wrote the cache file to disk'
    Assert (Test-UpdateCheckRecentlyMissed) 'immediately after a miss, cache correctly reports recently-missed (skip-check path would fire)'

    # Self-healing edge case the old static test never exercised: force the cached window to
    # have already expired and confirm the cache stops suppressing checks on its own.
    $expired = (Get-Date).ToUniversalTime().AddHours(-1).ToString('o')
    "until=$expired`nreason=live_test_expired" | Set-Content -LiteralPath $cachePath -Encoding UTF8
    Assert (-not (Test-UpdateCheckRecentlyMissed)) 'an expired cache window self-heals: no longer suppresses the check (a real server fix would be picked up again without a client restart)'

    Save-UpdateCheckMiss -Hours 6 -Reason 'live_test_miss_2'
    Assert (Test-UpdateCheckRecentlyMissed) 're-armed after a fresh miss'
    Clear-UpdateCheckMiss
    Assert (-not (Test-Path -LiteralPath $cachePath)) 'Clear-UpdateCheckMiss actually deletes the cache file'
    Assert (-not (Test-UpdateCheckRecentlyMissed)) 'post-clear: no longer suppressing checks (a success path re-enables real probing on next launch)'

    # Malformed cache file must fail open (never suppress the real update check on garbage data).
    'garbage not a valid until= line' | Set-Content -LiteralPath $cachePath -Encoding UTF8
    Assert (-not (Test-UpdateCheckRecentlyMissed)) 'malformed cache content fails open (does not falsely suppress checks)'
} finally {
    $env:USERPROFILE = $origUserProfile
    Remove-Item -LiteralPath $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
