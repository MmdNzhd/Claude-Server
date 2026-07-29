#Requires -Version 5.1
# LIVE adversarial: Soft reclaim kills real orphan -R, leaves real sibling -R + current -R;
# Sibling clean then kills sibling tunnel + fake Connect UI host; never current; never Close-Cursor
# on personal/current (Close-Cursor stubbed so we never touch real Cursor windows).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Hygiene Soft-vs-Sibling LIVE (adversarial) ===' -ForegroundColor Cyan

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
foreach ($n in $need) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Isolated marker dir (never touch user session-slot-*.json).
# Override AFTER extract so marker helpers never write into the real ~/.config tree.
$script:CfgDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-hygiene-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$CfgDir = $script:CfgDir
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null

# High ephemeral base so Soft's 10-port scan never touches real 20000+ Connect tunnels.
$script:Base = Get-Random -Minimum 46000 -Maximum 46990
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
    if ($joined -match 'cursor-server-reaper') { return 'REAPER_OK_LIVE' }
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
class SshStubHang {
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
class FakeConnectHost {
    static void Main(string[] args) {
        // args: sshExe selfPid childPid port connectPs1Path
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
    Write-Host "  FAIL  compile decoys: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$portCurrent = $Base + 0
$portSibling = $Base + 1
$portOrphan = $Base + 2
$orphanPid = 0; $siblingPid = 0; $currentPid = 0; $hostPid = 0
$orphanProc = $null; $currentProc = $null; $hostProc = $null

try {
    # Current session tunnel (no Connect UI ancestor) — protected via SessionBgTunnel.
    $currentProc = Start-Process -FilePath $sshCurrentExe -ArgumentList @(
        '-R', "${portCurrent}:localhost:22", '-N', '-o', 'ExitOnForwardFailure=yes',
        'fakeuser@laptophost', '--pidfile', $pidCurrent
    ) -WindowStyle Hidden -PassThru

    # Orphan tunnel — Soft must kill.
    $orphanProc = Start-Process -FilePath $sshOrphanExe -ArgumentList @(
        '-R', "${portOrphan}:localhost:22", '-N', '-o', 'ExitOnForwardFailure=yes',
        'fakeuser@laptophost', '--pidfile', $pidOrphan
    ) -WindowStyle Hidden -PassThru

    # Sibling: fake connect.ps1-shaped host + child -R — Soft must leave; Sibling must kill.
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
    Assert $okCur "current decoy started pid=$currentPid port=$portCurrent"
    Assert $okOr "orphan decoy started pid=$orphanPid port=$portOrphan"
    Assert $okHost "sibling Connect-UI decoy started pid=$hostPid"
    Assert $okSib "sibling tunnel decoy started pid=$siblingPid port=$portSibling"
    if (-not ($okCur -and $okOr -and $okHost -and $okSib)) {
        Write-Host '  FAIL  decoy setup incomplete' -ForegroundColor Red
        $script:fail++
        throw 'setup'
    }

    Start-Sleep -Milliseconds 250
    $sibCim = Get-CimInstance Win32_Process -Filter "ProcessId=$siblingPid" -ErrorAction SilentlyContinue
    Assert ($sibCim -and [int]$sibCim.ParentProcessId -eq $hostPid) "sibling tunnel parent is fake connect host ($hostPid)"

    $script:SessionBgTunnel = Get-Process -Id $currentPid -ErrorAction Stop
    Write-ConnectSessionSlotMarker -Slot 1 -Port $portSibling -ProjectId 'SiblingLive' -RemotePath 'D:\work\SiblingLive' -ProcessId $hostPid
    $markPath = Get-ConnectSessionSlotMarkerPath -Slot 1
    Assert (Test-Path -LiteralPath $markPath) "slot marker file exists at $markPath"
    $marks = @(Get-ConnectSessionSlotMarkers)
    Assert ($marks.Count -ge 1 -and $marks[0].ProjectId -eq 'SiblingLive') "slot marker readable ProjectId=SiblingLive (count=$($marks.Count))"

    $report = Get-ConnectHygieneReport -UidStr '1000' -ProtectRemotePath 'D:\work\CurrentLive' -ProtectProjectId 'CurrentLive' -SkipServer
    $byPort = @{}
    foreach ($t in @($report.Tunnels)) { $byPort[[int]$t.Port] = $t }

    Assert ($byPort.ContainsKey($portCurrent) -and $byPort[$portCurrent].Class -eq 'current') "report classifies port=$portCurrent as current"
    Assert ($byPort.ContainsKey($portSibling) -and $byPort[$portSibling].Class -eq 'sibling') "report classifies port=$portSibling as sibling"
    Assert ($byPort.ContainsKey($portOrphan) -and $byPort[$portOrphan].Class -eq 'orphan') "report classifies port=$portOrphan as orphan"
    Assert ($report.SoftTargetCount -ge 1) "SoftTargetCount>=1 (got $($report.SoftTargetCount))"
    Assert ($report.SiblingCount -ge 1) "SiblingCount>=1 (got $($report.SiblingCount))"
    Assert ($byPort[$portSibling].ConnectUiPid -eq $hostPid) "sibling ConnectUiPid resolves to fake host $hostPid"
    Assert ($byPort[$portSibling].ProjectId -eq 'SiblingLive') "sibling report carries ProjectId=SiblingLive from marker"
    Assert ($byPort[$portSibling].RemotePath -match 'SiblingLive') "sibling report carries RemotePath from marker"

    # --- Soft ---
    $script:cursorCloses.Clear()
    $soft = Invoke-ConnectHygieneClean -Mode Soft -Report $report -ProtectRemotePath 'D:\work\CurrentLive' -ProtectProjectId 'CurrentLive'

    $deadlineSoft = (Get-Date).AddSeconds(8)
    $orphanDead = $false
    while ((Get-Date) -lt $deadlineSoft) {
        if (-not (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) { $orphanDead = $true; break }
        Start-Sleep -Milliseconds 150
    }
    $siblingAliveAfterSoft = [bool](Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)
    $currentAliveAfterSoft = [bool](Get-Process -Id $currentPid -ErrorAction SilentlyContinue)
    $hostAliveAfterSoft = [bool](Get-Process -Id $hostPid -ErrorAction SilentlyContinue)

    Assert $orphanDead "LIVE Soft killed orphan tunnel pid=$orphanPid"
    Assert $siblingAliveAfterSoft "LIVE Soft left sibling tunnel pid=$siblingPid alive"
    Assert $currentAliveAfterSoft "LIVE Soft left current tunnel pid=$currentPid alive"
    Assert $hostAliveAfterSoft "LIVE Soft left sibling Connect UI host pid=$hostPid alive"
    Assert ($script:cursorCloses.Count -eq 0) 'LIVE Soft never called Close-CursorProjectWindows'
    Assert ($script:sshxCalls -ge 1) 'LIVE Soft attempted fail-open server SshX path'

    # --- Sibling ---
    $report2 = Get-ConnectHygieneReport -UidStr '1000' -ProtectRemotePath 'D:\work\CurrentLive' -ProtectProjectId 'CurrentLive' -SkipServer
    Assert ($report2.SiblingCount -ge 1) "after Soft, siblings remain (got $($report2.SiblingCount))"
    Assert ($report2.SoftTargetCount -eq 0 -or -not (@($report2.Tunnels | Where-Object { $_.Class -eq 'orphan' -and $_.TunnelPid -eq $orphanPid }).Count)) 'orphan gone from report after Soft'

    $script:cursorCloses.Clear()
    $sib = Invoke-ConnectHygieneClean -Mode Sibling -Report $report2 -ProtectRemotePath 'D:\work\CurrentLive' -ProtectProjectId 'CurrentLive'

    $deadlineSib = (Get-Date).AddSeconds(8)
    $siblingDead = $false
    $hostDead = $false
    while ((Get-Date) -lt $deadlineSib) {
        if (-not (Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)) { $siblingDead = $true }
        if (-not (Get-Process -Id $hostPid -ErrorAction SilentlyContinue)) { $hostDead = $true }
        if ($siblingDead -and $hostDead) { break }
        Start-Sleep -Milliseconds 150
    }
    $currentAliveAfterSib = [bool](Get-Process -Id $currentPid -ErrorAction SilentlyContinue)

    Assert $siblingDead "LIVE Sibling killed sibling tunnel pid=$siblingPid"
    Assert $hostDead "LIVE Sibling killed sibling Connect UI host pid=$hostPid"
    Assert $currentAliveAfterSib "LIVE Sibling left current tunnel pid=$currentPid alive"
    Assert ($script:cursorCloses.Count -eq 1) 'LIVE Sibling closed exactly one Cursor project window (stub)'
    Assert ($script:cursorCloses[0] -match '^SiblingLive\|protect=CurrentLive$') 'LIVE Sibling Cursor close targeted SiblingLive protecting CurrentLive'
    Assert ($sib.SiblingTunnels -ge 1) "LIVE SiblingTunnels>=1 (got $($sib.SiblingTunnels))"
    Assert ($sib.SiblingConnects -ge 1) "LIVE SiblingConnects>=1 (got $($sib.SiblingConnects))"

    # Adversarial: Soft again must not resurrect kills / must not touch current
    $report3 = Get-ConnectHygieneReport -UidStr '1000' -ProtectRemotePath 'D:\work\CurrentLive' -SkipServer
    Assert ($report3.SiblingCount -eq 0) 'after Sibling clean, no sibling tunnels remain'
    $script:cursorCloses.Clear()
    $null = Invoke-ConnectHygieneClean -Mode Soft -Report $report3
    Assert ([bool](Get-Process -Id $currentPid -ErrorAction SilentlyContinue)) 'second Soft still leaves current tunnel alive'
    Assert ($script:cursorCloses.Count -eq 0) 'second Soft still never closes Cursor'
} catch {
    if ("$($_.Exception.Message)" -ne 'setup') {
        Write-Host "  FAIL  exception: $($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
    }
} finally {
    foreach ($p in @($orphanPid, $siblingPid, $currentPid, $hostPid)) {
        if ($p -gt 0) { try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { } }
    }
    foreach ($proc in @($orphanProc, $currentProc, $hostProc)) {
        if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
    }
    Start-Sleep -Milliseconds 200
    Assert (-not ($currentPid -gt 0 -and (Get-Process -Id $currentPid -ErrorAction SilentlyContinue))) "cleanup: current decoy gone"
    Assert (-not ($orphanPid -gt 0 -and (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue))) "cleanup: orphan decoy gone"
    Assert (-not ($siblingPid -gt 0 -and (Get-Process -Id $siblingPid -ErrorAction SilentlyContinue))) "cleanup: sibling decoy gone"
    Assert (-not ($hostPid -gt 0 -and (Get-Process -Id $hostPid -ErrorAction SilentlyContinue))) "cleanup: host decoy gone"
    Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
