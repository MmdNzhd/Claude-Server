# test-cursor-auth-merge.ps1 — verify auth sync never closes Cursor
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$authScript = Join-Path $PSScriptRoot '..\cursor-auth-laptop.ps1'
$src = Get-Content $authScript -Raw
Assert ($src -match 'Merge-CursorAuthIntoLocalDb') 'uses SQLite merge'
Assert ($src -notmatch 'Stop-Cursor|CloseMainWindow|Stop-Process') 'no close/kill'
Assert ($src -notmatch 'Remove-Item.*wal|wal.*Remove-Item') 'does not delete WAL files'
Assert ($src -match 'Get-RemoteCursorAuthFromGolden') 'reads auth from golden bundle'
Assert ($src -match 'golden/storage.json') 'storage merge from golden'

$winConnect = Get-Content (Join-Path $PSScriptRoot '..\windows\connect.ps1') -Raw
Assert ($winConnect -match 'Sync-CursorGoldenAuth -Alias \$Alias') 'auth sync on every mount'
Assert ($winConnect -match 'if \(-not \$editorOpened\)') 'editor opens only once'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All cursor-auth merge tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
