#Requires -Version 5.1
# test-hard-cmd-flash-fleet-push.ps1
# HARD++ gate: periodic visible cmd.exe on Windows laptops.
# Server-side regressions must be proven fixed for EVERY /home user, not only smart.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}
Write-Host ''
Write-Host '=== HARD++: Windows CMD flash / fleet-wide ===' -ForegroundColor White
Write-Host ''

$repo = $script:RepoRoot
$push = Join-Path $script:ScriptsRoot 'server\claude-client-push-laptop.sh'
$fleet = Join-Path $script:ScriptsRoot 'server\claude-client-push-fleet.sh'
$mount = Join-Path $script:ScriptsRoot 'server\claude-mount.sh'
$heal = Join-Path $script:ScriptsRoot 'server\claude-self-heal.sh'
$le = Join-Path $script:ScriptsRoot 'server\laptop-exec.sh'
$gitPs = Join-Path $script:ClientRoot 'git-mode.ps1'
$wmcp = Join-Path $script:ClientRoot 'windows\windows-mcp-laptop.ps1'
$worker = Join-Path $repo 'publish\_setup-worker-body.ps1'
$launch = Join-Path $repo 'publish\_setup-launch-body.ps1'
$install = Join-Path $script:ScriptsRoot 'server\commands\install.sh'
$deployMount = Join-Path $script:ScriptsRoot 'server\commands\deploy-mount-fix.sh'

foreach ($f in @($push,$fleet,$mount,$heal,$le,$gitPs,$wmcp,$worker,$launch,$install,$deployMount)) {
    Assert (Test-Path -LiteralPath $f) ("exists $(Split-Path $f -Leaf)")
}

$pushSrc = Get-Content -LiteralPath $push -Raw
$mountSrc = Get-Content -LiteralPath $mount -Raw
$healSrc = Get-Content -LiteralPath $heal -Raw
$leSrc = Get-Content -LiteralPath $le -Raw
$gitSrc = Get-Content -LiteralPath $gitPs -Raw
$wmcpSrc = Get-Content -LiteralPath $wmcp -Raw
$workerSrc = Get-Content -LiteralPath $worker -Raw
$launchSrc = Get-Content -LiteralPath $launch -Raw
$installSrc = Get-Content -LiteralPath $install -Raw
$fleetSrc = Get-Content -LiteralPath $fleet -Raw
$deploySrc = Get-Content -LiteralPath $deployMount -Raw

Assert ($pushSrc -match 'ssh_l_ps_hidden') 'push-laptop defines ssh_l_ps_hidden'
Assert ($pushSrc -match 'WindowStyle Hidden') 'push-laptop uses WindowStyle Hidden'
Assert ($pushSrc -match 'EncodedCommand') 'push-laptop uses EncodedCommand'
Assert ($pushSrc -match 'IDLE_STAMP_SECS') 'push-laptop has IDLE_STAMP_SECS'
Assert ($pushSrc -match 'CLAUDE_CLIENT_PUSH_IDLE_SECS:-900') 'default idle stamp is 900s'
Assert ($pushSrc -match 'Already current') 'idle path documents skip of Connect.bat rewrite'
Assert ($pushSrc -notmatch 'cmd /c if exist') 'push-laptop has no cmd /c if exist version probe'
Assert ($pushSrc -notmatch 'cmd /c echo %USERPROFILE%') 'push-laptop has no cmd /c Desktop echo'
$needIdx = $pushSrc.IndexOf('if [ "$need_push" = "1" ]')
$shortcutIdx = $pushSrc.LastIndexOf('Desktop Connect.bat launcher')
if ($shortcutIdx -lt 0) { $shortcutIdx = $pushSrc.LastIndexOf('Connect.bat') }
Assert ($needIdx -ge 0) 'push-laptop has need_push branch'
Assert ($shortcutIdx -gt $needIdx) 'Connect.bat rewrite is after need_push=1 branch'
$rewriteBlock = if ($needIdx -ge 0) { $pushSrc.Substring($needIdx) } else { '' }
$beforeNeed = if ($needIdx -ge 0) { $pushSrc.Substring(0, $needIdx) } else { '' }
Assert ($rewriteBlock -match 'WriteAllText\(\$bat') 'need_push branch writes Connect.bat via WriteAllText'
Assert ($beforeNeed -notmatch 'WriteAllText\(\$bat') 'pre-need_push path does not WriteAllText Connect.bat'
Assert ($fleetSrc -match 'claude-client-push-laptop') 'fleet cron calls push-laptop'

