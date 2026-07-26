#Requires -Version 5.1
# test-designer-close-log.ps1
# Designer Win connect must Close-ConnectLog on session teardown / script exit
# (parity with windows/connect.ps1 day-log flush).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Designer Close-ConnectLog presence ===' -ForegroundColor White

$des = Get-Content (Get-ClientFile 'users\designer\connect.ps1') -Raw

Assert ($des -match 'Initialize-ConnectLog') 'designer opens connect day log'
Assert ($des -match 'Close-ConnectLog') 'designer references Close-ConnectLog'
Assert ($des -match '(?s)\} finally \{.*?Close-ConnectLog') `
    'designer finally block calls Close-ConnectLog'
Assert ($des -match '(?s)# end :mainLoop.*?Close-ConnectLog') `
    'designer script exit path calls Close-ConnectLog'

if ($failed -gt 0) {
    Write-Host "FAILED $failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All designer Close-ConnectLog asserts passed' -ForegroundColor Green
exit 0
