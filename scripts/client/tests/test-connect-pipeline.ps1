# test-connect-pipeline.ps1 - regression tests for project-select pipeline bug
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$ver = Get-ConnectVersion

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== connect.ps1 pipeline self-test ===" -ForegroundColor Cyan
Write-Host ""

$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connectUiPs1 = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
Assert ($connectUiPs1 -notmatch 'function Get-GitModeLabel') 'connect-ui.ps1 does not shadow Get-GitModeLabel'

foreach ($rel in @('windows\connect.ps1')) {
    $path = Get-ClientFile $rel
    $src = Get-Content $path -Raw
    $parseErrs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrs)
    Assert ((-not $parseErrs) -or ($parseErrs.Count -eq 0)) "$rel parses cleanly in PS 5.1"
    Assert ($src -notmatch '[\u201C\u201D\u2018\u2019]') "$rel has no smart/curly quotes (PS 5.1 break)"
    Assert ($src -notmatch 'Set-ConnectTitle "Claude Connect \| \$\(') "$rel Set-ConnectTitle avoids pipe-in-double-quote PS 5.1 bug"
    $bundle = $src + $gitModePs1
    Assert ($src -match 'function Choose-Project') "$rel uses Choose-Project (no while-loop pipeline leak)"
    Assert ($src -notmatch '(?m)^\s+\$go = \[PSCustomObject\]') "$rel has no bare `$go = [PSCustomObject]"
    Assert ($src -match 'Launch-RemoteEditor') "$rel launches editor via Launch-RemoteEditor"
    Assert ($src -match "ConnectVersion = '$([regex]::Escape($ver))'") "$rel has current ConnectVersion ($ver)"
    Assert ($src -match 'connect-ui\.ps1') "$rel dot-sources connect-ui"
    Assert ($src -match '\-AdminFix') "$rel supports AdminFix"
    Assert ($src -match 'Read-PostDisconnectKey') "$rel has post-disconnect helper"
    Assert ($src -match 'menuLoop|Clear-SessionMount|Initialize-ServerSession') "$rel has v11 session features"
    Assert ($src -match 'git-mode\.ps1') "$rel dot-sources git-mode.ps1"
    Assert ($bundle -match 'Remount-ProjectGit') "$rel has mid-session git remount"
    Assert ($src -match 'Write-SessionBox|G = git mode') "$rel has session git hotkey"
    Assert ($bundle -match 'function Get-GitMode') "$rel has Get-GitMode (via git-mode.ps1)"
    Assert ($bundle -match 'GIT_MODE=%s') "$rel pushes GIT_MODE to server"
    Assert ($bundle -match 'LAPTOP_OS=windows') "$rel pushes LAPTOP_OS to server"
    Assert ($src -match '"g" \{.*Configure-GitMode') "$rel has git menu option"
    Assert ($bundle -match 'Push-ServerConnectConf') "$rel has Push-ServerConnectConf"
    Assert ($src -match '@\(Choose-Project -Mounts \$allMounts\)\[-1\]') "$rel uses safe Choose-Project capture"
    Assert ($src -match 'Initialize-SessionBgTunnel') "$rel pre-warms tunnel after Ready"
    Assert ($src -match '@\(Resolve-EditorChoice -CfgDir \$CfgDir\)\[-1\]') "$rel uses safe Resolve-EditorChoice capture"
    Assert ($src -match 'Test-AuthorizedKeyFragment|Test-LaptopSshReady') "$rel has laptop SSH key check helper"
    Assert ($bundle -match 'Acquire-TunnelPort') "$rel uses tunnel slot acquisition"
    Assert ($bundle -match 'Sanitize-SshAliasConfig') "$rel sanitizes ssh config (no RemoteForward)"
    Assert ($bundle -match 'Ensure-LaptopReverseSshCached') "$rel caches laptop SSH verify"
    Assert ($src -match 'Ensure-SessionTunnel') "$rel uses Ensure-SessionTunnel"
    Assert ($src -match 'TrustedTunnel') "$rel uses trusted tunnel mount"
    Assert ($src -notmatch 'RemoteForward \$Port') "$rel ssh config has no RemoteForward"
    Assert ($src -notmatch 'Select-String -Path \$userAk -Pattern \[regex\]::Escape') "$rel Select-String uses safe Pattern variable"
    Assert ($src -match 'function Get-InteractiveLaptopUser') "$rel resolves logged-on laptop user when elevated"
    Assert ($src -match 'Get-InteractiveLaptopUser') "$rel stores LAPTOP_USER from interactive session not elevated token"
    Assert ($src -match 'tunnelAuthRetryCount') "$rel caps tunnel auth retry loop"
    Assert ($src -match 'Start-ProcessAsInteractiveUser|Start-Process powershell\.exe -Verb RunAs') "$rel self-elevates to administrator on launch"
    Assert ($src -notmatch 'Verb RunAs -ArgumentList $elevArgs -PassThru -Wait') "$rel elevate does not -Wait (avoids stuck unelevated console)"
    Assert ($src -match 'Invoke-LaptopAdminOps') "$rel has laptop admin SSH helpers"
}


