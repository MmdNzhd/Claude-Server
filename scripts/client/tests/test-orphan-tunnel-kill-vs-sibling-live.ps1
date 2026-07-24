# test-orphan-tunnel-kill-vs-sibling-live.ps1 - LIVE: Remove-LocalOrphanTunnel must kill a real
# unprotected ssh.exe -R tunnel process (no connect.ps1-shaped ancestor = orphan) while leaving
# a real sibling ssh.exe -R tunnel process alone (has a connect.ps1-shaped ancestor, per the
# actual Get-SiblingConnectTunnelPids parent-chain walk) - exercising the real function bodies
# extracted verbatim from git-mode.ps1 against real OS processes, not mocks.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Orphan-vs-sibling tunnel kill (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
foreach ($n in @('Write-GitModeLog', 'Clear-TunnelBannerCache', 'Get-TunnelProcessExitCode', 'Stop-TunnelProcessWithExitLog', 'Get-LocalTunnelSshPids', 'Test-ProcessCommandIsConnectUi', 'Get-SiblingConnectTunnelPids', 'Remove-LocalOrphanTunnel')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

$Port = Get-Random -Minimum 45000 -Maximum 45999

$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-orphan-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$dirOrphanSsh  = Join-Path $tmpRoot 'orphan'
$dirSiblingSsh = Join-Path $tmpRoot 'sibling'
$dirHost       = Join-Path $tmpRoot 'host'
foreach ($d in @($dirOrphanSsh, $dirSiblingSsh, $dirHost)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$sshStubOrphanExe  = Join-Path $dirOrphanSsh 'ssh.exe'
$sshStubSiblingExe = Join-Path $dirSiblingSsh 'ssh.exe'
$connectHostExe    = Join-Path $dirHost 'fake-connect-host.exe'

$pidFileOrphan       = Join-Path $tmpRoot 'orphan.pid'
$pidFileConnectHost  = Join-Path $tmpRoot 'host.pid'
$pidFileSiblingChild = Join-Path $tmpRoot 'sibling.pid'

# Same stub binary for both ssh.exe decoys: sleeps forever, writes its own PID to the path
# given after a "--pidfile" flag so the test can find it without relying on Start-Process's
# own PID for the sibling (which is spawned indirectly by the host stub, not by this script).
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

# Host stub: its own command line contains a fake "...\connect.ps1" path (what
# Test-ProcessCommandIsConnectUi actually greps for), and it spawns the sibling ssh.exe stub
# as its REAL OS child process - reproducing the exact OS-level precondition that
# Get-SiblingConnectTunnelPids's parent-chain walk inspects, without faking the check itself.
$connectHostSrc = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
class FakeConnectHost {
    static void Main(string[] args) {
        // args[0]=sshStubExePath args[1]=selfPidFile args[2]=childPidFile args[3]=port
        try {
            File.WriteAllText(args[1], Process.GetCurrentProcess().Id.ToString());
        } catch { }
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
    Add-Type -Language CSharp -TypeDefinition $sshStubSrc -OutputType ConsoleApplication -OutputAssembly $sshStubOrphanExe -ErrorAction Stop
    Copy-Item -LiteralPath $sshStubOrphanExe -Destination $sshStubSiblingExe -Force
    Add-Type -Language CSharp -TypeDefinition $connectHostSrc -OutputType ConsoleApplication -OutputAssembly $connectHostExe -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile decoy stubs: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Assert (Test-Path -LiteralPath $sshStubOrphanExe) 'orphan decoy ssh.exe compiled to a real binary'
Assert (Test-Path -LiteralPath $sshStubSiblingExe) 'sibling decoy ssh.exe (separate dir, same name) is a real binary'
Assert (Test-Path -LiteralPath $connectHostExe) 'fake connect.ps1-shaped host stub compiled to a real binary'

$orphanProc = $null
$connectHostProc = $null
$orphanPid = 0
$siblingPid = 0
$hostPid = 0
try {
    # Scenario 1: orphan - a real ssh.exe -R <port>:localhost:22 process spawned directly as
    # a child of THIS test process, which has no connect.ps1-shaped ancestor anywhere in its
    # parent chain (the test script's own powershell.exe command line names this test file,
    # not connect.ps1/connect-boot.ps1) -> Get-SiblingConnectTunnelPids must not classify it
    # as a sibling, so Remove-LocalOrphanTunnel must kill it.
    $orphanProc = Start-Process -FilePath $sshStubOrphanExe -ArgumentList @('-R', "${Port}:localhost:22", '-N', '-o', 'ExitOnForwardFailure=yes', 'fakeuser@laptophost', '--pidfile', $pidFileOrphan) -WindowStyle Hidden -PassThru

    # Scenario 2: sibling - a real ssh.exe -R <port>:localhost:22 process spawned as a REAL
    # OS child of a real live process whose own command line matches the connect.ps1 pattern
    # Test-ProcessCommandIsConnectUi checks for -> Get-SiblingConnectTunnelPids's parent-walk
    # must find that ancestor and classify the ssh pid as a sibling, so Remove-LocalOrphanTunnel
    # must leave it running.
    $connectHostProc = Start-Process -FilePath $connectHostExe -ArgumentList @($sshStubSiblingExe, $pidFileConnectHost, $pidFileSiblingChild, "$Port", 'C:\FakeConnectClient\connect.ps1') -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path $pidFileOrphan) -and (Test-Path $pidFileConnectHost) -and (Test-Path $pidFileSiblingChild))) {
        Start-Sleep -Milliseconds 200
    }

    $sawOrphan = (Test-Path -LiteralPath $pidFileOrphan) -and [int]::TryParse((Get-Content -LiteralPath $pidFileOrphan -Raw -ErrorAction SilentlyContinue), [ref]$orphanPid)
    Assert $sawOrphan 'orphan decoy ssh.exe actually started and reported its own PID (real process, not a mock)'

    $sawHost = (Test-Path -LiteralPath $pidFileConnectHost) -and [int]::TryParse((Get-Content -LiteralPath $pidFileConnectHost -Raw -ErrorAction SilentlyContinue), [ref]$hostPid)
    Assert $sawHost 'fake connect.ps1-shaped host actually started and reported its own PID'

    $sawSibling = (Test-Path -LiteralPath $pidFileSiblingChild) -and [int]::TryParse((Get-Content -LiteralPath $pidFileSiblingChild -Raw -ErrorAction SilentlyContinue), [ref]$siblingPid)
    Assert $sawSibling 'sibling decoy ssh.exe actually started (spawned by the host, real process, not a mock)'

    if (-not ($sawOrphan -and $sawHost -and $sawSibling)) {
        Write-Host '  FAIL  decoy setup incomplete - aborting before exercising the real function' -ForegroundColor Red
        $script:fail++
    } else {
        # Confirm the real OS-level precondition before trusting the function under test:
        # the sibling ssh.exe's actual Win32 parent must really be the fake connect.ps1 host.
        Start-Sleep -Milliseconds 300
        $siblingCim = Get-CimInstance Win32_Process -Filter "ProcessId=$siblingPid" -ErrorAction SilentlyContinue
        Assert ($siblingCim -and [int]$siblingCim.ParentProcessId -eq $hostPid) "sibling decoy's real Win32 parent process id is the fake connect.ps1 host (got parent=$($siblingCim.ParentProcessId), expected=$hostPid)"

        $foundPids = @(Get-LocalTunnelSshPids -TargetPort $Port)
        Assert ($foundPids -contains $orphanPid) "Get-LocalTunnelSshPids finds the orphan decoy pid=$orphanPid for port=$Port"
        Assert ($foundPids -contains $siblingPid) "Get-LocalTunnelSshPids finds the sibling decoy pid=$siblingPid for port=$Port"

        $siblingsPre = @(Get-SiblingConnectTunnelPids -TargetPort $Port)
        Assert ($siblingsPre -contains $siblingPid) "Get-SiblingConnectTunnelPids classifies pid=$siblingPid as a sibling (real parent-chain walk found the connect.ps1-shaped ancestor)"
        Assert (-not ($siblingsPre -contains $orphanPid)) "Get-SiblingConnectTunnelPids does NOT classify the orphan pid=$orphanPid as a sibling"

        # Exercise the real function under test.
        Remove-LocalOrphanTunnel -TargetPort $Port | Out-Null

        $deadline2 = (Get-Date).AddSeconds(6)
        $orphanDead = $false
        while ((Get-Date) -lt $deadline2) {
            if (-not (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) { $orphanDead = $true; break }
            Start-Sleep -Milliseconds 200
        }
        $siblingAlive = [bool](Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)

        Assert $orphanDead "Remove-LocalOrphanTunnel killed the real orphan ssh.exe pid=$orphanPid (no connect.ps1 ancestor)"
        Assert $siblingAlive "Remove-LocalOrphanTunnel left the real sibling ssh.exe pid=$siblingPid alone (has a connect.ps1-shaped ancestor)"
    }
} finally {
    # Forcibly kill every decoy unconditionally, regardless of what the function under test did.
    foreach ($p in @($orphanPid, $siblingPid, $hostPid)) {
        if ($p -and $p -gt 0) {
            try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    foreach ($proc in @($orphanProc, $connectHostProc)) {
        if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
    }
    Start-Sleep -Milliseconds 300
    $strayOrphan = ($orphanPid -gt 0) -and [bool](Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)
    $straySibling = ($siblingPid -gt 0) -and [bool](Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)
    $strayHost = ($hostPid -gt 0) -and [bool](Get-Process -Id $hostPid -ErrorAction SilentlyContinue)
    Assert (-not $strayOrphan) "final cleanup check: orphan decoy pid=$orphanPid does not survive the test"
    Assert (-not $straySibling) "final cleanup check: sibling decoy pid=$siblingPid does not survive the test (killed by test cleanup, not by the code under test)"
    Assert (-not $strayHost) "final cleanup check: fake connect.ps1-shaped host pid=$hostPid does not survive the test"
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
