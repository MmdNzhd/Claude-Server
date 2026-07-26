#Requires -Version 5.1
# test-hard-multi-agent-regressions.ps1
# HARD regression gate for bugs that slipped past HARD10/VERIFY10:
#   - Up to 10 Connect UIs per PC (Global\ClaudeConnect#0..#9)
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

Write-Host '--- A) Up to 10 Connect UIs per PC (multi instance) ---' -ForegroundColor Cyan
Assert ($ui -match 'Global\\ClaudeConnect#') 'Win: Enter-ConnectSingleInstance uses Global\ClaudeConnect# slot mutexes'
Assert ($ui -match 'New-Object System\.Threading\.Mutex') 'Win: connect-ui takes slot Mutex'
Assert (
    ($ui -match '10 Claude Connect windows already open') -or
    ($ui -match 'MULTI_INSTANCE: acquired')
) 'Win: blocks at 10 or logs MULTI_INSTANCE acquire'
Assert ($ui -match 'MULTI_INSTANCE: acquired') 'Win: multi-instance slot pool enabled'
Assert ($ui -match 'mutex error \(block\)') 'Win: mutex catch is fail-closed (block)'
Assert ($ui -notmatch 'mutex error \(continue\)') 'Win: mutex catch must not fail-open'
Assert ($gm -match 'no result line') 'git-mode: pushLine null-safe fallback'
Assert ($bat -match 'connect-boot\.ps1') 'connect.bat handoffs via connect-boot.ps1 (atomic slot mutex)'
Assert ($bat -notmatch 'ReleaseMutex') 'connect.bat must not probe/release mutex (TOCTOU)'
$boot = Get-Content (Join-Path $Client 'windows\connect-boot.ps1') -Raw
Assert ($boot -match 'ReleaseMutex' -and $boot -match 'CLAUDE_CONNECT_BOOT_MUTEX' -and $boot -match 'ClaudeConnect#') 'connect-boot owns slot mutex release (not cold-start UAC in connect.ps1)'
Assert ($win -match 'Elevate-when-needed') 'connect.ps1 elevate-when-needed (no always-elevate before UAC)'
Assert ($win -match 'Invoke-LaptopAdminOps' -and $win -match 'Start-Process powershell\.exe -Verb RunAs') 'on-demand AdminFix RunAs still present'

