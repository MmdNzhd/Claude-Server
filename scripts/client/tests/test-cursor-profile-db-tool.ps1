#Requires -Version 5.1
# test-cursor-profile-db-tool.ps1 - Stage 10: report OK; prune refuses if profile Cursor running / without -Force
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== cursor-profile-db-tool (Stage 10) ==="
Write-Host ""

$tool = Join-Path $RepoRoot 'scripts\client\cursor-profile-db-tool.ps1'
Assert (Test-Path -LiteralPath $tool) 'cursor-profile-db-tool.ps1 exists'
$src = Get-Content -LiteralPath $tool -Raw

Assert ($src -match '\[switch\]\$Report') 'has -Report'
Assert ($src -match 'PruneChatAgent') 'has -PruneChatAgent'
Assert ($src -match '\[switch\]\$Force') 'has -Force'
Assert ($src -match 'Test-CursorServerProfileClosed|Get-CursorProfileProcesses') 'checks profile Cursor closed before prune'
Assert ($src -match 'REFUSE prune') 'emits REFUSE prune on unsafe path'
Assert ($src -match 'NEVER wire|not wired into connect') 'documents never wire into connect'
Assert ($src -match 'Get-CursorRemoteProfileDir') 'uses Get-CursorRemoteProfileDir'

# Must not be auto-wired into connect paths
$conn = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.ps1') -Raw
$boot = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect-boot.ps1') -Raw
$bat = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.bat') -Raw
Assert ($conn -notmatch 'cursor-profile-db-tool') 'connect.ps1 does not call cursor-profile-db-tool'
Assert ($boot -notmatch 'cursor-profile-db-tool') 'connect-boot.ps1 does not call cursor-profile-db-tool'
Assert ($bat -notmatch 'cursor-profile-db-tool') 'connect.bat does not call cursor-profile-db-tool'

# Parse OK
$tokens = $null; $errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($tool, [ref]$tokens, [ref]$errs)
Assert (($null -eq $errs) -or ($errs.Count -eq 0)) 'tool parses cleanly'

# Runtime: -Report should exit 0
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$reportOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Report 2>&1 | Out-String
$ErrorActionPreference = $prevEap
$reportEc = $LASTEXITCODE
Assert ($reportEc -eq 0) ("-Report exit 0 (got $reportEc)")
Assert ($reportOut -match 'state_vscdb_bytes=') '-Report prints state_vscdb_bytes'
Assert ($reportOut -match 'profile_cursor_closed=') '-Report prints profile_cursor_closed'

# Runtime: prune without -Force must refuse
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$noForce = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -PruneChatAgent 2>&1 | Out-String
$ErrorActionPreference = $prevEap
$noForceEc = $LASTEXITCODE
Assert ($noForceEc -ne 0) '-PruneChatAgent without -Force exits non-zero'
Assert ($noForce -match 'REFUSE prune') '-PruneChatAgent without -Force says REFUSE'

# Runtime: if profile Cursor is open, -Force still refuses (process gate)
$el = Join-Path $RepoRoot 'scripts\client\editor-launch.ps1'
. $el
$procs = @(Get-CursorProfileProcesses -ForceRefresh)
if ($procs.Count -gt 0) {
    $prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$forced = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -PruneChatAgent -Force 2>&1 | Out-String
$ErrorActionPreference = $prevEap
    $forcedEc = $LASTEXITCODE
    Assert ($forcedEc -ne 0) '-PruneChatAgent -Force refuses while profile Cursor running'
    Assert ($forced -match 'REFUSE prune|still running') 'refuse message mentions still running'
} else {
    Write-Host '  SKIP runtime refuse-while-running (no profile Cursor process right now)' -ForegroundColor DarkYellow
    # Static contract still requires the closed check in source
    Assert ($src -match 'still running') 'source has still-running refuse message'
}

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
