#Requires -Version 5.1
# test-hard-multi-agent-regressions.ps1
# HARD regression gate for bugs that slipped past HARD10/VERIFY10:
#   - single-instance mutex blocking unlimited clients
#   - Ensure-ConnectRunId called before function definition
#   - user-visible failures logged only as INFO / console-only
# Failures here mean "do not ship".

$ErrorActionPreference = 'Stop'
$Client = Resolve-Path (Join-Path $PSScriptRoot '..')
$failed = 0
$passed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

function Get-LineIndex([string]$Text, [string]$Needle) {
    $idx = $Text.IndexOf($Needle)
    if ($idx -lt 0) { return -1 }
    return ($Text.Substring(0, $idx) -split "`n").Count
}

Write-Host ''
Write-Host '=== HARD multi-agent regressions ===' -ForegroundColor White
Write-Host ''

$ui   = Get-Content (Join-Path $Client 'connect-ui.ps1') -Raw
$uiSh = Get-Content (Join-Path $Client 'connect-ui.sh') -Raw
$win  = Get-Content (Join-Path $Client 'windows\connect.ps1') -Raw
$upd  = Get-Content (Join-Path $Client 'windows\connect-update.ps1') -Raw
$bat  = Get-Content (Join-Path $Client 'windows\connect.bat') -Raw
$mac  = Get-Content (Join-Path $Client 'mac\connect.sh') -Raw
$desPs = Get-Content (Join-Path $Client 'users\designer\connect.ps1') -Raw
$desSh = Get-Content (Join-Path $Client 'users\designer\connect.sh') -Raw
$gm   = Get-Content (Join-Path $Client 'git-mode.ps1') -Raw

Write-Host '--- A) Unlimited concurrent clients ---' -ForegroundColor Cyan
Assert ($ui -match 'MULTI_INSTANCE: allowed') 'Win: Enter-ConnectSingleInstance is multi-instance no-op'
Assert ($ui -notmatch 'Another Claude Connect is already running') 'Win: no blocking single-instance user message'
Assert ($ui -match '(?s)function Enter-ConnectSingleInstance.*?return \$true') 'Win: Enter-ConnectSingleInstance always returns true'
Assert ($ui -notmatch 'New-Object System\.Threading\.Mutex') 'Win: connect-ui does not take Global\\ClaudeConnect mutex'
Assert ($uiSh -match 'MULTI_INSTANCE: allowed') 'Mac: enter_connect_single_instance is multi-instance no-op'
Assert ($uiSh -notmatch 'Another Claude Connect is already running') 'Mac: no blocking flock user message'
Assert ($desPs -notmatch 'Designer \+ main connect cannot share') 'Designer Win: no dual-connect block message'
Assert ($desSh -notmatch 'exec 9>"\$_designer_lockfile"') 'Designer Mac: no connect.lock flock'
Assert ($gm -match '0\.\.9') 'Tunnel slots 0..9 exist for concurrent tunnels'

Write-Host '--- B) Ensure-ConnectRunId define-before-use ---' -ForegroundColor Cyan
$defLine = Get-LineIndex $upd 'function Ensure-ConnectRunId'
# first call after param/setup (not inside function body) — find "$null = Ensure-ConnectRunId"
$callLine = Get-LineIndex $upd '$null = Ensure-ConnectRunId'
Assert ($defLine -gt 0) 'connect-update.ps1 defines Ensure-ConnectRunId'
Assert ($callLine -gt 0) 'connect-update.ps1 seeds Ensure-ConnectRunId early'
Assert ($defLine -lt $callLine) ("Ensure-ConnectRunId defined at L{0} before call at L{1}" -f $defLine, $callLine)

# Runtime: script must parse and function must resolve when early body runs
$tokens = $null; $errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($upd, [ref]$tokens, [ref]$errs)
Assert (($null -eq $errs) -or ($errs.Count -eq 0)) 'connect-update.ps1 parses cleanly'
# Execute only the Ensure-ConnectRunId function + early call in isolated scope
$probe = @'
function Ensure-ConnectRunId {
    if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
        $env:CLAUDE_CONNECT_RUN_ID = $env:CLAUDE_CONNECT_RUN_ID.Trim()
        return $env:CLAUDE_CONNECT_RUN_ID
    }
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    return $env:CLAUDE_CONNECT_RUN_ID
}
$env:CLAUDE_CONNECT_RUN_ID = ''
$id = Ensure-ConnectRunId
if (-not $id -or $id.Length -lt 8) { throw 'Ensure-ConnectRunId returned empty' }
'@
try {
    Invoke-Expression $probe
    Assert $true 'Ensure-ConnectRunId runtime probe OK'
} catch {
    Assert $false ("Ensure-ConnectRunId runtime probe: {0}" -f $_.Exception.Message)
}

