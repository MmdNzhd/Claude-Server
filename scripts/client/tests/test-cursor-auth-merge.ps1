# test-cursor-auth-merge.ps1 - verify auth sync never closes Cursor
$ErrorActionPreference = 'Continue'
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$authScript = Join-Path $PSScriptRoot '..\cursor-auth-laptop.ps1'
$src = Get-Content $authScript -Raw
Assert ($src -match 'Merge-CursorAuthIntoLocalDb') 'uses SQLite merge'
Assert ($src -match 'winsqlite3|CursorAuthSqlite') 'uses winsqlite3 via C# P/Invoke'
Assert ($src -notmatch 'Resolve-CursorAuthPython|Invoke-CursorAuthPython|python3 /usr/local') 'no Python dependency'
Assert ($src -notmatch 'Stop-Cursor|CloseMainWindow|Stop-Process') 'no close/kill'
Assert ($src -notmatch 'Remove-Item.*wal|wal.*Remove-Item') 'does not delete WAL files'
Assert ($src -match 'Get-RemoteCursorAuthFromGolden') 'reads auth from golden bundle'
Assert ($src -match 'golden/storage.json') 'storage merge from golden'
Assert ($src -notmatch 'wal_checkpoint\(FULL\)') 'auth merge does not force WAL checkpoint'
Assert ($src -match 'Write-CursorProfileMachineId') 'writes Electron machineid file'
Assert ($src -match 'machineid healed') 'skip path still heals machineid'
Assert ($src -match 'AlreadyComplete') 'auth sync skips when local tokens complete'
Assert ($src -match 'Repair-CursorComposerWorkspaceBindings') 'auth can repair composer workspace links'
Assert ($src -match 'function Get-CursorAuthTempRoot') 'uses Get-CursorAuthTempRoot for temp dirs'
Assert ($src -match 'function Remove-CursorAuthTempDir') 'uses Remove-CursorAuthTempDir for cleanup'
Assert ($src -match 'golden-synced-at\.txt') 'stamps/reads golden-synced-at'
Assert ($src -match 'golden_stale') 'needs-refresh detects golden rotation'
Assert ($src -match 'machineid_file_mismatch') 'needs-refresh detects machineid file drift'
Assert ($src -match 'Keep auth.json metadata on early') 'early merge keeps email/stripe metadata'
Assert ($src -notmatch 'Remove-Item \$tmp') 'no bare Remove-Item $tmp (8.3 TEMP trap)'
Assert ($src -match 'function Test-CursorAuthNeedsRefresh') 'cursor-auth-laptop has Test-CursorAuthNeedsRefresh'
Assert ($src -match 'serviceMachineId_empty') 'Test-CursorAuthNeedsRefresh checks serviceMachineId'
Assert ($src -match 'AUTH ERROR') 'logs AUTH ERROR on refresh failures'

$winConnect = Get-Content (Join-Path $PSScriptRoot '..\windows\connect.ps1') -Raw
Assert ($winConnect -match 'Sync-CursorGoldenAuth -Alias \$Alias') 'auth sync on every mount'
Assert ($winConnect -match 'skipped \(editor open\)') 'auth sync skipped while Cursor open'
Assert ($winConnect -match "action -eq 'o'") 'session can reopen editor with O'
Assert ($winConnect -match 'Begin-ConnectRecovery') 'connect.ps1 resets auth on recovery'
Assert ($winConnect -match 'ForceCursorAuthSync') 'connect.ps1 force auth after recovery'
Assert ($winConnect -match 'AuthRelaunch') 'connect can auth-relaunch editor'
Assert ($winConnect -match 'auth_relaunch despite already_on_folder') 'auth relaunch works when already on folder'

$macConnect = Get-Content (Join-Path $PSScriptRoot '..\mac\connect.sh') -Raw
Assert ($macConnect -match '_on_folder_now') 'Mac O allows reopen when sticky not on folder'
Assert ($macConnect -match 'Reloading \$EDITOR_NAME \(auth refresh\)') 'Mac relaunches when AUTH_RELAUNCH set'
$skippedBlock = [regex]::Match($macConnect, '(?ms)skipped\)\s*\n.*?;;')
Assert ($skippedBlock.Success) 'Mac has skipped auth case'
Assert ($skippedBlock.Value -notmatch 'CURSOR_AUTH_RELAUNCH=1') 'Mac skipped auth does not set AUTH_RELAUNCH'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All cursor-auth merge tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
