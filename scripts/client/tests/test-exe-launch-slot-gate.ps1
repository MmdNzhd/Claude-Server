#Requires -Version 5.1
# test-exe-launch-slot-gate.ps1 - Stage 6f: EXE setup only blocks when 10 slots full
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== EXE launch slot gate (Stage 6f) ==="
Write-Host ""

$bodyPath = Join-Path $RepoRoot 'publish\_setup-launch-body.ps1'
Assert (Test-Path -LiteralPath $bodyPath) '_setup-launch-body.ps1 exists'
$body = Get-Content -LiteralPath $bodyPath -Raw

Assert ($body -match 'function Test-ConnectUiOpen') 'defines Test-ConnectUiOpen'
Assert ($body -match 'Global\\ClaudeConnect#') 'probes Global\ClaudeConnect# slots'
Assert ($body -match 'ClaudeConnectExeLaunch') 'keeps ExeLaunch debounce mutex'
Assert ($body -match '10 Claude Connect') 'MessageBox/text mentions 10 Claude Connect'
Assert ($body -match 'already open') 'MessageBox/text mentions already open'

# Must NOT gate on connect.ps1/connect-boot.ps1 process CommandLine (false single-instance)
Assert (-not ($body -match "(?i)CommandLine -match '\(\?i\)connect-boot")) 'no connect-boot CommandLine process gate'
Assert (-not ($body -match "(?i)CommandLine -match '\(\?i\)connect\.ps1")) 'no connect.ps1 CommandLine process gate'
Assert (-not ($body -match 'Get-CimInstance Win32_Process')) 'no Win32_Process scan for UI-open gate'

# Block only when zero free slots (return true iff all 10 held)
Assert ($body -match '(?i)free|slot') 'slot/free vocabulary present'
Assert (
    ($body -match 'return \(\$free -eq 0\)') -or
    ($body -match 'return \(\$freeCount -eq 0\)') -or
    ($body -match 'if \(\$free -gt 0\) \{ return \$false \}') -or
    ($body -match 'zero free') -or
    ($body -match '\$freeSlots')
) 'blocks only when zero free slots (explicit free-count gate)'

# Old false-positive MessageBox must be gone
Assert (-not ($body -match "'Claude Connect is already open\.'")) 'old single-instance MessageBox text removed'

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
