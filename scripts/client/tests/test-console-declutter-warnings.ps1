# test-console-declutter-warnings.ps1 - user request (2026-07-24): two chronic WARN messages
# (xray proxy "international path down" and "Personal Cursor is open") printed to the console on
# a large fraction of sessions and were pure noise by then - confirm both are console-silent now
# while still fully recorded in the day log (Write-ConnectLog), not silently dropped.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Console decluttering: xray + personal-Cursor warnings ===' -ForegroundColor Cyan

$winContent = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$macContent = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

Assert ($winContent -notmatch "Write-Host [^\r\n]*international path down") 'Win: xray "international path down" no longer printed to console'
Assert ($winContent -match "Write-ConnectLog 'PROXY_HEALTH_UI international_path_down") 'Win: xray path still fully recorded in the day log (INFO)'

Assert ($winContent -notmatch "Warn 'Personal Cursor is open") 'Win: "Personal Cursor is open" no longer printed to console'
Assert ($winContent -match "Write-ConnectLog 'AUTH_WARN personal_cursor_dominant'") 'Win: personal-Cursor warning still fully recorded in the day log'

Assert ($macContent -notmatch "warn 'Personal Cursor is open") 'Mac: "Personal Cursor is open" no longer printed to console'
Assert ($macContent -match "connect_log 'AUTH_WARN personal_cursor_dominant'") 'Mac: personal-Cursor warning still fully recorded in the day log'

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): both chronic console warnings are quiet now, still fully logged.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
