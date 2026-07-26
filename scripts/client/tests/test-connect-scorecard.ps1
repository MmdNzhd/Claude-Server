#Requires -Version 5.1
# test-connect-scorecard.ps1 - #19 always-on SCORECARD boot/end + Task 8 EditorOpened preference
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Connect scorecard #19 (static + EditorOpened fixture) ===' -ForegroundColor Cyan
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

# --- Task 8 harden: $script:EditorOpened=$true fixture must emit editor=open ---
$scSrc = Get-FunctionSource -Content $ui -Name 'Write-ConnectScorecard'
Assert (-not [string]::IsNullOrWhiteSpace($scSrc)) 'Write-ConnectScorecard extractable'
Assert ($scSrc -match '\$null\s*-ne\s*\$script:EditorOpened') 'SCORECARD prefers $script:EditorOpened (null-check)'
Assert ($scSrc -notmatch '\$script:EditorOpened\s*-or\s*\$script:EditorSeenOpen') 'SCORECARD must not OR EditorSeenOpen (false-green)'

$script:ScorecardLines = New-Object System.Collections.Generic.List[string]
function Write-ConnectLog {
    param([string]$Message, [string]$Level = 'INFO')
    $script:ScorecardLines.Add([string]$Message)
}
. ([scriptblock]::Create($scSrc))

$script:EditorOpened = $true
$script:EditorSeenOpen = $false
$script:ConnectVersion = 'test-scorecard'
$script:ScorecardLines.Clear()
Write-ConnectScorecard -Phase 'end'
$lineOpen = ($script:ScorecardLines | Where-Object { $_ -match 'SCORECARD' } | Select-Object -First 1)
Assert ($lineOpen -match 'editor=open') `
    "Task8: `$script:EditorOpened=`$true fixture => SCORECARD has editor=open (got: $lineOpen)"

# Sticky SeenOpen alone must NOT force editor=open
$script:EditorOpened = $false
$script:EditorSeenOpen = $true
$script:ScorecardLines.Clear()
Write-ConnectScorecard -Phase 'end'
$lineClosed = ($script:ScorecardLines | Where-Object { $_ -match 'SCORECARD' } | Select-Object -First 1)
Assert ($lineClosed -match 'editor=closed') `
    "Task8: EditorSeenOpen alone => editor=closed (got: $lineClosed)"

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1