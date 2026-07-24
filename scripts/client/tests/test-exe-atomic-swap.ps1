# test-exe-atomic-swap.ps1 - #P6 Sync-ConnectExeBesideClient used a plain Copy-Item -Force
# onto Desktop\Claude-Connect.exe, which silently fails ("exe_promote_fail") whenever that
# exact file is the one currently running (the user launched via the Desktop exe/shortcut) -
# Windows denies content-overwrite of a mapped/running executable. Rename-swap (move the
# running file aside, then copy the new build into the freed path) fixes it.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== EXE atomic rename-swap #P6 (static) ===' -ForegroundColor Cyan

$s = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw

Assert ($s -match 'function Copy-ExeAtomicSwap') 'Copy-ExeAtomicSwap helper defined'
$fnIdx = $s.IndexOf('function Copy-ExeAtomicSwap')
if ($fnIdx -ge 0) {
    $nextFn = $s.IndexOf("`nfunction ", $fnIdx + 40)
    $body = if ($nextFn -gt $fnIdx) { $s.Substring($fnIdx, $nextFn - $fnIdx) } else { $s.Substring($fnIdx) }
    Assert ($body -match 'Get-SafeFileSha256 \$Source\)\s*-eq\s*\(Get-SafeFileSha256 \$Destination\)') 'skips the copy entirely when source/dest already match (avoids needless rename dance)'
    Assert ($body -match 'Copy-Item .*-ErrorAction Stop') 'tries a normal Copy-Item first (fast path when the file is not locked)'
    Assert ($body -match 'Rename-Item') 'falls back to renaming the locked destination out of the way'
    Assert ($body -match [regex]::Escape('$Destination.old-')) 'renamed-aside file uses a distinct .old- suffix (not silently dropped)'
    Assert ($body -match 'Remove-Item -LiteralPath \$old -Force -ErrorAction SilentlyContinue') 'best-effort cleanup of the renamed-aside old file (ok if still locked)'
    Assert ($body -match 'return \$true' -and $body -match 'return \$false') 'returns a clear success/failure signal to the caller'
}

Assert ($s -match 'function Sync-ConnectExeBesideClient') 'Sync-ConnectExeBesideClient still defined'
$syncIdx = $s.IndexOf('function Sync-ConnectExeBesideClient')
if ($syncIdx -ge 0) {
    $nextFn2 = $s.IndexOf("`nfunction ", $syncIdx + 40)
    $syncBody = if ($nextFn2 -gt $syncIdx) { $s.Substring($syncIdx, $nextFn2 - $syncIdx) } else { $s.Substring($syncIdx) }
    Assert ($syncBody -match 'Copy-ExeAtomicSwap -Source \$exe -Destination \$desk') 'Desktop mirror now goes through the atomic-swap helper'
    Assert ($syncBody -match 'Copy-ExeAtomicSwap -Source \$exe -Destination \$setup') 'Setup mirror now goes through the atomic-swap helper'
    Assert ($syncBody -match 'Resolve-Path .*\$exe.*Resolve-Path .*\$desk' -or $syncBody -match '\(Resolve-Path -LiteralPath \$exe') 'guards against copying the exe onto itself (self-referential running-from-Desktop case)'
    Assert ($syncBody -notmatch 'Copy-Item -LiteralPath \$exe -Destination \$desk -Force -ErrorAction SilentlyContinue') 'old unconditional Copy-Item (no lock fallback) removed from the Desktop mirror path'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
