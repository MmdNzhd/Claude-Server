#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
$script:passCount = 0
$script:failCount = 0
$script:fails = New-Object System.Collections.Generic.List[string]

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "PASS  $Msg" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "FAIL  $Msg" -ForegroundColor Red
        $script:failCount++
        [void]$script:fails.Add($Msg)
    }
}

Set-Location D:\Smart\Claude-Code-Server
Write-Host "ROOT=$(Get-Location)" -ForegroundColor DarkGray

$gm   = Get-Content 'scripts/client/git-mode.ps1' -Raw
$ui   = Get-Content 'scripts/client/connect-ui.ps1' -Raw
$uiSh = Get-Content 'scripts/client/connect-ui.sh' -Raw
$el   = Get-Content 'scripts/client/editor-launch.ps1' -Raw
$win  = Get-Content 'scripts/client/windows/connect.ps1' -Raw
$mac  = Get-Content 'scripts/client/mac/connect.sh' -Raw
$ver  = (Get-Content 'scripts/client/windows/connect-version.txt' -Raw).Trim()
$cm   = Get-Content 'scripts/server/claude-mount.sh' -Raw
$auth = Get-Content 'scripts/client/cursor-auth-laptop.ps1' -Raw
$hard = Get-Content 'scripts/client/tests/test-hard-multi-agent-regressions.ps1' -Raw
$sl   = Get-Content 'scripts/client/tests/test-session-log-contracts.ps1' -Raw
$pipe = Get-Content 'scripts/client/tests/test-connect-pipeline.ps1' -Raw

Write-Host ''
Write-Host '=== P0 STRICT AUDIT ===' -ForegroundColor Cyan

Write-Host '--- 1) Tunnel peer safety ---' -ForegroundColor Yellow
Assert ($gm -match 'skip_peer_live') 'git-mode: ORPHAN skip_peer_live'
Assert ($gm -match 'ACQUIRE_SKIP:\s*peer_live') 'git-mode: ACQUIRE_SKIP peer_live'
Assert ($gm -match 'Get-LocalTunnelSshPids') 'git-mode: Get-LocalTunnelSshPids helper'
Assert ($gm -match '\[int\]\$TunnelPid') 'Write-TunnelDropLog param TunnelPid'
Assert ($gm -notmatch '(?s)function Write-TunnelDropLog\s*\{[^}]{0,400}\[int\]\$Pid\s*=') 'Write-TunnelDropLog must NOT use [int]$Pid'
Assert ($win -match '-TunnelPid\s+\$bgPid') 'connect.ps1 calls -TunnelPid $bgPid'
Assert ($win -notmatch 'Write-TunnelDropLog[^\r\n]*-Pid\s+\$') 'connect.ps1 must not pass -Pid to TunnelDropLog'
Assert ($gm -match 'TUNNEL_STOP: skip_peer_live') 'Stop-SessionTunnelCleanup skips peer live'

Write-Host '--- 2) Single-instance ---' -ForegroundColor Yellow
Assert ($ui -match 'Global\\ClaudeConnect') 'Win mutex Global\ClaudeConnect'
Assert ($ui -match 'Another Claude Connect is already running') 'Win blocking message'
Assert ($ui -match 'SINGLE_INSTANCE') 'Win SINGLE_INSTANCE logs'
Assert ($ui -notmatch 'MULTI_INSTANCE: allowed') 'Win: no MULTI_INSTANCE allowed'
Assert ($uiSh -notmatch 'MULTI_INSTANCE: allowed') 'Mac: no MULTI_INSTANCE allowed'
Assert ($uiSh -match 'SINGLE_INSTANCE|flock|connect\.lock') 'Mac flock/single-instance'
Assert ($hard -match 'Global\\ClaudeConnect') 'hard-multi asserts mutex'
Assert ($hard -notmatch "Assert \(\`$ui -match 'MULTI_INSTANCE: allowed'\)") 'hard-multi does not assert MULTI_INSTANCE'
Assert ($sl -notmatch "Assert \(\`$ui -match 'MULTI_INSTANCE: allowed'\)") 'session-log does not assert MULTI_INSTANCE'

Write-Host '--- 3) Launch fail-closed ---' -ForegroundColor Yellow
Assert ($el -match 'PROC_START_FAIL: mode=elevated_launch_task') 'elevated_launch_task PROC_START_FAIL'
Assert ($el -match 'LAUNCH_FAIL: started_but_no_process') 'LAUNCH_FAIL started_but_no_process'
Assert ($el -match 'LAUNCH_FAIL: started_but_no_window') 'LAUNCH_FAIL started_but_no_window'
$warnIdx = $el.IndexOf('LAUNCH_WARN: process started but folder workspace not detected')
Assert ($warnIdx -ge 0) 'LAUNCH_WARN marker still present for soft folder miss'
if ($warnIdx -ge 0) {
    $slice = $el.Substring($warnIdx, [Math]::Min(800, $el.Length - $warnIdx))
    Assert ($slice -match 'return \$false') 'after LAUNCH_WARN eventual return false'
    Assert ($slice -notmatch '(?m)^\s*return \$true\s*$') 'no bare return true after LAUNCH_WARN block'
}
Assert ($win -match '(?s)if \(-not \(Launch-RemoteEditor[\s\S]{0,300}StepFail') 'Opening step StepFail when launch false'