Assert ($mountSrc -notmatch "rcmd='cmd /c exit 0'") 'claude-mount no cmd /c exit rcmd'
Assert ($mountSrc -match 'WindowStyle Hidden -Command exit') 'claude-mount hidden powershell probe'
Assert ($mountSrc -match 'WindowStyle Hidden -EncodedCommand') 'claude-mount _win_ps_encode is Hidden'
Assert ($healSrc -notmatch 'cmd /c exit 0') 'claude-self-heal no cmd /c exit 0'
Assert (($healSrc -split 'WindowStyle Hidden -Command exit').Count -ge 3) 'claude-self-heal has >=2 hidden probes'
Assert ($leSrc -notmatch 'cmd /c exit 0') 'laptop-exec no cmd /c exit 0'
Assert ($leSrc -match 'WindowStyle Hidden -Command exit') 'laptop-exec hidden tunnel probe'
Assert ($gitSrc -notmatch 'cmd /c exit 0') 'git-mode.ps1 no cmd /c exit 0'
Assert (($gitSrc -split 'WindowStyle Hidden -Command exit').Count -ge 3) 'git-mode.ps1 has >=2 hidden probes'
Assert ($wmcpSrc -notmatch 'cmd /c "netstat') 'windows-mcp listen fallback not cmd /c netstat'
Assert ($wmcpSrc -match 'CreateNoWindow\s*=\s*\$true') 'windows-mcp netstat fallback CreateNoWindow'
Assert ($workerSrc -match 'Unblock-File') 'setup-worker Unblock-File MOTW'
Assert ($launchSrc -match 'Unblock-File') 'setup-launch Unblock-File MOTW'
Assert ($workerSrc -notmatch 'Set-MpPreference') 'setup-worker never touches MpPreference'
Assert ($installSrc -match 'claude-client-push-laptop\.sh') 'install.sh deploys push-laptop'
Assert ($installSrc -match 'rm -f /usr/local/bin/claude-mount') 'install.sh force-resyncs bin mount (no stale file)'
Assert ($installSrc -match 'cmd /c exit 0') 'install.sh fails closed if cmd /c exit remains'
Assert ($installSrc -match 'claude-self-heal') 'install.sh deploys self-heal to user homes'
Assert ($deploySrc -match 'rm -f /usr/local/bin/claude-mount') 'deploy-mount-fix force-resyncs bin mount'
Assert ($deploySrc -match 'cmd /c exit 0') 'deploy-mount-fix fails closed on cmd /c exit'
Assert ($deploySrc -match 'claude-self-heal') 'deploy-mount-fix pushes self-heal to users'

Write-Host ''
Write-Host '--- LIVE FLEET: every /home user ---' -ForegroundColor Cyan
try {
    $audit = Join-Path $PSScriptRoot '_live-fleet-cmd-flash-audit.sh'
    Assert (Test-Path -LiteralPath $audit) 'LIVE audit script exists in tests/'
    $rid = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $remote = "/tmp/hard-cmd-flash-fleet-audit-$rid.sh"
    & scp -o BatchMode=yes -o ConnectTimeout=12 $audit "smart@192.168.210.240:$remote" 2>&1 | Out-Null
    # Must run as root: other users' ~/.local/bin is mode 700/750 and smart cannot sha256sum them.
    $sshCmd = "sed -i '1s/^\xEF\xBB\xBF//' '$remote'; chmod 755 '$remote'; sudo-from-laptop --smart -- bash '$remote'; ec=`$?; rm -f '$remote'; exit `$ec"
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=60 smart@192.168.210.240 $sshCmd 2>&1
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    Write-Host $text
    $livePass = ([regex]::Matches($text, 'LIVE_PASS ')).Count
    $liveFail = ([regex]::Matches($text, 'LIVE_FAIL ')).Count
    Assert ($livePass -ge 28) ("LIVE fleet checks passed count>=28 (got $livePass)")
    Assert ($liveFail -eq 0) ("LIVE fleet checks zero fails (got $liveFail)")
    Assert ($text -match 'fleet_users_(\d+)') 'LIVE reports fleet_users count'
    if ($text -match 'fleet_users_(\d+)') {
        Assert ([int]$Matches[1] -ge 8) ("LIVE fleet users >=8 (got $($Matches[1]))")
    }
} catch {
    Assert $false ("LIVE fleet ssh failed: $($_.Exception.Message)")
}

Write-Host ''
Write-Host '--- Desktop Claude-Connect parity ---' -ForegroundColor Cyan
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
if (Test-Path -LiteralPath $desk) {
    $dv = (Get-Content (Join-Path $desk 'connect-version.txt') -Raw).Trim()
    Assert ($dv -eq '20260727.02') ("Desktop connect-version is 20260727.02 (got $dv)")
    $dg = Get-Content (Join-Path $desk 'git-mode.ps1') -Raw
    Assert ($dg -notmatch 'cmd /c exit 0') 'Desktop git-mode.ps1 no cmd /c exit 0'
    Assert ($dg -match 'WindowStyle Hidden -Command exit') 'Desktop git-mode.ps1 hidden probe'
} else {
    Write-Host '  SKIP  Desktop\Claude-Connect missing' -ForegroundColor Yellow
}

Write-Host ''
Write-Host ("Passed: {0}  Failed: {1}" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'HARD++ cmd-flash fleet-wide: ALL PASS' -ForegroundColor Green
exit 0