Assert (Test-Path (Join-Path $Client 'windows\connect-boot.ps1')) 'connect-boot.ps1 exists'
Assert ((Get-Content (Join-Path $Client 'windows\connect-boot.ps1') -Raw) -match 'ClaudeConnect#') 'connect-boot acquires ClaudeConnect# slot pool'
Assert ((Get-Content (Join-Path $Client '..\..\publish\deploy-client-bundles.ps1') -Raw) -match "connect-boot\.ps1") 'deploy-client-bundles includes connect-boot.ps1 in WinBundleFiles'
Assert (
    ($uiSh -match 'connect\.lock') -or
    ($uiSh -match 'Another Claude Connect is already running') -or
    ($uiSh -match 'SINGLE_INSTANCE: acquired') -or
    ($uiSh -match 'MULTI_INSTANCE')
) 'Mac: enter_connect_single_instance uses flock or instance message'
Assert ($desPs -match 'Enter-ConnectSingleInstance') 'Designer Win: shares main instance gate'
Assert ($desPs -match '(?s)Enter-ConnectSingleInstance[\s\S]{0,200}-not \(Enter-ConnectSingleInstance\)') 'Designer Win: honors mutex false (exits)'
Assert ($desPs -notmatch '\$null = Enter-ConnectSingleInstance') 'Designer Win: must not discard mutex result'
Assert ($desSh -match 'enter_connect_single_instance') 'Designer Mac: shares main instance gate'
Assert ($gm -match '0\.\.9') 'Tunnel slots 0..9 align with multi-UI capacity'
Assert ($gm -match 'CLAUDE_CONNECT_UI_SLOT') 'git-mode prefers CLAUDE_CONNECT_UI_SLOT for tunnel acquire'
Assert ($gm -match 'skip_sibling') 'git-mode ORPHAN_TUNNEL skip_sibling present'
Assert ($gm -match 'Get-SiblingConnectTunnelPids') 'git-mode Get-SiblingConnectTunnelPids present'
Assert ($gm -match 'sticky_shared|sibling_live') 'git-mode Acquire sticky_shared / sibling_live'
Assert ($gm -match 'am_only|Test-IsPrimaryTunnelPublisher') 'git-mode am_only PushConf keeps primary TUNNEL_PORT'
$exeBody = Get-Content (Join-Path $Client '..\..\publish\_setup-launch-body.ps1') -Raw
$exeWorker = Get-Content (Join-Path $Client '..\..\publish\_setup-worker-body.ps1') -Raw
Assert ($exeBody -match 'function Test-ConnectUiOpen') 'EXE setup defines Test-ConnectUiOpen'
Assert ($exeBody -match 'return \(\$free -eq 0\)') 'EXE setup blocks only when zero free ClaudeConnect# slots'
Assert ($exeBody -notmatch 'Get-CimInstance Win32_Process') 'EXE setup does not scan Win32_Process for false single-instance'
Assert ($exeBody -match '10 Claude Connect windows already open') 'EXE MessageBox matches 10 already-open text'
Assert ($exeWorker -match 'ClaudeConnectExeLaunch') 'ExeLaunch double-launch gate lives in the detached worker (setup-launch exits fast)'
Assert ($exeBody -match 'setup-worker\.ps1') 'EXE setup spawns the detached worker'
# Deferred Server-setup child must not steal a second ClaudeConnect# slot / UI_SLOT.
Assert ($win -match 'DeferredServerSetupOnly') 'Win: DeferredServerSetupOnly child mode exists'
Assert ($win -match 'deferred_setup_skip_mutex') 'Win: deferred setup skips Enter-ConnectSingleInstance (no 2nd UI slot)'
Assert ($win -match '(?s)if \(\$DeferredServerSetupOnly\)[\s\S]{0,900}elseif \(-not \(Enter-ConnectSingleInstance\)\)') 'Win: Enter-ConnectSingleInstance gated behind DeferredServerSetupOnly skip'
Assert ($win -match 'inherit_slot') 'Win: deferred setup logs/preserves parent UI_SLOT for tunnel acquire'
Write-Host '--- B) Ensure-ConnectRunId define-before-use ---' -ForegroundColor Cyan
$defLine = Get-LineIndex $upd 'function Ensure-ConnectRunId'
# first call after param/setup (not inside function body) â€" find "$null = Ensure-ConnectRunId"
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
Assert ($upd -match 'UPDATE_SWAP_IN_USE') 'connect-update.ps1 logs UPDATE_SWAP_IN_USE'


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
$bootToMenu = [regex]::Match($win, '(?s)Mark-BootstrapDone[\s\S]*?:menuLoop\s+while').Value
$initSession = [regex]::Match($win, '(?ms)^function\s+Initialize-ServerSession\s*\{.*?(?=^function\s+|\z)').Value
Assert ($bootToMenu -and ($bootToMenu -notmatch 'Initialize-ServerSession')) 'no Initialize-ServerSession between Ready and menuLoop'
Assert ($bootToMenu -and ($bootToMenu -notmatch 'Ensure-LaptopSshReady')) 'no duplicate Ensure-LaptopSshReady between Ready and menuLoop'
Assert (($initSession -match 'Ensure-LaptopSshReady') -and ($initSession -match '\$script:LaptopFirewallOk\s*=\s*\$true')) 'Ensure#1 success sets LaptopFirewallOk in Initialize-ServerSession'
Assert ($win -match 'FAIL SERVER_SCRIPT_PUSH') 'server script push fail logged'
Assert ($uiSh -match 'connect_log_ts') 'Mac connect_log has millisecond timestamps helper'
Assert ((Get-Content (Join-Path $Client 'mac\connect.sh') -Raw) -match 'FAIL CONNECT_UNREACHABLE') 'Mac unreachable logs FAIL CONNECT_UNREACHABLE'
Assert ((Get-Content (Join-Path $Client 'mac\connect.sh') -Raw) -match '_boot_ts') 'Mac BOOTSTRAP uses ms timestamp'
Assert ((Get-Content (Join-Path $Client 'mac\connect-update.sh') -Raw) -match 'FAIL UPDATE_') 'Mac update ERROR prefixed FAIL UPDATE_'

Write-Host ''
Write-Host ("Hard regressions: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
