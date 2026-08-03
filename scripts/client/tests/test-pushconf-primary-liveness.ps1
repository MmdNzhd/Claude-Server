#Requires -Version 5.1
# test-pushconf-primary-liveness.ps1
# P1.3 AM_ONLY takeover + primary soft-liveness (AM_ONLY=0):
#   - non-primary: take over dead published port; keep when CUR still live
#   - primary: soft_keep CUR when both live + sshfs -p CUR under ~/mounts;
#     overwrite (fleet reclaim) when CUR live without mount_on_cur
#
# Exercises the REAL Push-ServerConnectConf $remoteBody (extracted + ExpandString +
# bash), not a reimplementation.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
$pass = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function ConvertTo-WslPath([string]$WinPath) {
    $full = [System.IO.Path]::GetFullPath($WinPath)
    if ($full -match '^([A-Za-z]):(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = ($Matches[2] -replace '\\', '/')
        return "/mnt/$drive$rest"
    }
    throw "Cannot convert path to WSL form: $WinPath"
}

Write-Host ''
Write-Host '=== PushConf primary publisher liveness (P1.3) ===' -ForegroundColor Cyan

$gmPath = Get-ClientFile 'git-mode.ps1'
$gm = Get-Content $gmPath -Raw
$push = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
$prim = Get-FunctionSource -Content $gm -Name 'Test-IsPrimaryTunnelPublisher'

Write-Host '--- A) Source shape ---' -ForegroundColor Cyan
Assert ($push.Length -gt 200) 'Push-ServerConnectConf extracted'
Assert ($prim -match 'CLAUDE_CONNECT_UI_SLOT') 'Test-IsPrimaryTunnelPublisher still slot-gated'
Assert ($push -match 'port_takeover') 'PushConf remote emits port_takeover'
Assert ($push -match 'CUR_LIVE') 'PushConf remote probes CUR_LIVE'
Assert ($push -match 'OUR_LIVE') 'PushConf remote probes OUR_LIVE'
Assert ($push -match 'published_dead') 'port_takeover names published_dead'
Assert ($push -match 'port_mismatch_keep.*cur_live') 'mismatch_keep retains cur_live/our_live observability'
Assert (($push -split "`n" | Where-Object { $_ -match "port_takeover" -and $_ -match 'foreach' }).Count -ge 1) 'client foreach signal list includes port_takeover'
Assert ($push -match 'primary_soft_keep') 'PushConf remote emits primary_soft_keep'
Assert ($push -match 'primary_overwrite') 'PushConf remote emits primary_overwrite'
Assert ($push -match 'MOUNT_ON_CUR') 'PushConf remote probes MOUNT_ON_CUR'
Assert ($push -match "pgrep.*\[s\]shfs|pgrep.*'\[s\]shfs'") 'PushConf remote scans sshfs via pgrep'
Assert ($push -match 'reason=mount_on_cur') 'primary_soft_keep cites reason=mount_on_cur'
Assert (($push -split "`n" | Where-Object { $_ -match 'primary_soft_keep' -and $_ -match 'foreach' }).Count -ge 1) 'client foreach signal list includes primary_soft_keep'
Assert (($push -split "`n" | Where-Object { $_ -match 'primary_overwrite' -and $_ -match 'foreach' }).Count -ge 1) 'client foreach signal list includes primary_overwrite'

$gmShPath = Get-ClientFile 'git-mode.sh'
$gmSh = Get-Content $gmShPath -Raw
Assert ($gmSh -match 'primary_soft_keep') 'Mac push_server_connect_conf emits primary_soft_keep'
Assert ($gmSh -match 'primary_overwrite') 'Mac push_server_connect_conf emits primary_overwrite'
Assert ($gmSh -match 'MOUNT_ON_CUR') 'Mac remote probes MOUNT_ON_CUR'
Assert ($gmSh -match 'reason=mount_on_cur') 'Mac primary_soft_keep cites mount_on_cur'

# Slot preference must remain: UI_SLOT=3 is non-primary (am_only path), takeover is remote.
if ($prim) {
    . ([scriptblock]::Create($prim))
    $saved = $env:CLAUDE_CONNECT_UI_SLOT
    try {
        $env:CLAUDE_CONNECT_UI_SLOT = '0'
        Assert (Test-IsPrimaryTunnelPublisher) 'slot 0 still preferred primary'
        $env:CLAUDE_CONNECT_UI_SLOT = '1'
        Assert (-not (Test-IsPrimaryTunnelPublisher)) 'slot 1 still non-primary by slot index (liveness is remote)'
    } finally {
        if ($null -eq $saved) { Remove-Item Env:CLAUDE_CONNECT_UI_SLOT -ErrorAction SilentlyContinue }
        else { $env:CLAUDE_CONNECT_UI_SLOT = $saved }
    }
}

