# test-auth-temp-contracts.ps1 - HARD contracts for Cursor auth TEMP + merge
# Exit 0 = all pass; exit 1 = any HARD FAIL
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $Root 'scripts/client/cursor-auth-laptop.ps1'))) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$AuthPs1 = Join-Path $Root 'scripts/client/cursor-auth-laptop.ps1'
if (-not (Test-Path -LiteralPath $AuthPs1)) {
    Write-Host 'FAIL: cursor-auth-laptop.ps1 missing'
    exit 1
}

$src = Get-Content -LiteralPath $AuthPs1 -Raw -Encoding UTF8
$fails = New-Object System.Collections.Generic.List[string]
$passes = New-Object System.Collections.Generic.List[string]

function Assert-Pass([string]$Msg) {
    $script:passes.Add($Msg) | Out-Null
    Write-Host "  PASS  $Msg"
}
function Assert-Fail([string]$Msg) {
    $script:fails.Add($Msg) | Out-Null
    Write-Host "  FAIL  $Msg"
}

Write-Host ''
Write-Host '=== Auth TEMP + merge contracts ==='
Write-Host ''

# 1. Helpers must exist
if ($src -match '(?m)^function Get-CursorAuthTempRoot\b') {
    Assert-Pass 'Get-CursorAuthTempRoot exists'
} else {
    Assert-Fail 'Get-CursorAuthTempRoot must exist'
}
if ($src -match '(?m)^function Remove-CursorAuthTempDir\b') {
    Assert-Pass 'Remove-CursorAuthTempDir exists'
} else {
    Assert-Fail 'Remove-CursorAuthTempDir must exist'
}

# 2. Get-RemoteCursorAuthFromGolden finally must call Remove-CursorAuthTempDir
$fnMatch = [regex]::Match(
    $src,
    '(?s)function Get-RemoteCursorAuthFromGolden\s*\{.*?^\}\s*(?=function |\z)',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
if (-not $fnMatch.Success) {
    Assert-Fail 'Get-RemoteCursorAuthFromGolden function not found'
} else {
    $body = $fnMatch.Value
    if ($body -match 'finally\s*\{[^}]*Remove-CursorAuthTempDir\s+-Path\s+\$tmp') {
        Assert-Pass 'Get-RemoteCursorAuthFromGolden finally calls Remove-CursorAuthTempDir'
    } else {
        Assert-Fail 'Get-RemoteCursorAuthFromGolden finally must call Remove-CursorAuthTempDir -Path $tmp'
    }
    if ($body -match 'Remove-Item\s+[^\n]*\$tmp[^\n]*-Recurse') {
        Assert-Fail 'Get-RemoteCursorAuthFromGolden must not bare Remove-Item -Recurse $tmp'
    } else {
        Assert-Pass 'Get-RemoteCursorAuthFromGolden has no bare Remove-Item -Recurse $tmp'
    }
}

# 3. Any Remove-Item $tmp -Recurse in file = FAIL (file -Force merge-src OK)
$recurseHits = [regex]::Matches($src, '(?m)Remove-Item[^\n]*\$tmp[^\n]*-Recurse[^\n]*')
$bad = @()
foreach ($m in $recurseHits) {
    $line = $m.Value
    # Allow only inside Remove-CursorAuthTempDir (uses -LiteralPath $Path, not $tmp)
    if ($line -match '\$tmp') { $bad += $line.Trim() }
}
if ($bad.Count -eq 0) {
    Assert-Pass 'No Remove-Item $tmp -Recurse in cursor-auth-laptop.ps1'
} else {
    foreach ($b in $bad) { Assert-Fail "Remove-Item `$tmp -Recurse found: $b" }
}

# File merge-src Remove-Item $tmp -Force (no -Recurse) is OK
$mergeSrcForce = [regex]::Matches($src, '(?m)Remove-Item\s+\$tmp\s+-Force')
if ($mergeSrcForce.Count -ge 1) {
    Assert-Pass "File merge-src Remove-Item `$tmp -Force allowed ($($mergeSrcForce.Count) hit(s))"
}

# 4. golden-synced-at or equivalent rotation check on Win skip path
$hasSyncedAt = $src -match 'golden-synced-at'
$hasRotation = $src -match 'goldenExportedAt|exported-at|goldenCurrent|syncedAt\s*-eq'
$hasSkipComplete = $src -match 'skip already complete|AlreadyComplete|path=skip_already_complete'
if ($hasSyncedAt -and $hasRotation) {
    Assert-Pass 'golden-synced-at + rotation check present on Win skip path'
} elseif ($hasSyncedAt) {
    Assert-Fail 'golden-synced-at present but rotation/exported-at compare missing'
} else {
    Assert-Fail 'golden-synced-at or equivalent rotation stamp missing on Win skip path'
}
if ($hasSkipComplete) {
    Assert-Pass 'Win skip-already-complete path present'
} else {
    Assert-Fail 'Win skip-already-complete path missing'
}

Write-Host ''
Write-Host "Passed: $($passes.Count)  Failed: $($fails.Count)"
if ($fails.Count -gt 0) {
    Write-Host 'HARD FAIL: auth temp contracts'
    exit 1
}
Write-Host 'All auth temp contracts passed.'
exit 0
