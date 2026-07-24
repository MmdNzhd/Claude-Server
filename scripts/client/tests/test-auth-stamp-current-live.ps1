# test-auth-stamp-current-live.ps1 - LIVE: proves the real Test-CursorAuthStampCurrent
# function (scripts/client/cursor-auth-laptop.ps1) correctly decides whether a local
# "golden-synced-at.txt" stamp is current, using REAL file timestamps in a REAL isolated
# temp directory standing in for the Cursor globalStorage dir (never touches any real
# Cursor profile or real stamp file on this machine).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Cursor auth stamp currency Test-CursorAuthStampCurrent (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'cursor-auth-laptop.ps1') -Raw
$src = Get-FunctionSource -Content $content -Name 'Test-CursorAuthStampCurrent'
if (-not $src) {
    Write-Host "  FAIL  could not extract Test-CursorAuthStampCurrent - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}

# The real function calls Get-CursorGoldenExportedAtStamp -Alias $Alias when the local
# stamp is missing/expired. Stub it (not extracted from source) so this test controls the
# "SSH-checked" exported-at value per scenario without any real SshX/SSH round trip.
$script:StampStubValue = ''
$script:StampStubCalls = 0
function Get-CursorGoldenExportedAtStamp {
    param([Parameter(Mandatory)][string]$Alias)
    $script:StampStubCalls++
    return $script:StampStubValue
}

. ([scriptblock]::Create($src))

# TTL is hard-coded inline in the real function as 60 minutes ("$ageMin -ge 0 -and $ageMin -lt 60"),
# not a separate named constant - read directly from source, do not assume/hardcode independently.
$ttlMatch = [regex]::Match($src, '-lt\s+(\d+)\s*\)\s*\{\s*\r?\n\s*return')
if (-not $ttlMatch.Success) {
    Write-Host "  FAIL  could not read TTL constant from source - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}
$ttlMinutes = [int]$ttlMatch.Groups[1].Value
Write-Host "  (using TTL=$ttlMinutes minutes read from real source)" -ForegroundColor DarkGray

$fakeGs = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-authstamp-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $fakeGs | Out-Null
$dbPath = Join-Path $fakeGs 'state.vscdb'
$stampPath = Join-Path $fakeGs 'golden-synced-at.txt'
$alias = 'live-test-alias'

try {
    # --- Scenario 1: fresh real LastWriteTime (now) -> local_ttl fast path, no SSH stub call ---
    Set-Content -LiteralPath $stampPath -Value 'STAMP-FRESH' -Encoding ASCII -NoNewline
    $script:StampStubValue = 'SHOULD-NOT-BE-USED'
    $script:StampStubCalls = 0

    $r1 = Test-CursorAuthStampCurrent -DbPath $dbPath -Alias $alias
    Assert ($r1.Current -eq $true) 'fresh real stamp (age ~0min < TTL): Current=true (local fast path)'
    Assert ($r1.Source -eq 'local_ttl') 'fresh real stamp reports Source=local_ttl (matches real code)'
    Assert ($r1.SyncedAt -eq 'STAMP-FRESH') 'SyncedAt reflects the real file content just written'
    Assert ($r1.GoldenExportedAt -eq 'STAMP-FRESH') 'local_ttl path echoes SyncedAt back as GoldenExportedAt'
    Assert ($script:StampStubCalls -eq 0) 'local_ttl short-circuit never calls Get-CursorGoldenExportedAtStamp (no SSH round trip needed)'

    # --- Scenario 2: age the SAME real file past TTL, stub returns a MISMATCHING exported-at ---
    $agedTime = (Get-Date).AddMinutes(-($ttlMinutes + 5))
    (Get-Item -LiteralPath $stampPath).LastWriteTime = $agedTime
    $script:StampStubValue = 'STAMP-DIFFERENT'

    $r2 = Test-CursorAuthStampCurrent -DbPath $dbPath -Alias $alias
    Assert ($r2.Current -eq $false) "stamp aged past TTL ($($ttlMinutes + 5)min) + SSH-checked exported-at mismatch: Current=false"
    Assert ($r2.Source -eq 'ssh') 'expired local stamp falls through to Source=ssh (matches real code)'
    Assert ($r2.SyncedAt -eq 'STAMP-FRESH') 'SyncedAt still reflects the real (unchanged) file content'
    Assert ($r2.GoldenExportedAt -eq 'STAMP-DIFFERENT') 'GoldenExportedAt reflects the stubbed SSH-checked value'
    Assert ($script:StampStubCalls -eq 1) 'expired stamp path does call Get-CursorGoldenExportedAtStamp exactly once'

    # --- Scenario 3: same aged real file, stub now returns a MATCHING exported-at ---
    $script:StampStubValue = 'STAMP-FRESH'

    $r3 = Test-CursorAuthStampCurrent -DbPath $dbPath -Alias $alias
    Assert ($r3.Current -eq $true) 'stamp aged past TTL but SSH-checked exported-at now matches recorded SyncedAt: Current=true'
    Assert ($r3.Source -eq 'ssh') 'matching-but-expired path also reports Source=ssh (checked via ssh)'
    Assert ($r3.SyncedAt -eq 'STAMP-FRESH') 'SyncedAt unchanged'
    Assert ($r3.GoldenExportedAt -eq 'STAMP-FRESH') 'GoldenExportedAt reflects the now-matching stubbed SSH value'
    Assert ($script:StampStubCalls -eq 2) 'second expired-path call also went through Get-CursorGoldenExportedAtStamp'
} finally {
    Remove-Item -LiteralPath $fakeGs -Recurse -Force -ErrorAction SilentlyContinue
}

Assert (-not (Test-Path -LiteralPath $fakeGs)) 'isolated fake globalStorage temp dir was fully removed after the run'

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
