# verify-cursor-auth-live.ps1 - end-to-end golden -> local merge (no token values printed)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Alias = 'claude-server'
function SshX([string]$Cmd) {
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 $Alias $Cmd
}

. (Get-ClientFile 'editor-launch.ps1')
. (Get-ClientFile 'cursor-auth-laptop.ps1')

$db = Join-Path (Get-CursorRemoteProfileDir) 'User\globalStorage\state.vscdb'
$before = if (Test-Path $db) { (Get-Item $db).Length } else { 0 }
Write-Host "BEFORE state.vscdb: $before bytes"

$golden = (SshX "test -f /etc/cursor-auth/golden/auth.json && echo yes" 2>$null) -join ''
if ($golden -notmatch 'yes') { Write-Host 'FAIL: no golden on server'; exit 1 }
Write-Host 'SERVER golden: ok'

$payload = Get-RemoteCursorAuthFromGolden -Alias $Alias
if (-not $payload) { Write-Host 'FAIL: could not fetch golden auth JSON'; exit 1 }
Write-Host 'FETCH golden JSON: ok'

$result = Sync-CursorGoldenAuth -Alias $Alias
Write-Host "SYNC result: Ok=$($result.Ok) Skipped=$($result.Skipped)"

$after = if (Test-Path $db) { (Get-Item $db).Length } else { 0 }
Write-Host "AFTER state.vscdb: $after bytes"

$ok = Test-LocalCursorAuthDb -DbPath $db
Write-Host "LOCAL verify tokens in db: $ok"

if ($result.Ok -and $ok) {
    Write-Host 'PASS live auth sync' -ForegroundColor Green
    exit 0
}
Write-Host 'FAIL live auth sync' -ForegroundColor Red
exit 1