Write-Host '--- 4) Silent update ---' -ForegroundColor Yellow
Assert ($ui -match "UPDATE_SILENT skip reason=tunnel_down") 'silent update skips tunnel_down'
$beg = [regex]::Match($win, '(?s)function Begin-ConnectRecovery\s*\{.{0,900}')
Assert ($beg.Success) 'Begin-ConnectRecovery found'
Assert ($beg.Value -notmatch 'Invoke-ConnectSilentUpdateCheck') 'Begin-ConnectRecovery does not call silent update'
Assert ($win -match "UPDATE_SILENT phase=post_tunnel_recovery") 'silent update post_tunnel_recovery phase'
Assert ($ui -match '(?s)if \(\$exitCode -eq 0 -or \$exitCode -eq 2\)[\s\S]{0,200}WriteAllText\(\$stateFile') 'stamp only on exit 0 or 2'

Write-Host '--- 5) Version + Task A/B ---' -ForegroundColor Yellow
Assert ($ver -eq '20260720.10') ("connect-version.txt is 20260720.10 (got '$ver')")
Assert ($win -match "ConnectVersion = '20260720.10'") 'connect.ps1 version .10'
Assert ($mac -match "CONNECT_VERSION='20260720.10'") 'mac version .10'
Assert ($ui -match 'LOG_SYNC_RECONCILE') 'Task A LOG_SYNC_RECONCILE Win'
Assert ($uiSh -match 'LOG_SYNC_RECONCILE') 'Task A LOG_SYNC_RECONCILE Mac'
Assert ($auth -match 'AUTH_SYNC_BATCH_PROBE') 'Task B AUTH_SYNC_BATCH_PROBE'

Write-Host '--- 6) git-hide fail-fast ---' -ForegroundColor Yellow
Assert ($cm -match 'n -lt 2') 'claude-mount hide loop n-lt-2'
Assert ($cm -notmatch 'while \(\$n -lt 3\)') 'no Win while n-lt-3'
Assert ($pipe -match 'fail-fast|lt 2') 'pipeline test expects fail-fast'
Assert ($pipe -notmatch 'retries git rename 3x') 'pipeline no longer asserts 3x'

Write-Host '--- 7) SSH quote ---' -ForegroundColor Yellow
Assert ($win -match 'base64 -d') 'ssh path uses base64 -d'
Assert ($win -notmatch "timeout 45 bash -lc '\$escaped'") 'no fragile bash -lc $escaped'

Write-Host '--- 8) Parse critical PS1 ---' -ForegroundColor Yellow
foreach ($rel in @(
    'scripts/client/git-mode.ps1',
    'scripts/client/connect-ui.ps1',
    'scripts/client/editor-launch.ps1',
    'scripts/client/windows/connect.ps1',
    'scripts/client/cursor-auth-laptop.ps1',
    'scripts/client/tests/test-hard-multi-agent-regressions.ps1',
    'scripts/client/tests/test-session-log-contracts.ps1',
    'scripts/client/tests/test-connect-pipeline.ps1'
)) {
    $tok = $null; $err = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $rel), [ref]$tok, [ref]$err)
    $ok = ($null -eq $err) -or ($err.Count -eq 0)
    Assert $ok ("parse OK $rel")
    if (-not $ok) { foreach ($e in $err) { Write-Host ("    ERR: $e") -ForegroundColor DarkRed } }
}

Write-Host '--- 9) bash -n ---' -ForegroundColor Yellow
foreach ($rel in @('scripts/client/connect-ui.sh','scripts/client/mac/connect.sh','scripts/server/claude-mount.sh','scripts/client/git-mode.sh')) {
    & bash -n $rel 2>&1 | Out-Null
    Assert ($LASTEXITCODE -eq 0) ("bash -n OK $rel")
}

Write-Host ''
$color = if ($script:failCount -gt 0) { 'Red' } else { 'Green' }
Write-Host ("=== SUMMARY passed={0} failed={1} ===" -f $script:passCount, $script:failCount) -ForegroundColor $color
if ($script:failCount -gt 0) {
    Write-Host 'FAILURES:' -ForegroundColor Red
    $script:fails | ForEach-Object { Write-Host ("  - " + $_) -ForegroundColor Red }
    exit 1
}
exit 0