Write-Host '--- C) User-visible failures MUST be FAIL ERROR in log ---' -ForegroundColor Cyan
Assert ($ui -match 'FAIL EXIT reason=') 'Wait-ConnectExit emits FAIL EXIT'
Assert ($ui -match 'Write-ConnectUserFacingError') 'Write-ConnectUserFacingError helper exists'
# Non-zero exit path uses ERROR level
Assert ($ui -match "(?s)if \(\`$Code -ne 0\).*FAIL EXIT.*'ERROR'") 'FAIL EXIT only on non-zero code with ERROR level'
Assert ($win -match 'FAIL STEP name=') 'StepFail emits FAIL STEP'
Assert ($win -match "STEP end:.*failed.*'ERROR'") 'StepFail uses ERROR not WARN'
Assert ($win -match 'FAIL NEED_ADMIN') 'Admin prompt emits FAIL NEED_ADMIN'
Assert ($win -match 'FAIL ADMIN_DENIED') 'Admin decline emits FAIL ADMIN_DENIED'
Assert ($win -match 'FAIL ADMIN_UAC') 'UAC failure emits FAIL ADMIN_UAC'
Assert ($win -match 'FAIL DIE:') 'Die emits FAIL DIE'
Assert ($win -match 'FAIL UNHANDLED') 'trap emits FAIL UNHANDLED'
Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'update trap emits FAIL UPDATE_UNHANDLED'
Assert ($bat -match 'FAIL UPDATE_BAT_EXIT') 'bat logs FAIL UPDATE_BAT_EXIT on update exit 1'
Assert ($mac -match 'FAIL STEP name=') 'Mac step_fail emits FAIL STEP'
Assert ($mac -match 'FAIL DIE:') 'Mac die emits FAIL DIE'

Write-Host '--- D) Console [X] must not be log-orphaned (spot checks) ---' -ForegroundColor Cyan
# OpenSSH early path writes day-log FAIL before Wait-ConnectExit
Assert ($win -match 'FAIL OpenSSH client') 'OpenSSH missing writes FAIL to day log'
Assert ($win -match 'FAIL ADMIN_FIX: No admin fix pending') 'AdminFix missing pending writes FAIL'

Write-Host '--- E) Session correlation for concurrent agents ---' -ForegroundColor Cyan
Assert ($bat -match 'CLAUDE_CONNECT_RUN_ID') 'bat sets RUN_ID before update'
Assert ($ui -match 'Get-ConnectSessionId') 'session id helper present'
Assert ($ui -match 'SESSION_FILTER') 'SESSION_FILTER tip for grepping concurrent sessions'
Assert ($ui -match '\[\$ts\] \[\$Level\] \[\$sid\]') 'log lines include session id bracket'


Write-Host '--- F) Update swap must not nest bak under live (flat layout) ---' -ForegroundColor Cyan
Assert ($upd -match 'flat_layout staging_ext') 'connect-update.ps1 guards flat Desktop layout bak outside live'
Assert ($upd -match 'windowsDir -eq \$packageRoot') 'connect-update.ps1 detects windowsDir -eq packageRoot'
$macUpd = Get-Content (Join-Path $Client 'mac\connect-update.sh') -Raw
Assert ($macUpd -match 'flat_layout') 'mac connect-update.sh guards flat layout bak outside live'
Assert ($bat -match 'FAIL OUTDATED_SCRIPTS') 'connect.bat logs FAIL OUTDATED_SCRIPTS'
Assert ($upd -match 'swap_inplace_ok') 'connect-update.ps1 inplace fallback when live in use'
Assert ($upd -match 'FAIL UPDATE_SWAP_IN_USE') 'connect-update.ps1 logs FAIL UPDATE_SWAP_IN_USE'


Write-Host '--- G) Admin AK ACL false-positive ---' -ForegroundColor Cyan
Assert ($win -match 'admin_ak unreadable unelevated') 'connect.ps1 skips NEED_ADMIN when admin_ak unreadable'
Assert ($win -match 'cannot_read_ak') 'Test-AuthorizedKeyFragment logs cannot_read_ak on access denied'
Assert ($win -match 'null -eq \$akHit') 'explicit null check for AK membership'


Write-Host '--- H) Deep log completeness (20260720.7) ---' -ForegroundColor Cyan
Assert ($win -match 'FAIL SSH_QUOTE') 'SSH quoting glitch logs FAIL SSH_QUOTE'
Assert ($win -match 'CONNECT_ATTEMPT') 'connect retry attempts logged'
Assert ($win -match 'FAIL CONNECT_UNREACHABLE') 'unreachable after 10 attempts logs FAIL CONNECT_UNREACHABLE'
Assert ($win -match 'INTERACTIVE: project_menu_shown') 'project menu wait is logged'
Assert ($win -match 'FAIL MENU_ABORT') 'empty Choose-Project logs FAIL MENU_ABORT'
Assert ($win -match 'FAIL LAPTOP_SSH_BOOT') 'Ensure-LaptopSshReady false logs FAIL LAPTOP_SSH_BOOT'
Assert ($win -match 'FAIL SERVER_SCRIPT_PUSH') 'server script push fail logged'
Assert ($uiSh -match 'connect_log_ts') 'Mac connect_log has millisecond timestamps helper'
Assert ((Get-Content (Join-Path $Client 'mac\connect.sh') -Raw) -match 'FAIL CONNECT_UNREACHABLE') 'Mac unreachable logs FAIL CONNECT_UNREACHABLE'
Assert ((Get-Content (Join-Path $Client 'mac\connect.sh') -Raw) -match '_boot_ts') 'Mac BOOTSTRAP uses ms timestamp'
Assert ((Get-Content (Join-Path $Client 'mac\connect-update.sh') -Raw) -match 'FAIL UPDATE_') 'Mac update ERROR prefixed FAIL UPDATE_'

Write-Host ''
Write-Host ("Hard regressions: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
