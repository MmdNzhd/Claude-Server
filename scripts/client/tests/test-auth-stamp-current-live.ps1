# test-auth-stamp-current-live.ps1 - LIVE: proves Test-CursorAuthStampCurrent
# never invents Current=true from file mtime alone (account-rotation safe).
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

# Stub SSH stamp fetch.
$script:StampStubValue = ''
$script:StampStubCalls = 0
function Get-CursorGoldenExportedAtStamp {
    param([Parameter(Mandatory)][string]$Alias)
    $script:StampStubCalls++
    return $script:StampStubValue
}

. ([scriptblock]::Create($src))

# Must NOT contain the old mtime-only local_ttl fast path.
Assert ($src -notmatch 'local_ttl') 'source no longer uses mtime-only local_ttl short-circuit'
Assert ($src -match 'session_cache') 'source uses session_cache only when CursorGoldenStampCache matches'

$fakeGs = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-authstamp-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $fakeGs | Out-Null
$dbPath = Join-Path $fakeGs 'state.vscdb'
$stampPath = Join-Path $fakeGs 'golden-synced-at.txt'
$alias = 'live-test-alias'

try {
    # --- Scenario 1: fresh stamp file alone MUST still SSH (no invent Current=true) ---
    Set-Content -LiteralPath $stampPath -Value 'STAMP-FRESH' -Encoding ASCII -NoNewline
    $script:CursorGoldenStampCache = $null
    $script:StampStubValue = 'STAMP-SERVER-NEW'
    $script:StampStubCalls = 0

    $r1 = Test-CursorAuthStampCurrent -DbPath $dbPath -Alias $alias
    Assert ($r1.Current -eq $false) 'fresh stamp without session cache + mismatched server: Current=false'
    Assert ($r1.Source -eq 'ssh') 'falls through to SSH compare'
    Assert ($r1.SyncedAt -eq 'STAMP-FRESH') 'SyncedAt from file'
    Assert ($r1.GoldenExportedAt -eq 'STAMP-SERVER-NEW') 'GoldenExportedAt from stub SSH'
    Assert ($script:StampStubCalls -eq 1) 'SSH stamp fetch called once'

    # --- Scenario 2: session cache matching local stamp -> Current=true, no SSH ---
    $script:CursorGoldenStampCache = @{ Stamp = 'STAMP-FRESH'; At = (Get-Date) }
    $script:StampStubCalls = 0
    $r2 = Test-CursorAuthStampCurrent -DbPath $dbPath -Alias $alias
    Assert ($r2.Current -eq $true) 'session_cache match: Current=true'
    Assert ($r2.Source -eq 'session_cache') 'Source=session_cache'
    Assert ($script:StampStubCalls -eq 0) 'session_cache does not call SSH stamp fetch'

    # --- Scenario 3: session cache mismatch forces SSH ---
    $script:CursorGoldenStampCache = @{ Stamp = 'STAMP-OLD-CACHE'; At = (Get-Date) }
    $script:StampStubValue = 'STAMP-FRESH'
    $script:StampStubCalls = 0
    $r3 = Test-CursorAuthStampCurrent -DbPath $dbPath -Alias $alias
    Assert ($r3.Current -eq $true) 'cache mismatch but SSH matches file: Current=true'
    Assert ($r3.Source -eq 'ssh') 'cache mismatch falls through to ssh'
    Assert ($script:StampStubCalls -eq 1) 'SSH called when cache does not match local stamp'
} finally {
    Remove-Item -LiteralPath $fakeGs -Recurse -Force -ErrorAction SilentlyContinue
}

Assert (-not (Test-Path -LiteralPath $fakeGs)) 'isolated fake globalStorage temp dir was fully removed after the run'

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
