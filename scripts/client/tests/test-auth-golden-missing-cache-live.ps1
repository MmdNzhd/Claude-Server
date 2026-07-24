#Requires -Version 5.1
# test-auth-golden-missing-cache-live.ps1 - LIVE: the "golden auth known missing" negative
# cache (scripts/client/cursor-auth-laptop.ps1) must actually skip repeat SSH round trips
# while cached, self-heal once the short TTL window expires (no client restart required),
# and clear cleanly on demand - exercising the real functions against an isolated fake
# global-storage directory (never touches the real local Cursor global storage on this box).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Cursor golden-auth known-missing cache (LIVE) ===' -ForegroundColor Cyan

# cursor-auth-laptop.ps1 lives directly under scripts/client/ (not scripts/client/windows/).
$content = Get-Content (Get-ClientFile 'cursor-auth-laptop.ps1') -Raw

# Real short-TTL constant the production code checks against - read it out of the source
# instead of hardcoding a duplicate value, so this test tracks the real code if it changes.
$ttlMatch = [regex]::Match($content, '\$script:CursorGoldenMissingTtlMin\s*=\s*(\d+)')
if (-not $ttlMatch.Success) {
    Write-Host '  FAIL  could not find $script:CursorGoldenMissingTtlMin in source - live test cannot run (source drifted)' -ForegroundColor Red
    exit 1
}
$ttlMin = [int]$ttlMatch.Groups[1].Value

# Real function names in source are Test-CursorGoldenKnownMissing / Set-CursorGoldenMissingCache /
# Clear-CursorGoldenMissingCache (the cache-suffixed setter/clearer names, not
# Set-/Clear-CursorGoldenKnownMissing) - confirmed directly against the shipped source below.
foreach ($n in @('Test-CursorGoldenKnownMissing', 'Set-CursorGoldenMissingCache', 'Clear-CursorGoldenMissingCache')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}
$script:CursorGoldenMissingTtlMin = $ttlMin

# Stub the location-resolving dependency so these live functions run standalone against an
# isolated fake directory, without loading cursor-auth-laptop.ps1's full module (SQLite P/Invoke
# type init, SshX/remote helpers, etc). Defined AFTER the real functions are dot-sourced above -
# PowerShell resolves Get-LocalCursorGlobalStorage by name at call time, so this override wins
# without needing to touch the real Get-CursorRemoteProfileDir/global storage path at all.
$fakeGs = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-golden-missing-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
function Get-LocalCursorGlobalStorage { return $fakeGs }

try {
    New-Item -ItemType Directory -Force -Path $fakeGs | Out-Null
    $cachePath = Join-Path $fakeGs 'golden-missing-checked-at.txt'

    Assert ($cachePath -like "$fakeGs*") 'cache path is derived from the (isolated, fake) global storage dir - will not touch the real Cursor global storage'
    Assert (-not (Test-Path -LiteralPath $cachePath)) 'no stale cache file pre-existing in the fresh fake global storage dir'
    Assert (-not (Test-CursorGoldenKnownMissing)) 'fresh state: golden auth not known-missing (a real probe would still be attempted)'

    Set-CursorGoldenMissingCache
    Assert (Test-Path -LiteralPath $cachePath) 'Set-CursorGoldenMissingCache actually wrote the cache file to real disk'
    Assert (Test-CursorGoldenKnownMissing) 'immediately after caching, known-missing correctly reports true (repeat SSH probe would be skipped)'

    # Self-healing edge case: force the cache file's real on-disk timestamp past the real TTL
    # constant (the production code keys off LastWriteTime, not an in-file field) and confirm
    # the cache stops suppressing the probe on its own - no client restart required.
    $expiredItem = Get-Item -LiteralPath $cachePath
    $expiredItem.LastWriteTime = (Get-Date).AddMinutes(-($ttlMin + 5))
    $ageMin = ((Get-Date) - (Get-Item -LiteralPath $cachePath).LastWriteTime).TotalMinutes
    Assert ($ageMin -ge $ttlMin) "cache file timestamp really was pushed past the $ttlMin-minute TTL on disk (age=$([math]::Round($ageMin,1))min)"
    Assert (-not (Test-CursorGoldenKnownMissing)) 'an expired cache window self-heals: no longer known-missing (a real admin fix - cursor-auth-export - would be picked up again without a client restart)'

    Set-CursorGoldenMissingCache
    Assert (Test-CursorGoldenKnownMissing) 're-armed after a fresh miss'
    Clear-CursorGoldenMissingCache
    Assert (-not (Test-Path -LiteralPath $cachePath)) 'Clear-CursorGoldenMissingCache actually deletes the cache file from real disk'
    Assert (-not (Test-CursorGoldenKnownMissing)) 'post-clear: no longer known-missing (a real probe would fire again on next connect)'
} finally {
    Remove-Item -LiteralPath $fakeGs -Recurse -Force -ErrorAction SilentlyContinue
    Assert (-not (Test-Path -LiteralPath $fakeGs)) 'fake global storage dir cleaned up after the run (no leftovers on real disk)'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
