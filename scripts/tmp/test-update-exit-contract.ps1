# test-update-exit-contract.ps1 - ERROR paths must exit nonzero (Select-String contract)
$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
if ($PSScriptRoot) {
    $cand = Join-Path $PSScriptRoot '..\..'
    if (Test-Path (Join-Path $cand 'scripts\client\windows\connect-update.ps1')) {
        $repo = (Resolve-Path $cand).Path
    }
}
$ps1 = Join-Path $repo 'scripts\client\windows\connect-update.ps1'
$sh  = Join-Path $repo 'scripts\client\mac\connect-update.sh'
$fail = 0; $pass = 0
function Ok([string]$m) { $script:pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad([string]$m) { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }

Write-Host '=== Update ERROR exit contract ==='
Write-Host ("repo=$repo")
if (-not (Test-Path -LiteralPath $ps1)) { Bad "missing $ps1"; exit 1 }
if (-not (Test-Path -LiteralPath $sh))  { Bad "missing $sh"; exit 1 }

# 1) No ERROR; exit 0 on same line (PS)
$badSame = @(Select-String -LiteralPath $ps1 -Pattern "'ERROR'\s*;\s*exit\s+0")
if ($badSame.Count -eq 0) { Ok 'ps1: no ERROR; exit 0 same-line' } else {
  foreach ($h in $badSame) { Bad ("ps1:{0}: {1}" -f $h.LineNumber, $h.Line.Trim()) }
}

# 2) Known ERROR markers with exit 1 nearby (PS) — Select-String line then peek
$psLines = @(Get-Content -LiteralPath $ps1)
function Assert-ExitNonzeroNear {
    param([string]$Path,[object[]]$AllLines,[string]$Marker,[string]$Label)
    $hits = @(Select-String -LiteralPath $Path -SimpleMatch -Pattern $Marker)
    if ($hits.Count -eq 0) { Bad "$Label missing marker '$Marker'"; return }
    $ok = $false; $bad = $false
    foreach ($h in $hits) {
        $i = $h.LineNumber - 1
        $end = [Math]::Min($AllLines.Count-1, $i+5)
        $chunk = ($AllLines[$i..$end] -join "`n")
        if ($chunk -match '(?m)exit\s+0\b' -and $chunk -notmatch '(?m)exit\s+[1-9]') {
            # allow exit 0 only if also exit 1 in window? prefer strict
            if ($chunk -match '(?m)^\s*exit\s+0\s*$' -or $chunk -match ";\s*exit\s+0") {
                Bad ("{0}:{1}: '{2}' exits 0" -f $Label,$h.LineNumber,$Marker); $bad = $true; continue
            }
        }
        if ($chunk -match '(?m)exit\s+([1-9]\d*)\b' -or $h.Line -match 'exit 1') { $ok = $true }
    }
    if (-not $bad) {
        if ($ok) { Ok "$Label '$Marker' exits nonzero" } else { Bad "$Label '$Marker' no nonzero exit" }
    }
}

Assert-ExitNonzeroNear $ps1 $psLines 'ssh_missing' 'ps1'
Assert-ExitNonzeroNear $ps1 $psLines 'scp_missing' 'ps1'
Assert-ExitNonzeroNear $ps1 $psLines 'manifest_empty_or_unreachable' 'ps1'
Assert-ExitNonzeroNear $ps1 $psLines 'manifest_zero_files' 'ps1'
Assert-ExitNonzeroNear $ps1 $psLines 'download_failed' 'ps1'
Assert-ExitNonzeroNear $ps1 $psLines 'incomplete_files' 'ps1'
Assert-ExitNonzeroNear $ps1 $psLines 'apply_rollback' 'ps1'

# checksum_fail -> caller exit 1
$cs = @(Select-String -LiteralPath $ps1 -SimpleMatch -Pattern 'checksum_fail')
$call = @(Select-String -LiteralPath $ps1 -SimpleMatch -Pattern 'Test-BundleChecksums')
$csOk = $false
foreach ($c in $call) {
    if ($c.Line -match 'function') { continue }
    $i = $c.LineNumber - 1
    $chunk = ($psLines[$i..([Math]::Min($psLines.Count-1,$i+6))] -join "`n")
    if ($chunk -match '(?m)exit\s+1') { $csOk = $true }
}
if ($cs.Count -gt 0 -and $csOk) { Ok 'ps1 checksum_fail -> exit 1' } else { Bad 'ps1 checksum_fail path' }

$shLines = @(Get-Content -LiteralPath $sh)
Assert-ExitNonzeroNear $sh $shLines 'ssh_missing' 'sh'
Assert-ExitNonzeroNear $sh $shLines 'scp_missing' 'sh'
Assert-ExitNonzeroNear $sh $shLines 'manifest_empty' 'sh'
Assert-ExitNonzeroNear $sh $shLines 'download_failed' 'sh'
Assert-ExitNonzeroNear $sh $shLines 'incomplete_files' 'sh'
Assert-ExitNonzeroNear $sh $shLines 'apply_rollback' 'sh'
# checksum_fail logs inside _verify_checksums (returns); caller exits 1
$cf = @(Select-String -LiteralPath $sh -SimpleMatch -Pattern 'checksum_fail')
$cv = @(Select-String -LiteralPath $sh -SimpleMatch -Pattern '_verify_checksums')
$cfOk = $false
foreach ($c in $cv) {
    if ($c.Line -match '^_verify_checksums') { continue }
    $i = $c.LineNumber - 1
    $chunk = ($shLines[$i..([Math]::Min($shLines.Count-1,$i+6))] -join "`n")
    if ($chunk -match '(?m)exit\s+1') { $cfOk = $true }
}
if ($cf.Count -gt 0 -and $cfOk) { Ok 'sh checksum_fail -> exit 1 via caller' } else { Bad 'sh checksum_fail path' }

# soft-fail messages must not exit 0
foreach ($msg in @('Update incomplete','Update download failed','checksum failed','rolled back')) {
    $hits = @(Select-String -LiteralPath $sh -SimpleMatch -Pattern $msg)
    foreach ($h in $hits) {
        $i = $h.LineNumber - 1
        $chunk = ($shLines[$i..([Math]::Min($shLines.Count-1,$i+6))] -join "`n")
        if ($chunk -match '(?m)^\s*exit\s+0\s*$') { Bad ("sh:{0}: '{1}' exit 0" -f $h.LineNumber,$msg) }
        elseif ($chunk -match '(?m)^\s*exit\s+[1-9]') { Ok ("sh:{0}: '{1}' nonzero" -f $h.LineNumber,$msg) }
    }
}

Write-Host ''
Write-Host ("contract: {0} pass, {1} fail" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