$bashOk = $false
try {
    $probe = & bash -c "echo BASH_OK" 2>$null
    if ($LASTEXITCODE -eq 0 -and ($probe -join "`n") -match 'BASH_OK') { $bashOk = $true }
} catch { $bashOk = $false }

if (-not $bashOk) {
    Write-Host '  FAIL  WSL/bash not reachable - cannot execute live AM_ONLY liveness cases' -ForegroundColor Red
    $fail++
    Write-Host ''
    Write-Host ("Primary liveness: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor Red
    exit 1
}

$m = [regex]::Match($gm, '(?s)\$remoteBody = @"\r?\n(.*?)\r?\n"@')
if (-not $m.Success) {
    Write-Host '  FAIL  could not extract $remoteBody here-string' -ForegroundColor Red
    exit 1
}
$templateText = $m.Groups[1].Value

function Expand-PushConfRemoteBody {
    param(
        [string]$Template,
        [string]$SessionPort,
        [string]$SessionSlot,
        [string]$AmOnly = '1'
    )
    $clearFlag = '0'
    $preferEsc = ''
    $lu = 'liveness-test'
    $portEsc = $SessionPort
    $slotEsc = $SessionSlot
    $modeEsc = 'off'
    $hkEsc = ''
    $amOnlyFlag = $AmOnly
    $expanded = $ExecutionContext.InvokeCommand.ExpandString($Template)
    return (($expanded -replace "`r`n", "`n") -replace "`r", "`n")
}

function Start-BashTcpListener {
    param([Parameter(Mandatory)][int]$ListenPort)
    # Background nc listener on 127.0.0.1 inside WSL (same netns as /dev/tcp probes).
    $marker = [System.IO.Path]::Combine($env:TEMP, ("pushconf-live-{0}-{1}.ready" -f $ListenPort, [guid]::NewGuid().ToString('N')))
    $starter = [System.IO.Path]::Combine($env:TEMP, ("pushconf-live-{0}-{1}.sh" -f $ListenPort, [guid]::NewGuid().ToString('N')))
    $wslMarker = ConvertTo-WslPath $marker
    # OpenBSD nc accepts one connection then exits; loop-rebind so CUR_LIVE/OUR_LIVE
    # probes do not kill the listener. nohup so the loop survives starter exit.
    $lines = @(
        '#!/bin/bash'
        "nohup bash -c 'while true; do nc -l 127.0.0.1 $ListenPort >/dev/null 2>&1 || sleep 0.05; done' >/dev/null 2>&1 &"
        'PID=$!'
        "echo `"`$PID`" > `"${wslMarker}.pid`""
        ": > `"$wslMarker`""
        'sleep 0.3'
        "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$ListenPort' && echo READY_OK || echo READY_FAIL"
        'exit 0'
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")
    [System.IO.File]::WriteAllBytes($starter, $bytes)
    $wslStarter = ConvertTo-WslPath $starter
    $startOut = & bash $wslStarter 2>&1
    $startText = ($startOut | Out-String)
    if (-not (Test-Path $marker) -or $startText -notmatch 'READY_OK') {
        throw "Listener on $ListenPort did not become ready. starter_out=$startText"
    }
    $bgPid = ''
    $pidRaw = & bash -c "cat '${wslMarker}.pid' 2>/dev/null" 2>$null
    if ($pidRaw) { $bgPid = ("$pidRaw").Trim() }
    return @{ Pid = $bgPid; Marker = $marker; Starter = $starter; ListenPort = $ListenPort }
}

function Stop-BashTcpListener {
    param($Handle)
    if (-not $Handle) { return }
    if ($Handle.Pid) {
        & bash -c "kill $($Handle.Pid) 2>/dev/null; pkill -f 'nc -l 127.0.0.1 $($Handle.ListenPort)' 2>/dev/null; true" 2>$null | Out-Null
    }
    foreach ($p in @($Handle.Marker, $Handle.Starter)) {
        if ($p -and (Test-Path $p)) { Remove-Item -Force $p -ErrorAction SilentlyContinue }
    }
    if ($Handle.Marker) {
        $wslPid = (ConvertTo-WslPath $Handle.Marker) + '.pid'
        & bash -c "rm -f '$wslPid' 2>/dev/null" 2>$null | Out-Null
    }
}

# Pick two high ports unlikely to collide with Connect's 20000+UID block in this shell.
$deadPort = 27111
$livePort = 27112
$altLivePort = 27113

$handles = @()
$tempFiles = @()
try {
    Write-Host '--- B) LIVE: published dead + session alive => takeover ---' -ForegroundColor Cyan
    $hLive = Start-BashTcpListener -ListenPort $livePort
    $handles += $hLive

    $expanded = Expand-PushConfRemoteBody -Template $templateText -SessionPort "$livePort" -SessionSlot '1' -AmOnly '1'
    $wrapper = @"
set -u
TMPHOME=`$(mktemp -d)
export HOME="`$TMPHOME"
mkdir -p "`$HOME"
printf 'LAPTOP_USER=liveness-test\nTUNNEL_PORT=$deadPort\nPORT=$deadPort\nTUNNEL_SLOT=0\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=\nLAPTOP_HOSTKEY_FP=\n' > "`$HOME/.claude-connect.conf"
$expanded
echo "---CONF---"
cat "`$HOME/.claude-connect.conf"
rm -rf "`$TMPHOME"
"@
    $wrapper = ($wrapper -replace "`r`n", "`n") -replace "`r", "`n"
    $tmpSh = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_pushconf_takeover_$([guid]::NewGuid().ToString('N')).sh")
    $tempFiles += $tmpSh
    [System.IO.File]::WriteAllText($tmpSh, $wrapper)
    $out = & bash (ConvertTo-WslPath $tmpSh) 2>&1
    $outText = ($out -join "`n")
    Write-Host '  --- bash output (takeover) ---' -ForegroundColor DarkGray
    $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $result = ($out | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
    $written = [regex]::Match($outText, '(?m)^TUNNEL_PORT=(.*)$')
    $writtenPort = if ($written.Success) { $written.Groups[1].Value.Trim() } else { '' }

    Assert ($outText -match 'port_takeover') 'emits PUSH_CONF port_takeover when published port is dead'
    Assert ($outText -match "published_dead=$deadPort") "port_takeover cites published_dead=$deadPort"
    Assert ($writtenPort -eq "$livePort") "conf TUNNEL_PORT becomes live session port $livePort (was dead $deadPort)"
    Assert ($result -match "publish_port=$livePort") "RESULT publish_port=$livePort (not 0)"
    Assert ($outText -notmatch 'port_mismatch_keep') 'no port_mismatch_keep on successful takeover'

    Write-Host '--- C) LIVE: published still live + session alive => keep (no race) ---' -ForegroundColor Cyan
    $hCur = Start-BashTcpListener -ListenPort $altLivePort
    $handles += $hCur
    # session port remains $livePort (still listening)

    $expandedKeep = Expand-PushConfRemoteBody -Template $templateText -SessionPort "$livePort" -SessionSlot '1' -AmOnly '1'
    $wrapperKeep = @"
set -u
TMPHOME=`$(mktemp -d)
export HOME="`$TMPHOME"
mkdir -p "`$HOME"
printf 'LAPTOP_USER=liveness-test\nTUNNEL_PORT=$altLivePort\nPORT=$altLivePort\nTUNNEL_SLOT=0\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=\nLAPTOP_HOSTKEY_FP=\n' > "`$HOME/.claude-connect.conf"
$expandedKeep
echo "---CONF---"
cat "`$HOME/.claude-connect.conf"
rm -rf "`$TMPHOME"
"@
    $wrapperKeep = ($wrapperKeep -replace "`r`n", "`n") -replace "`r", "`n"
    $tmpKeep = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_pushconf_keep_$([guid]::NewGuid().ToString('N')).sh")
    $tempFiles += $tmpKeep
    [System.IO.File]::WriteAllText($tmpKeep, $wrapperKeep)
    $outKeep = & bash (ConvertTo-WslPath $tmpKeep) 2>&1
    $outKeepText = ($outKeep -join "`n")
    Write-Host '  --- bash output (keep) ---' -ForegroundColor DarkGray
    $outKeep | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $resultKeep = ($outKeep | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
    $writtenKeep = [regex]::Match($outKeepText, '(?m)^TUNNEL_PORT=(.*)$')
    $writtenKeepPort = if ($writtenKeep.Success) { $writtenKeep.Groups[1].Value.Trim() } else { '' }

    Assert ($outKeepText -notmatch 'port_takeover') 'no takeover when published port is still listening'
    Assert ($outKeepText -match 'port_mismatch_keep') 'still logs port_mismatch_keep for live primary + other slot'
    Assert ($outKeepText -match 'cur_live=1') 'mismatch_keep reports cur_live=1'
    Assert ($outKeepText -match 'our_live=1') 'mismatch_keep reports our_live=1'
    Assert ($writtenKeepPort -eq "$altLivePort") "conf keeps published live port $altLivePort (not session $livePort)"
    Assert ($resultKeep -match 'publish_port=0') 'RESULT publish_port=0 when keeping live primary'

    Write-Host '--- D) LIVE: published dead + session also dead => keep (no premature publish) ---' -ForegroundColor Cyan
    $dead2 = 27114
    $deadSession = 27115
    $expandedDead = Expand-PushConfRemoteBody -Template $templateText -SessionPort "$deadSession" -SessionSlot '2' -AmOnly '1'
    $wrapperDead = @"
set -u
TMPHOME=`$(mktemp -d)
export HOME="`$TMPHOME"
mkdir -p "`$HOME"
printf 'LAPTOP_USER=liveness-test\nTUNNEL_PORT=$dead2\nPORT=$dead2\nTUNNEL_SLOT=0\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=\nLAPTOP_HOSTKEY_FP=\n' > "`$HOME/.claude-connect.conf"
$expandedDead
echo "---CONF---"
cat "`$HOME/.claude-connect.conf"
rm -rf "`$TMPHOME"
"@
    $wrapperDead = ($wrapperDead -replace "`r`n", "`n") -replace "`r", "`n"
    $tmpDead = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_pushconf_bothdead_$([guid]::NewGuid().ToString('N')).sh")
    $tempFiles += $tmpDead
    [System.IO.File]::WriteAllText($tmpDead, $wrapperDead)
    $outDead = & bash (ConvertTo-WslPath $tmpDead) 2>&1
    $outDeadText = ($outDead -join "`n")
    $writtenDead = [regex]::Match($outDeadText, '(?m)^TUNNEL_PORT=(.*)$')
    $writtenDeadPort = if ($writtenDead.Success) { $writtenDead.Groups[1].Value.Trim() } else { '' }

    Assert ($outDeadText -notmatch 'port_takeover') 'no takeover when session port is not listening yet'
    Assert ($writtenDeadPort -eq "$dead2") "conf keeps prior published port when session not live yet"

    Write-Host '--- E) LIVE primary: CUR live + OUR live + fake sshfs on CUR => soft_keep ---' -ForegroundColor Cyan
    # AM_ONLY=0 (primary). Fake sshfs: bash -c sleep with trailing argv "sshfs -p CUR $HOME/mounts/..."
    # (GNU sleep rejects extra args and exits; bash keeps them in /proc/*/cmdline for pgrep -f).
    $expandedSoft = Expand-PushConfRemoteBody -Template $templateText -SessionPort "$livePort" -SessionSlot '0' -AmOnly '0'
    $wrapperSoft = @"
set -u
TMPHOME=`$(mktemp -d)
export HOME="`$TMPHOME"
mkdir -p "`$HOME/mounts/fakeproj"
# Fake sshfs cmdline via long-lived bash argv tail (sleep alone drops args on exec).
bash -c 'trap "exit 0" TERM; while true; do sleep 1; done' sshfs -p $altLivePort "`$HOME/mounts/fakeproj" >/dev/null 2>&1 &
FAKE_PID=`$!
# Ensure pgrep can see the fake before PushConf runs.
for _i in 1 2 3 4 5; do
  if kill -0 "`$FAKE_PID" 2>/dev/null && pgrep -u "`$(id -un)" -f '[s]shfs' >/dev/null 2>&1; then break; fi
  sleep 0.1
done
printf 'LAPTOP_USER=liveness-test\nTUNNEL_PORT=$altLivePort\nPORT=$altLivePort\nTUNNEL_SLOT=0\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=fakeproj\nLAPTOP_HOSTKEY_FP=\n' > "`$HOME/.claude-connect.conf"
$expandedSoft
echo "---CONF---"
cat "`$HOME/.claude-connect.conf"
kill `$FAKE_PID 2>/dev/null || true
rm -rf "`$TMPHOME"
"@
    $wrapperSoft = ($wrapperSoft -replace "`r`n", "`n") -replace "`r", "`n"
    $tmpSoft = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_pushconf_softkeep_$([guid]::NewGuid().ToString('N')).sh")
    $tempFiles += $tmpSoft
    [System.IO.File]::WriteAllText($tmpSoft, $wrapperSoft)
    $outSoft = & bash (ConvertTo-WslPath $tmpSoft) 2>&1
    $outSoftText = ($outSoft -join "`n")
    Write-Host '  --- bash output (primary soft_keep) ---' -ForegroundColor DarkGray
    $outSoft | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $resultSoft = ($outSoft | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
    $writtenSoft = [regex]::Match($outSoftText, '(?m)^TUNNEL_PORT=(.*)$')
    $writtenSoftPort = if ($writtenSoft.Success) { $writtenSoft.Groups[1].Value.Trim() } else { '' }

    Assert ($outSoftText -match 'primary_soft_keep') 'emits PUSH_CONF primary_soft_keep when mount_on_cur'
    Assert ($outSoftText -match 'reason=mount_on_cur') 'primary_soft_keep cites reason=mount_on_cur'
    Assert ($outSoftText -match "session=$livePort") "soft_keep cites session=$livePort"
    Assert ($outSoftText -match "server=$altLivePort") "soft_keep cites server=$altLivePort"
    Assert ($writtenSoftPort -eq "$altLivePort") "conf keeps published CUR_PORT $altLivePort (soft keep)"
    Assert ($resultSoft -match 'publish_port=0') 'RESULT publish_port=0 on primary soft_keep'
    Assert ($resultSoft -match 'am_only=0') 'RESULT am_only=0 on primary soft_keep path'
    Assert ($outSoftText -notmatch 'primary_overwrite') 'no primary_overwrite when soft_keep applies'
    Assert ($outSoftText -notmatch 'port_takeover') 'no am_only port_takeover on primary soft_keep'

    Write-Host '--- F) LIVE primary: CUR live + OUR live + no sshfs => overwrite ---' -ForegroundColor Cyan
    $expandedOw = Expand-PushConfRemoteBody -Template $templateText -SessionPort "$livePort" -SessionSlot '0' -AmOnly '0'
    $wrapperOw = @"
set -u
TMPHOME=`$(mktemp -d)
export HOME="`$TMPHOME"
mkdir -p "`$HOME"
printf 'LAPTOP_USER=liveness-test\nTUNNEL_PORT=$altLivePort\nPORT=$altLivePort\nTUNNEL_SLOT=0\nGIT_MODE=off\nLAPTOP_OS=windows\nACTIVE_MOUNT=\nLAPTOP_HOSTKEY_FP=\n' > "`$HOME/.claude-connect.conf"
$expandedOw
echo "---CONF---"
cat "`$HOME/.claude-connect.conf"
rm -rf "`$TMPHOME"
"@
    $wrapperOw = ($wrapperOw -replace "`r`n", "`n") -replace "`r", "`n"
    $tmpOw = [System.IO.Path]::Combine($PSScriptRoot, "_tmp_pushconf_overwrite_$([guid]::NewGuid().ToString('N')).sh")
    $tempFiles += $tmpOw
    [System.IO.File]::WriteAllText($tmpOw, $wrapperOw)
    $outOw = & bash (ConvertTo-WslPath $tmpOw) 2>&1
    $outOwText = ($outOw -join "`n")
    Write-Host '  --- bash output (primary overwrite) ---' -ForegroundColor DarkGray
    $outOw | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $resultOw = ($outOw | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
    $writtenOw = [regex]::Match($outOwText, '(?m)^TUNNEL_PORT=(.*)$')
    $writtenOwPort = if ($writtenOw.Success) { $writtenOw.Groups[1].Value.Trim() } else { '' }

    Assert ($outOwText -match 'primary_overwrite') 'emits PUSH_CONF primary_overwrite when CUR live without mount'
    Assert ($outOwText -match 'cur_live=1') 'overwrite cites cur_live=1'
    Assert ($outOwText -match 'mount_on_cur=0') 'overwrite cites mount_on_cur=0'
    Assert ($outOwText -notmatch 'primary_soft_keep') 'no soft_keep without mount_on_cur'
    Assert ($writtenOwPort -eq "$livePort") "conf publishes session PORT $livePort (fleet reclaim)"
    Assert ($resultOw -match "publish_port=$livePort") "RESULT publish_port=$livePort on overwrite"
} catch {
    Write-Host "  FAIL  live harness exception: $($_.Exception.Message)" -ForegroundColor Red
    $fail++
} finally {
    foreach ($h in $handles) { Stop-BashTcpListener $h }
    foreach ($f in $tempFiles) {
        if (Test-Path $f) { Remove-Item -Force $f -ErrorAction SilentlyContinue }
    }
}

Write-Host ''
Write-Host ("Primary liveness: {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
exit 0
