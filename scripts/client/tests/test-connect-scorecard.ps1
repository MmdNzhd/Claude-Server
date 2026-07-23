# test-connect-scorecard.ps1 - #19 always-on SCORECARD boot/end
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Connect scorecard #19 (static) ===' -ForegroundColor Cyan
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$cp = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$sh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw
Assert ($ui -match 'function Write-ConnectScorecard') 'Write-ConnectScorecard defined'
Assert ($ui -match "ValidateSet\('boot', 'end'\)") 'Phases boot/end'
Assert ($ui -match "SCORECARD") 'Emits SCORECARD'
Assert ($ui -match 'CLAUDE_CONNECT_SCORECARD_UI') 'UI opt-in env'
Assert ($ui -notmatch 'Write-ConnectScorecard[\s\S]{0,200}Test-ConnectPerfEnabled') 'Scorecard not PERF-gated in function header region'
Assert ($cp -match "Write-ConnectScorecard -Phase 'boot'") 'boot hook in connect.ps1'
Assert ($cp -match "Write-ConnectScorecard -Phase 'end'") 'end hook in connect.ps1'
Assert ($sh -match 'write_connect_scorecard') 'Mac/sh helper present'
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
