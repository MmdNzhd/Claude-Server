#Requires -Version 5.1
# test-harder-live-orphan-tunnel.ps1 - HARD LIVE Remove-LocalOrphanTunnel (git-mode.ps1 extract):
# decoy ssh.exe orphans vs connect.ps1-shaped siblings, parallel double-call safety,
# Get-SiblingConnectTunnelPids classification, skip_sibling log string contracts.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
$pass = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) {
        Write-Host "  PASS  $msg" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL  $msg" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host ''
Write-Host '=== HARD LIVE orphan tunnel (Remove-LocalOrphanTunnel) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$fnNames = @(
    'Clear-TunnelBannerCache', 'Get-TunnelProcessExitCode', 'Stop-TunnelProcessWithExitLog',
    'Get-LocalTunnelSshPids', 'Test-ProcessCommandIsConnectUi', 'Get-SiblingConnectTunnelPids',
    'Remove-LocalOrphanTunnel'
)
$extracted = @{}
foreach ($n in $fnNames) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    $extracted[$n] = $src
}

# --- A) Source string contracts (skip_sibling / skip_current / kill) ---
$orphanSrc = $extracted['Remove-LocalOrphanTunnel']
Assert ($orphanSrc -match 'ORPHAN_TUNNEL: skip_sibling') 'source contract: skip_sibling log token present'
Assert ($orphanSrc -match 'ORPHAN_TUNNEL: skip_current') 'source contract: skip_current log token present'
Assert ($orphanSrc -match 'ORPHAN_TUNNEL: kill pid=\$processId port=\$TargetPort reason=unprotected_live') `
    'source contract: unprotected_live kill log token present'
Assert ($extracted['Get-SiblingConnectTunnelPids'] -match 'hops -lt 14') `
    'source contract: sibling walk capped at 14 hops'

# --- B) Dot-source extracted bodies with log capture ---
$script:GitModeLogLines = New-Object System.Collections.Generic.List[string]
function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    [void]$script:GitModeLogLines.Add(("{0}|{1}" -f $Level, $Message))
}
foreach ($n in $fnNames) { . ([scriptblock]::Create($extracted[$n])) }

$Port = Get-Random -Minimum 47000 -Maximum 47999
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-harder-orphan-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
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
    Add-Type -Language CSharp -TypeDefinition $sshStubSrc -OutputType ConsoleApplication -OutputAssembly $sshStubOrphanExe -ErrorAction Stop
    Copy-Item -LiteralPath $sshStubOrphanExe -Destination $sshStubSiblingExe -Force
    Add-Type -Language CSharp -TypeDefinition $connectHostSrc -OutputType ConsoleApplication -OutputAssembly $connectHostExe -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile decoy stubs: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Assert (Test-Path -LiteralPath $sshStubOrphanExe) 'decoy orphan ssh.exe compiled (Name=ssh.exe for CIM filter)'
Assert (Test-Path -LiteralPath $connectHostExe) 'decoy connect.ps1-shaped host compiled'

$orphanProc = $null
$connectHostProc = $null
$orphanPid = 0
$siblingPid = 0
$hostPid = 0

