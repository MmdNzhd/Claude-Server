# test-connect-update-fail-exit.ps1 - ERROR paths must exit nonzero (not look up-to-date)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== connect-update ERROR -> nonzero exit ===' -ForegroundColor Cyan

$win = Get-Content (Get-ClientFile 'windows\connect-update.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect-update.sh') -Raw

# Windows: every Write-UpdateFileLog ... 'ERROR' must be followed by exit 1 (or exit nonzero) before next success path.
$errorHits = [regex]::Matches($win, "Write-UpdateFileLog\s+(?:'([^']+)'|\(([^)]+)\))\s+'ERROR'")
Assert ($errorHits.Count -ge 4) ("Win update has ERROR log sites (found {0})" -f $errorHits.Count)

foreach ($m in $errorHits) {
    $label = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
    $start = $m.Index + $m.Length
    $window = $win.Substring($start, [Math]::Min(180, $win.Length - $start))
    # Same-line or next statement must exit nonzero (not exit 0).
    $ok = ($window -match 'exit\s+1\b') -or ($window -match 'exit\s+\$') -or ($window -match 'throw\b')
    $bad = ($window -match 'exit\s+0\b')
    Assert ($ok -and -not $bad) ("Win ERROR '$label' exits nonzero soon after (no exit 0)")
}

# Named failure paths (download / incomplete) explicitly exit 1.
Assert ($win -match "download_failed' 'ERROR'[\s\S]{0,120}?exit 1") 'Win download_failed -> exit 1'
Assert ($win -match "incomplete_files=[\s\S]{0,120}?exit 1") 'Win incomplete_files -> exit 1'
Assert ($win -match "manifest_empty_or_unreachable' 'ERROR'; exit 1") 'Win manifest_empty -> exit 1'
Assert ($win -match "manifest_zero_files' 'ERROR'; exit 1") 'Win manifest_zero -> exit 1'

# Success relaunch path still exit 2.
Assert ($win -match 'applied_ok need_relaunch exit=2') 'Win applied_ok still signals exit 2'
Assert ($win -match 'exit 2') 'Win has exit 2 relaunch'

# Mac: download/incomplete/manifest ERROR -> exit 1
Assert ($mac -match 'download_failed[\s\S]{0,80}?exit 1') 'Mac download_failed -> exit 1'
Assert ($mac -match 'incomplete_files[\s\S]{0,80}?exit 1') 'Mac incomplete_files -> exit 1'
Assert ($mac -match 'manifest_empty_or_unreachable[\s\S]{0,80}?exit 1') 'Mac manifest_empty -> exit 1'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All update fail-exit tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
