#Requires -Version 5.1
# test-harder-live-hygiene-race.ps1
# HARD LIVE (race): real Get-ConnectHygieneReport / Invoke-ConnectHygieneClean from git-mode.ps1.
# Decoys: current tunnel, orphan tunnel, sibling tunnel + fake Connect UI host.
# Two parallel Soft cleans overlap on orphan reclaim; sibling + current must survive both.
# Then Sibling mode kills sibling host + tunnel; current + slot marker hygiene.
# Skips honestly when helpers or C# stub compile are unavailable. Returns pass/fail/skip counts.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARD LIVE: hygiene Soft race + Sibling clean ===' -ForegroundColor White

$content = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$need = @(
    'Write-GitModeLog', 'Clear-TunnelBannerCache', 'Get-TunnelProcessExitCode',
    'Stop-TunnelProcessWithExitLog',
    'Get-LocalTunnelSshReverseRegex', 'Test-LocalTunnelSshCommandLine', 'Get-LocalTunnelSshPids',
    'Test-ProcessCommandIsConnectUi',
    'Get-SiblingConnectTunnelPids', 'Remove-LocalOrphanTunnel', 'Get-ConnectUiPidForProcess',
    'Get-ConnectSessionSlotMarkerDir', 'Get-ConnectSessionSlotMarkerPath',
    'Write-ConnectSessionSlotMarker', 'Clear-ConnectSessionSlotMarker', 'Get-ConnectSessionSlotMarkers',
    'Get-ConnectHygieneReport', 'Invoke-ConnectHygieneClean'
)
$missing = @()
foreach ($n in $need) {
    if (-not (Get-FunctionSource -Content $content -Name $n)) { $missing += $n }
}
if ($missing.Count -gt 0) {
    Write-Host ("SKIPPED: missing git-mode helpers: {0}" -f ($missing -join ', ')) -ForegroundColor Yellow
    $Skip++
    Write-Host ("HARD LIVE hygiene-race RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}
foreach ($n in $need) {
    . ([scriptblock]::Create((Get-FunctionSource -Content $content -Name $n)))
}

$script:CfgDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-hygiene-race-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$CfgDir = $script:CfgDir
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null

$script:Base = Get-Random -Minimum 47000 -Maximum 47990
$Base = $script:Base
function Get-TunnelPortUserBase { param([string]$UidStr) return [int]$script:Base }
function Get-ConnectSessionSlotMarkerDir { return [string]$script:CfgDir }

$script:cursorCloses = New-Object System.Collections.Generic.List[string]
$script:sshxCalls = 0
function Close-CursorProjectWindows {
    param([string]$ProjectRootName, [string]$ProtectRootName = '', [string]$Alias = 'claude-server')
    [void]$script:cursorCloses.Add(("{0}|protect={1}" -f $ProjectRootName, $ProtectRootName))
    return 1
}
function SshX {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $script:sshxCalls++
    $joined = ($Args | ForEach-Object { "$_" }) -join ' '
    if ($joined -match 'cursor-server-reaper') { return 'REAPER_OK_RACE' }
    if ($joined -match 'MUX_DEAD') { return 'MUX_DEAD_REMOVED=0' }
    return "LISTEN_BEGIN`nLISTEN_END`nMUX_BEGIN`nMUX_END`nSFTP_BEGIN`n0`nSFTP_END`nSM_BEGIN`nSM_END"
}

$tmpRoot = Join-Path $CfgDir 'bin'
$dirOrphan = Join-Path $tmpRoot 'orphan'
$dirSibling = Join-Path $tmpRoot 'sibling'
$dirCurrent = Join-Path $tmpRoot 'current'
$dirHost = Join-Path $tmpRoot 'host'
foreach ($d in @($dirOrphan, $dirSibling, $dirCurrent, $dirHost)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$sshOrphanExe = Join-Path $dirOrphan 'ssh.exe'
$sshSiblingExe = Join-Path $dirSibling 'ssh.exe'
$sshCurrentExe = Join-Path $dirCurrent 'ssh.exe'
$connectHostExe = Join-Path $dirHost 'fake-connect-host.exe'
$pidOrphan = Join-Path $tmpRoot 'orphan.pid'
$pidSibling = Join-Path $tmpRoot 'sibling.pid'
$pidCurrent = Join-Path $tmpRoot 'current.pid'
$pidHost = Join-Path $tmpRoot 'host.pid'

$sshStubSrc = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
class SshStubHangRace {
    static void Main(string[] args) {
        try {
            for (int i = 0; i < args.Length - 1; i++) {
                if (args[i] == "--pidfile") {
                    File.WriteAllText(args[i + 1], Process.GetCurrentProcess().Id.ToString());
                    break;
                }
            }
        } catch { }
        Thread.Sleep(Timeout.Infinite);
    }
}
'@
$connectHostSrc = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
class FakeConnectHostRace {
    static void Main(string[] args) {
        try { File.WriteAllText(args[1], Process.GetCurrentProcess().Id.ToString()); } catch { }
        try {
            var psi = new ProcessStartInfo {
                FileName = args[0],
                Arguments = "-R " + args[3] + ":localhost:22 -N -o ExitOnForwardFailure=yes fakeuser@laptophost --pidfile \"" + args[2] + "\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
            Process.Start(psi);
        } catch { }
        Thread.Sleep(Timeout.Infinite);
    }
}
'@

try {
    Add-Type -Language CSharp -TypeDefinition $sshStubSrc -OutputType ConsoleApplication -OutputAssembly $sshOrphanExe -ErrorAction Stop
    Copy-Item -LiteralPath $sshOrphanExe -Destination $sshSiblingExe -Force
    Copy-Item -LiteralPath $sshOrphanExe -Destination $sshCurrentExe -Force
    Add-Type -Language CSharp -TypeDefinition $connectHostSrc -OutputType ConsoleApplication -OutputAssembly $connectHostExe -ErrorAction Stop
} catch {
    Write-Host ("SKIPPED: could not compile decoy stubs ({0})" -f $_.Exception.Message) -ForegroundColor Yellow
    Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue
    $Skip++
    Write-Host ("HARD LIVE hygiene-race RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

$portCurrent = $Base + 0
$portSibling = $Base + 1
$portOrphan = $Base + 2
$script:PortOrphan = $portOrphan

$orphanPid = 0; $siblingPid = 0; $currentPid = 0; $hostPid = 0
$orphanProc = $null; $currentProc = $null; $hostProc = $null
$rs = $null; $ps = $null; $asyncHandle = $null
$barrier = New-Object System.Threading.ManualResetEventSlim($false)
$script:SoftRaceBarrier = $barrier
$sync = [hashtable]::Synchronized(@{
    Cmd = 'idle'
    State = 'idle'
    Overlap = $false
    Soft2Done = $false
    Error = $null
})

$script:OrigRemoveOrphan = ${function:Remove-LocalOrphanTunnel}
function Remove-LocalOrphanTunnel {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    if ($TargetPort -eq $script:PortOrphan) {
        $live = @(Get-LocalTunnelSshPids -TargetPort $TargetPort)
        if ($live.Count -gt 0) {
            if (-not $script:SoftRaceBarrier.IsSet) {
                [void]$script:SoftRaceBarrier.Set()
                Start-Sleep -Milliseconds 1000
            } else {
                $sync.Overlap = $true
                Start-Sleep -Milliseconds 350
            }
        }
    }
    & $script:OrigRemoveOrphan @PSBoundParameters
}

function Wait-SyncState {
    param([string]$Expect, [int]$TimeoutMs = 12000)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if ($sync.State -eq $Expect -or $sync.State -eq 'error') { return $true }
        Start-Sleep -Milliseconds 25
    }
    return $false
}

try {
    Note 'PhaseA: start current + orphan + sibling decoy tunnels'
    $currentProc = Start-Process -FilePath $sshCurrentExe -ArgumentList @(
        '-R', "${portCurrent}:localhost:22", '-N', '-o', 'ExitOnForwardFailure=yes',
        'fakeuser@laptophost', '--pidfile', $pidCurrent
    ) -WindowStyle Hidden -PassThru

    $orphanProc = Start-Process -FilePath $sshOrphanExe -ArgumentList @(
        '-R', "${portOrphan}:localhost:22", '-N', '-o', 'ExitOnForwardFailure=yes',
        'fakeuser@laptophost', '--pidfile', $pidOrphan
    ) -WindowStyle Hidden -PassThru

    $hostProc = Start-Process -FilePath $connectHostExe -ArgumentList @(
        $sshSiblingExe, $pidHost, $pidSibling, "$portSibling", 'C:\FakeConnectClient\connect.ps1'
    ) -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and -not (
            (Test-Path $pidCurrent) -and (Test-Path $pidOrphan) -and
            (Test-Path $pidHost) -and (Test-Path $pidSibling))) {
        Start-Sleep -Milliseconds 150
    }

    $okCur = (Test-Path $pidCurrent) -and [int]::TryParse((Get-Content $pidCurrent -Raw), [ref]$currentPid)
    $okOr = (Test-Path $pidOrphan) -and [int]::TryParse((Get-Content $pidOrphan -Raw), [ref]$orphanPid)
    $okHost = (Test-Path $pidHost) -and [int]::TryParse((Get-Content $pidHost -Raw), [ref]$hostPid)
    $okSib = (Test-Path $pidSibling) -and [int]::TryParse((Get-Content $pidSibling -Raw), [ref]$siblingPid)
    Assert ($okCur -and $okOr -and $okHost -and $okSib) `
        ("all four decoys ready (cur=$currentPid or=$orphanPid host=$hostPid sib=$siblingPid)")
    if (-not ($okCur -and $okOr -and $okHost -and $okSib)) { throw 'setup' }

    Start-Sleep -Milliseconds 250
    $script:SessionBgTunnel = Get-Process -Id $currentPid -ErrorAction Stop
    Write-ConnectSessionSlotMarker -Slot 1 -Port $portSibling -ProjectId 'SiblingRace' -RemotePath 'D:\work\SiblingRace' -ProcessId $hostPid
    $markPath = Get-ConnectSessionSlotMarkerPath -Slot 1
    $marks = @(Get-ConnectSessionSlotMarkers)
    Assert ((Test-Path -LiteralPath $markPath) -and $marks.Count -ge 1 -and $marks[0].ProjectId -eq 'SiblingRace') `
        'slot marker wired for SiblingRace on slot 1'

    $report = Get-ConnectHygieneReport -UidStr '1000' -ProtectRemotePath 'D:\work\CurrentRace' -ProtectProjectId 'CurrentRace' -SkipServer
    $byPort = @{}
    foreach ($t in @($report.Tunnels)) { $byPort[[int]$t.Port] = $t }

    Assert ($byPort.ContainsKey($portCurrent) -and $byPort[$portCurrent].Class -eq 'current') `
        "report classifies port=$portCurrent as current"
    Assert ($byPort.ContainsKey($portOrphan) -and $byPort[$portOrphan].Class -eq 'orphan') `
        "report classifies port=$portOrphan as orphan"
    Assert ($byPort.ContainsKey($portSibling) -and $byPort[$portSibling].Class -eq 'sibling') `
        "report classifies port=$portSibling as sibling"

    Note 'PhaseB: parallel Soft race — background runspace waits for hold then Soft again'
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync)
    $rs.SessionStateProxy.SetVariable('barrier', $barrier)
    $rs.SessionStateProxy.SetVariable('reportCopy', $report)
    $rs.SessionStateProxy.SetVariable('portOrphan', $portOrphan)
    $rs.SessionStateProxy.SetVariable('currentPid', $currentPid)
    $rs.SessionStateProxy.SetVariable('cfgDirRace', $CfgDir)
    foreach ($n in $need) {
        $src = Get-FunctionSource -Content $content -Name $n
        $rs.SessionStateProxy.SetVariable("fn_$n", $src)
    }
    $rs.SessionStateProxy.SetVariable('needNames', $need)

    $bgScript = @'
$ErrorActionPreference = 'Continue'
foreach ($n in $needNames) {
    $src = (Get-Variable -Name ("fn_" + $n) -ValueOnly)
    . ([scriptblock]::Create($src))
}
function Get-TunnelPortUserBase { param([string]$UidStr) return [int]$reportCopy.PortBase }
function Get-ConnectSessionSlotMarkerDir { return [string]$cfgDirRace }
function SshX { return 'REAPER_OK_RACE' }
function Close-CursorProjectWindows { return 0 }
$script:SessionBgTunnel = Get-Process -Id $currentPid -ErrorAction Stop
$script:PortOrphan = $portOrphan
$script:OrigRemoveOrphan = ${function:Remove-LocalOrphanTunnel}
function Remove-LocalOrphanTunnel {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    if ($TargetPort -eq $script:PortOrphan) {
        $live = @(Get-LocalTunnelSshPids -TargetPort $TargetPort)
        if ($live.Count -gt 0) {
            if (-not $barrier.IsSet) { $null = $barrier.Wait(15000) }
            $sync.Overlap = $true
            Start-Sleep -Milliseconds 350
        }
    }
    & $script:OrigRemoveOrphan @PSBoundParameters
}
while ($true) {
    switch ($sync.Cmd) {
        'soft2' {
            if ($sync.State -ne 'soft2_done' -and $sync.State -ne 'error') {
                try {
                    if (-not $barrier.Wait(15000)) { throw 'barrier timeout before soft2' }
                    $null = Invoke-ConnectHygieneClean -Mode Soft -Report $reportCopy `
                        -ProtectRemotePath 'D:\work\CurrentRace' -ProtectProjectId 'CurrentRace'
                    $sync.Soft2Done = $true
                    $sync.State = 'soft2_done'
                } catch {
                    $sync.Error = $_.Exception.Message
                    $sync.State = 'error'
                }
            }
        }
        'stop' { break }
    }
    if ($sync.Cmd -eq 'stop' -or $sync.State -eq 'error') { break }
    Start-Sleep -Milliseconds 20
}
'@
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($bgScript)
    $asyncHandle = $ps.BeginInvoke()
    Start-Sleep -Milliseconds 120
    $sync.Cmd = 'soft2'

    $soft1 = Invoke-ConnectHygieneClean -Mode Soft -Report $report `
        -ProtectRemotePath 'D:\work\CurrentRace' -ProtectProjectId 'CurrentRace'

    $gotSoft2 = Wait-SyncState -Expect 'soft2_done' -TimeoutMs 15000
    if ($sync.Error) {
        Assert $false ("background Soft error: {0}" -f $sync.Error)
    } else {
        Assert ($gotSoft2 -and $barrier.IsSet -and $script:sshxCalls -ge 2) `
            'parallel Soft race: main hold signalled and both Soft cleans ran (sshx>=2)'
    }

    $deadlineSoft = (Get-Date).AddSeconds(8)
    $orphanDead = $false
    while ((Get-Date) -lt $deadlineSoft) {
        if (-not (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) { $orphanDead = $true; break }
        Start-Sleep -Milliseconds 150
    }
    $siblingAlive = [bool](Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)
    $currentAlive = [bool](Get-Process -Id $currentPid -ErrorAction SilentlyContinue)
    $hostAlive = [bool](Get-Process -Id $hostPid -ErrorAction SilentlyContinue)

    Assert $orphanDead "dual Soft killed orphan tunnel pid=$orphanPid"
    Assert $siblingAlive "dual Soft left sibling tunnel pid=$siblingPid alive"
    Assert $currentAlive "dual Soft left current tunnel pid=$currentPid alive"
    Assert $hostAlive "dual Soft left sibling Connect UI host pid=$hostPid alive"
    Note ("dual Soft orphans_killed soft1=$($soft1.OrphansKilled) sshx=$($script:sshxCalls)")

    Note 'PhaseC: Sibling clean kills sibling host + tunnel; current survives'
    $report2 = Get-ConnectHygieneReport -UidStr '1000' -ProtectRemotePath 'D:\work\CurrentRace' -ProtectProjectId 'CurrentRace' -SkipServer

    $script:cursorCloses.Clear()
    $sib = Invoke-ConnectHygieneClean -Mode Sibling -Report $report2 `
        -ProtectRemotePath 'D:\work\CurrentRace' -ProtectProjectId 'CurrentRace'

    $deadlineSib = (Get-Date).AddSeconds(8)
    $siblingDead = $false; $hostDead = $false
    while ((Get-Date) -lt $deadlineSib) {
        if (-not (Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)) { $siblingDead = $true }
        if (-not (Get-Process -Id $hostPid -ErrorAction SilentlyContinue)) { $hostDead = $true }
        if ($siblingDead -and $hostDead) { break }
        Start-Sleep -Milliseconds 150
    }
    $currentAliveAfterSib = [bool](Get-Process -Id $currentPid -ErrorAction SilentlyContinue)

    Assert $siblingDead "Sibling mode killed sibling tunnel pid=$siblingPid"
    Assert $hostDead "Sibling mode killed Connect UI host pid=$hostPid"
    Assert $currentAliveAfterSib "Sibling mode left current tunnel pid=$currentPid alive"
    Assert (-not (Test-Path -LiteralPath $markPath)) 'slot marker cleared after Sibling clean'
    Note ("Sibling clean tunnels=$($sib.SiblingTunnels) connects=$($sib.SiblingConnects) cursor=$($sib.CursorWindows)")
} catch {
    if ("$($_.Exception.Message)" -ne 'setup') {
        Write-Host ("  FAIL  exception: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $Fail++
    }
} finally {
    if ($ps) {
        try {
            $sync.Cmd = 'stop'
            if ($asyncHandle) { try { [void]$ps.EndInvoke($asyncHandle) } catch { } }
        } catch { }
        try { $ps.Dispose() } catch { }
    }
    if ($rs) {
        try { $rs.Close() } catch { }
        try { $rs.Dispose() } catch { }
    }
    if ($barrier) { try { $barrier.Dispose() } catch { } }
    foreach ($p in @($orphanPid, $siblingPid, $currentPid, $hostPid)) {
        if ($p -gt 0) { try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { } }
    }
    foreach ($proc in @($orphanProc, $currentProc, $hostProc)) {
        if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
    }
    Start-Sleep -Milliseconds 200
    Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARD LIVE hygiene-race RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Green
    exit 0
}
Write-Host ("HARD LIVE hygiene-race RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
exit 1
