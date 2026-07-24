# test-update-check-failfast.ps1 - #P1 connect-version.txt check must not re-pay the full
# SSH resolution cost (primary + up to 2 fallback identities, 3 retries each - observed up
# to 62s) on every single launch when the server bundle is known-missing/unreachable.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Update-check fail-fast cache #P1 (static) ===' -ForegroundColor Cyan

$s = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw

Assert ($s -match 'function Get-UpdateMissCachePath') 'Get-UpdateMissCachePath defined'
Assert ($s -match 'function Test-UpdateCheckRecentlyMissed') 'Test-UpdateCheckRecentlyMissed defined'
Assert ($s -match 'function Save-UpdateCheckMiss') 'Save-UpdateCheckMiss defined'
Assert ($s -match 'function Clear-UpdateCheckMiss') 'Clear-UpdateCheckMiss defined'
Assert ($s -match [regex]::Escape('.config\claude-connect') -and $s -match 'update-check-miss\.txt') 'cache lives alongside other per-user connect config (not a new ad-hoc location)'

$resolveIdx = $s.IndexOf('$resolved = Resolve-UpdateEndpoint')
Assert ($resolveIdx -ge 0) 'Resolve-UpdateEndpoint call site found'
if ($resolveIdx -ge 0) {
    $before = $s.Substring([Math]::Max(0, $resolveIdx - 200), 200)
    Assert ($before -match 'Test-UpdateCheckRecentlyMissed') 'cache is checked BEFORE attempting SSH resolution (skips the whole retry dance)'
    $after = $s.Substring($resolveIdx, [Math]::Min(700, $s.Length - $resolveIdx))
    Assert ($after -match 'Save-UpdateCheckMiss') 'a fresh miss gets cached for next launch'
    Assert ($after -match 'Clear-UpdateCheckMiss') 'a success clears any stale miss cache (self-healing once server is reachable again)'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
