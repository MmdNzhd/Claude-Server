#Requires -Version 5.1
# Stage 4: poll loop and recovery both use presence; WindowOpen gate not used in recovery.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Stage 4: presence recovery parity ===' -ForegroundColor White
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

Assert ($win -match 'Get-RemoteEditorSessionPresence') 'connect.ps1 references presence API'
# Poll loop comment/WS5
Assert ($win -match 'single-pass presence query') 'Poll loop documents single-pass presence'

$rec = [regex]::Match($win, '(?s)\$skipRecoveryClear = \$false.*?Reason ''auto_recovery''').Value
Assert ($rec.Length -gt 100) 'Recovery block extractable'
Assert ($rec -match 'Get-RemoteEditorSessionPresence') 'Recovery uses presence (parity with poll)'
Assert ($rec -notmatch 'Test-RemoteEditorWindowOpen\s*-') 'Recovery not gated by WindowOpen-when-on-folder API'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