try {
    $orphanProc = Start-Process -FilePath $sshStubOrphanExe -ArgumentList @(
        '-R', "${Port}:localhost:22", '-N', '-o', 'ExitOnForwardFailure=yes', 'fakeuser@laptophost', '--pidfile', $pidFileOrphan
    ) -WindowStyle Hidden -PassThru

    $connectHostProc = Start-Process -FilePath $connectHostExe -ArgumentList @(
        $sshStubSiblingExe, $pidFileConnectHost, $pidFileSiblingChild, "$Port", 'C:\FakeConnectClient\connect.ps1'
    ) -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path $pidFileOrphan) -and (Test-Path $pidFileConnectHost) -and (Test-Path $pidFileSiblingChild))) {
        Start-Sleep -Milliseconds 200
    }

    $sawOrphan = (Test-Path -LiteralPath $pidFileOrphan) -and [int]::TryParse((Get-Content -LiteralPath $pidFileOrphan -Raw -ErrorAction SilentlyContinue), [ref]$orphanPid)
    $sawHost = (Test-Path -LiteralPath $pidFileConnectHost) -and [int]::TryParse((Get-Content -LiteralPath $pidFileConnectHost -Raw -ErrorAction SilentlyContinue), [ref]$hostPid)
    $sawSibling = (Test-Path -LiteralPath $pidFileSiblingChild) -and [int]::TryParse((Get-Content -LiteralPath $pidFileSiblingChild -Raw -ErrorAction SilentlyContinue), [ref]$siblingPid)
    Assert $sawOrphan 'orphan decoy ssh.exe started (real process, no connect.ps1 ancestor)'
    Assert ($sawHost -and $sawSibling) 'sibling decoy ssh.exe started under connect.ps1-shaped host'

    if ($sawOrphan -and $sawHost -and $sawSibling) {
        Start-Sleep -Milliseconds 300
        $siblingCim = Get-CimInstance Win32_Process -Filter "ProcessId=$siblingPid" -ErrorAction SilentlyContinue
        Assert ($siblingCim -and [int]$siblingCim.ParentProcessId -eq $hostPid) `
            "sibling Win32 parent is connect-shaped host (parent=$($siblingCim.ParentProcessId) expected=$hostPid)"

        $foundPids = @(Get-LocalTunnelSshPids -TargetPort $Port)
        Assert ($foundPids -contains $orphanPid) "Get-LocalTunnelSshPids finds orphan pid=$orphanPid on port=$Port"
        Assert ($foundPids -contains $siblingPid) "Get-LocalTunnelSshPids finds sibling pid=$siblingPid on port=$Port"

        $siblingsPre = @(Get-SiblingConnectTunnelPids -TargetPort $Port)
        Assert ($siblingsPre -contains $siblingPid) "Get-SiblingConnectTunnelPids returns sibling pid=$siblingPid"
        Assert (-not ($siblingsPre -contains $orphanPid)) "Get-SiblingConnectTunnelPids excludes orphan pid=$orphanPid"

        # Parallel double-call: two jobs invoke the real function body against the same live decoys.
        $fnBlock = ($fnNames | ForEach-Object { $extracted[$_] }) -join "`n"
        $jobScript = {
            param([string]$FnBlock, [int]$TargetPort)
            $ErrorActionPreference = 'Continue'
            $script:GitModeLogLines = New-Object System.Collections.Generic.List[string]
            function Write-GitModeLog {
                param([string]$Message, [string]$Level = 'INFO')
                [void]$script:GitModeLogLines.Add(("{0}|{1}" -f $Level, $Message))
            }
            Invoke-Expression $FnBlock
            Remove-LocalOrphanTunnel -TargetPort $TargetPort | Out-Null
            ,@($script:GitModeLogLines.ToArray())
        }
        $jobs = @(
            (Start-Job -ScriptBlock $jobScript -ArgumentList $fnBlock, $Port),
            (Start-Job -ScriptBlock $jobScript -ArgumentList $fnBlock, $Port)
        )
        $jobOut = @($jobs | Wait-Job -Timeout 30 | Receive-Job)
        $jobs | Remove-Job -Force -ErrorAction SilentlyContinue

        $deadline2 = (Get-Date).AddSeconds(6)
        $orphanDead = $false
        while ((Get-Date) -lt $deadline2) {
            if (-not (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) { $orphanDead = $true; break }
            Start-Sleep -Milliseconds 200
        }
        $siblingAlive = [bool](Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)
        Assert $orphanDead "parallel double-call: orphan pid=$orphanPid killed"
        Assert $siblingAlive "parallel double-call: sibling pid=$siblingPid kept alive"

        $allLogs = @($script:GitModeLogLines)
        foreach ($batch in @($jobOut)) {
            if ($null -eq $batch) { continue }
            foreach ($line in @($batch)) {
                if ($line -is [string] -and $line.Length -gt 0) { $allLogs += $line }
            }
        }

        $skipSiblingLines = @($allLogs | Where-Object { $_ -match '\|ORPHAN_TUNNEL: skip_sibling ' })
        $killLines = @($allLogs | Where-Object { $_ -match '\|ORPHAN_TUNNEL: kill pid=' })
        Assert ($skipSiblingLines.Count -ge 1) 'skip_sibling log contract: at least one skip_sibling line emitted'
        Assert (@($skipSiblingLines | Where-Object { $_ -match "skip_sibling pid=$siblingPid port=$Port" }).Count -ge 1) `
            "skip_sibling log contract: names sibling pid=$siblingPid port=$Port"
        Assert (@($killLines | Where-Object { $_ -match "kill pid=$orphanPid port=$Port reason=unprotected_live" }).Count -ge 1) `
            "kill log contract: orphan pid=$orphanPid port=$Port reason=unprotected_live"
        Assert (-not (@($killLines | Where-Object { $_ -match "kill pid=$siblingPid" }).Count -ge 1)) `
            'kill log contract: sibling pid never appears in kill lines'

        $ret = Remove-LocalOrphanTunnel -TargetPort $Port
        Assert ($ret -eq $true) 'Remove-LocalOrphanTunnel returns $true (idempotent second pass)'
        Assert ([bool](Get-Process -Id $siblingPid -ErrorAction SilentlyContinue)) `
            'idempotent re-call: sibling still alive after orphan already gone'
    }
} finally {
    foreach ($p in @($orphanPid, $siblingPid, $hostPid)) {
        if ($p -and $p -gt 0) {
            try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    foreach ($proc in @($orphanProc, $connectHostProc)) {
        if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
    }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -eq 0) { exit 0 }
exit 1