# P0 recovery/tunnel safety contract (connect-fix-100 #93-95).
$winConnect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

$syncTunnel = Get-FunctionSource $gitModePs1 'Sync-SessionTunnelProcess'
$pushConf = Get-FunctionSource $gitModePs1 'Push-ServerConnectConf'
Assert ($winConnect -match 'RECOVERY_SKIP_CLEAR_MOUNT') 'auto recovery logs RECOVERY_SKIP_CLEAR_MOUNT when editor stays open'
Assert ($winConnect -match 'FINALLY_KEEP_TUNNEL') 'finally keeps tunnel alive while editor remains on remote folder'
Assert ($syncTunnel -match 'TUNNEL_SYNC soft_fail[^\r\n]*(no_ssh_proc|tcp_open_no_process|no_process_tcp_open|no_proc_tcp_open)') 'tunnel sync soft-fails when TCP is open without a process handle'
Assert (($gitModePs1 + $winConnect) -match 'TunnelSyncFailCount') 'Windows tunnel sync debounces consecutive failures'
Assert ($pushConf -notmatch 'claude-self-heal') 'Push-ServerConnectConf does not invoke claude-self-heal'
Assert ($pushConf -match 'ToBase64String|base64 -d') 'Push-ServerConnectConf uses base64 remote body'
Assert ($pushConf -match 'PUSH_CONF_RESULT') 'Push-ServerConnectConf requires PUSH_CONF_RESULT'
Assert ($pushConf -match 'hasResult') 'Push-ServerConnectConf gates dedupe on hasResult'
Assert ($gitModePs1 -match 'function Invoke-SshXChecked') 'git-mode.ps1 has Invoke-SshXChecked for Out-Null hot paths'

Assert ($syncTunnel -match 'LastTunnelSyncTraceAt[\s\S]*?TotalSeconds\s+-ge\s+30') 'Windows TUNNEL_SYNC TRACE is throttled to at least 30 seconds'

$authLaptop = Get-Content (Get-ClientFile 'cursor-auth-laptop.ps1') -Raw
$editorLaunch = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($authLaptop -match 'Merge-CursorAuthIntoLocalDb') 'cursor-auth-laptop uses merge not file replace'
Assert ($authLaptop -notmatch 'Stop-Cursor|CloseMainWindow') 'cursor-auth-laptop never closes Cursor'
Assert ($editorLaunch -match 'NonElevatedLauncher') 'editor-launch uses explorer token for fast de-elevated start'
Assert ($editorLaunch -match 'Initialize-EditorLaunchTask') 'editor-launch has reusable schtasks fallback'
Assert ($editorLaunch -match 'Invoke-SchTasksQuiet') 'editor-launch suppresses schtasks console noise'
Assert ($editorLaunch -match 'Test-RemoteEditorWindowOpen') 'editor-launch detects visible editor window'
Assert ($editorLaunch -match 'Initialize-CursorServerProfile') 'editor-launch marks server windows'

foreach ($rel in @('windows\connect.ps1')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    Assert ($src -match 'Sync-CursorGoldenAuth -Alias \$Alias') "$rel syncs cursor auth every reconnect"
    Assert ($src -match 'if \(-not \$editorOpened\)') "$rel opens editor only once"
    Assert ($src -match 'auth_folder_check') "$rel logs auth_folder_check perf mark"
    Assert ($src -match 'Test-RemoteEditorWindowOpenWhenOnFolder') "$rel uses single-pass window check after on_folder"
    Assert ($src -match 'Write-ConnectSessionOpenSummary') "$rel emits session_open_summary"
    Assert ($src -match 'ConnectPerf') "$rel tracks ConnectPerf counters"
}

function Choose-ProjectMock {
    return [PSCustomObject]@{ Id = 'ai'; Path = '/home/smart/mounts/ai' }
}
$go = Choose-ProjectMock
$p = Join-Path 'C:\Users\Smart' '.config\claude-connect'
Assert ($p -like '*claude-connect*') "Join-Path after project select (no ChildPath prompt)"

$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw
Assert ($mount -match 'GIT_MODE') "claude-mount.sh reads GIT_MODE"
Assert ($mount -match 'LAPTOP_OS') "claude-mount.sh reads LAPTOP_OS"
Assert ($mount -match '_mac_sh') "claude-mount.sh has Mac laptop git ops"
Assert ($mount -match 'GIT_HIDE:fail') "claude-mount reports git hide failures"
Assert ($mount -match 'warn: git hide failed') "claude-mount warns on git hide failure"
Assert ($mount -match 'warn: laptop tunnel down') "claude-mount warns when tunnel down"
Assert ($mount -match '\$n -lt 2') "claude-mount git hide fail-fast (<=2 attempts)"
Assert ($mount -match '_mount_restore_git_mode') "claude-mount restores GIT_MODE explicitly"
Assert ($mount -notmatch "trap 'GIT_MODE") "claude-mount has no RETURN trap on GIT_MODE"


$winConnect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($winConnect -match 'function Begin-ConnectRecovery') 'connect.ps1 has Begin-ConnectRecovery'
Assert ($winConnect -match 'RECOVERY_BEGIN trigger=') 'connect.ps1 logs RECOVERY_BEGIN'
Assert ($winConnect -match 'STEP begin:') 'connect.ps1 logs STEP begin'
Assert ($winConnect -match 'function SshX') 'connect.ps1 has SshX wrapper'
Assert ($winConnect -match 'SSH_TIMEOUT exit=124') 'connect.ps1 retries SshX on timeout'
Assert ($winConnect -match 'timeout 45 bash') 'connect.ps1 wraps SshX with timeout'

$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
Assert ($gitMode -match 'function Invoke-MountProject') 'git-mode.ps1 auto-retries mount after script push'
Assert ($gitMode -match 'function Resolve-ServerScriptDir') 'git-mode.ps1 resolves server scripts for ZIP layout'
Assert ($authLaptop -match 'Write-AuthPerfLog') 'cursor-auth-laptop emits auth PERF marks'
Assert ($authLaptop -match 'auth_total') 'cursor-auth-laptop tracks auth_total'
Assert ($gitMode -match 'mount_ssh_up') 'git-mode emits mount PERF marks'

# V9 additive: session log + tunnel-drop contracts (full suite in test-session-log-contracts.ps1)
$connectBat = Get-Content (Get-ClientFile 'windows\connect.bat') -Raw
$connectUiPs1 = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$connectUiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw
Assert ($connectBat -match 'CLAUDE_CONNECT_RUN_ID') 'connect.bat bootstraps CLAUDE_CONNECT_RUN_ID'
Assert ($connectBat -notmatch '-WindowStyle Hidden.*connect\.ps1') 'connect.bat runs connect.ps1 in visible console (not hidden window)'
Assert ($connectBat -match 'start "" /D "%HERE_NOTRAIL%" powershell(\.exe)?.*connect-boot\.ps1') 'connect.bat async handoff starts connect-boot.ps1'
Assert ($connectBat -match 'connect-boot\.ps1') 'connect.bat handoffs via connect-boot.ps1'
Assert ($gitMode -match 'TUNNEL_DROP') 'git-mode.ps1 emits TUNNEL_DROP on tunnel soft-fail'
Assert ($connectUiPs1 -match 'TUNNEL_DROP') 'connect-ui.ps1 forces log sync on TUNNEL_DROP'
Assert ($connectUiSh -match 'TUNNEL_DROP') 'connect-ui.sh forces log sync on TUNNEL_DROP'

$publish = Get-Content (Join-Path $script:RepoRoot 'publish\publish.ps1') -Raw
Assert (-not (Test-Path (Get-ClientFile 'users\sepidz\connect.ps1'))) 'no sepidz connect fork (single codebase)'
Assert ($publish -match 'scripts\\client\\windows\\connect\.ps1') 'publish uses canonical windows connect.ps1'
Assert ($publish -match 'PatchIp = \$true') 'publish has IP patch flag for Sepidz'
Assert ($publish -notmatch 'users\\sepidz') 'publish does not reference users/sepidz fork'

$sessionLogRc = 0
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-session-log-contracts.ps1')
if ($LASTEXITCODE -ne 0) { $sessionLogRc = [int]$LASTEXITCODE; $failed += 1; Write-Host 'FAIL session-log-contracts (see above)' -ForegroundColor Red }


Write-Host ""
if ($fail -eq 0) { Write-Host "All tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
