# cursor-proxy-sidecar.ps1 - sticky local front door for Cursor CLI/settings
# Listens 127.0.0.1:18999 (SOCKS) -> backend 19080; 18998 (HTTP) -> 19180.
# Dot-sourced by connect.ps1. Mutex ensures one sidecar per machine.

$script:CursorSocksFrontPort = 18999
$script:CursorHttpFrontPort = 18998


# #14: Job Object bound to Connect-spawned sidecar/watchdog tree only (KILL_ON_JOB_CLOSE).
# Never assign foreign PowerShell processes.
$script:CursorProxySidecarJob = $null

function Initialize-CursorProxySidecarJob {
    if ($script:CursorProxySidecarJob) { return $true }
    try {
        if (-not ('ClaudeConnect.SidecarJob' -as [type])) {
            Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ClaudeConnectSidecarJob {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr hObject);
  [StructLayout(LayoutKind.Sequential)]
  public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
    public long PerProcessUserTimeLimit;
    public long PerJobUserTimeLimit;
    public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize;
    public UIntPtr MaximumWorkingSetSize;
    public uint ActiveProcessLimit;
    public UIntPtr Affinity;
    public uint PriorityClass;
    public uint SchedulingClass;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct IO_COUNTERS {
    public ulong ReadOperationCount;
    public ulong WriteOperationCount;
    public ulong OtherOperationCount;
    public ulong ReadTransferCount;
    public ulong WriteTransferCount;
    public ulong OtherTransferCount;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
    public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
    public IO_COUNTERS IoInfo;
    public UIntPtr ProcessMemoryLimit;
    public UIntPtr JobMemoryLimit;
    public UIntPtr PeakProcessMemoryUsed;
    public UIntPtr PeakJobMemoryUsed;
  }
  public const int JobObjectExtendedLimitInformation = 9;
  public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
  public static IntPtr CreateKillOnCloseJob() {
    IntPtr h = CreateJobObject(IntPtr.Zero, null);
    if (h == IntPtr.Zero) return IntPtr.Zero;
    var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
    IntPtr ptr = Marshal.AllocHGlobal(len);
    try {
      Marshal.StructureToPtr(info, ptr, false);
      if (!SetInformationJobObject(h, JobObjectExtendedLimitInformation, ptr, (uint)len)) {
        CloseHandle(h);
        return IntPtr.Zero;
      }
    } finally { Marshal.FreeHGlobal(ptr); }
    return h;
  }
}
"@
        }
        $h = [ClaudeConnectSidecarJob]::CreateKillOnCloseJob()
        if ($h -eq [IntPtr]::Zero) { return $false }
        $script:CursorProxySidecarJob = $h
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_JOB created kill_on_close=1' 'INFO'
        }
        return $true
    } catch {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SIDECAR_JOB create_fail err={0}" -f $_.Exception.Message) 'WARN'
        }
        return $false
    }
}

function Add-CursorProxySidecarJobProcess {
    param([Parameter(Mandatory)]$Process)
    if (-not $Process) { return }
    if (-not (Initialize-CursorProxySidecarJob)) { return }
    try {
        $ok = [ClaudeConnectSidecarJob]::AssignProcessToJobObject(
            [IntPtr]$script:CursorProxySidecarJob,
            $Process.Handle
        )
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SIDECAR_JOB assign pid={0} ok={1}" -f $Process.Id, [int]$ok) 'DEBUG'
        }
    } catch {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SIDECAR_JOB assign_fail pid={0} err={1}" -f $Process.Id, $_.Exception.Message) 'DEBUG'
        }
    }
}

function Stop-CursorProxySidecarJob {
    if (-not $script:CursorProxySidecarJob) { return }
    try {
        [void][ClaudeConnectSidecarJob]::CloseHandle([IntPtr]$script:CursorProxySidecarJob)
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_JOB closed' 'INFO'
        }
    } catch {}
    $script:CursorProxySidecarJob = $null
}


if (-not ("ClaudeConnect.TcpRelay" -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public static class ClaudeConnectTcpRelay {
  public static void Run(int listenPort, int backendPort) {
    var listener = new TcpListener(IPAddress.Loopback, listenPort);
    listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
    listener.Start();
    while (true) {
      TcpClient client = null;
      try { client = listener.AcceptTcpClient(); } catch { Thread.Sleep(100); continue; }
      ThreadPool.QueueUserWorkItem(_ => {
        TcpClient remote = null;
        try {
          remote = new TcpClient();
          remote.Connect(IPAddress.Loopback, backendPort);
          var a = client.GetStream();
          var b = remote.GetStream();
          var t1 = a.CopyToAsync(b);
          var t2 = b.CopyToAsync(a);
          System.Threading.Tasks.Task.WaitAny(t1, t2);
        } catch { }
        finally {
          try { if (client != null) client.Close(); } catch { }
          try { if (remote != null) remote.Close(); } catch { }
        }
      });
    }
  }
}
"@
}

function Test-CursorProxySidecarListening {
    param([int]$Port)
    if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
        return [bool](Test-LocalPortOpen -PortNum $Port)
    }
    $c = $null
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect([System.Net.IPAddress]::Loopback, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(300)
        if (-not $ok) { return $false }
        try { $c.EndConnect($iar) } catch { return $false }
        return [bool]$c.Connected
    } catch { return $false }
    finally { if ($c) { try { $c.Close() } catch {} } }
}

function Start-TcpPortRelay {
    param(
        [Parameter(Mandatory)][int]$ListenPort,
        [Parameter(Mandatory)][int]$BackendPort,
        [Parameter(Mandatory)][string]$Name
    )
    if (Test-CursorProxySidecarListening -Port $ListenPort) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SIDECAR_START name={0} listen={1} backend={2} ok=1 reused=1" -f $Name, $ListenPort, $BackendPort) 'INFO'
        }
        return $true
    }
    if (-not $script:CursorProxySidecarPortMutexes) { $script:CursorProxySidecarPortMutexes = @{} }
    $mutexName = "Local\ClaudeConnectSidecar-$ListenPort"
    $created = $false
    $portMutex = $null
    try {
        $portMutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$created)
    } catch { $created = $true; $portMutex = $null }
    if (-not $created) {
        # Another owner already holds this port's mutex - never store a foreign handle.
        try { if ($portMutex) { $portMutex.Dispose() } } catch {}
        Start-Sleep -Milliseconds 500
        return (Test-CursorProxySidecarListening -Port $ListenPort)
    }
    # We created it (single-flight winner for this port) - hold the handle open for the
    # lifetime of this Connect process so Stop-CursorProxySidecarRelays can release it
    # on clean disconnect instead of leaking it to process exit.
    if ($portMutex -and -not $script:CursorProxySidecarPortMutexes.ContainsKey($ListenPort)) {
        $script:CursorProxySidecarPortMutexes[$ListenPort] = $portMutex
    }
    $arg = "-NoProfile -ExecutionPolicy Bypass -Command `"Add-Type -Language CSharp -TypeDefinition (Get-Content -Raw '%TEMP%\claude-connect-relay-type.cs'); [ClaudeConnectTcpRelay]::Run($ListenPort, $BackendPort)`""
    $cs = Join-Path $env:TEMP 'claude-connect-relay-type.cs'
    @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public static class ClaudeConnectTcpRelay {
  public static void Run(int listenPort, int backendPort) {
    var listener = new TcpListener(IPAddress.Loopback, listenPort);
    listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
    listener.Start();
    while (true) {
      TcpClient client = null;
      try { client = listener.AcceptTcpClient(); } catch { Thread.Sleep(100); continue; }
      ThreadPool.QueueUserWorkItem(_ => {
        TcpClient remote = null;
        try {
          remote = new TcpClient();
          remote.Connect(IPAddress.Loopback, backendPort);
          var a = client.GetStream();
          var b = remote.GetStream();
          var t1 = a.CopyToAsync(b);
          var t2 = b.CopyToAsync(a);
          System.Threading.Tasks.Task.WaitAny(t1, t2);
        } catch { }
        finally {
          try { if (client != null) client.Close(); } catch { }
          try { if (remote != null) remote.Close(); } catch { }
        }
      });
    }
  }
}
'@ | Set-Content -LiteralPath $cs -Encoding ASCII
    $ps1 = Join-Path $env:TEMP ("claude-connect-sidecar-{0}.ps1" -f $ListenPort)
    @"
`$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp -TypeDefinition (Get-Content -LiteralPath '$cs' -Raw)
[ClaudeConnectTcpRelay]::Run($ListenPort, $BackendPort)
"@ | Set-Content -LiteralPath $ps1 -Encoding UTF8
    try {
        $pRelay = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1
        )
        if ($pRelay -and (Get-Command Add-CursorProxySidecarJobProcess -ErrorAction SilentlyContinue)) {
            Add-CursorProxySidecarJobProcess -Process $pRelay
        }
    } catch {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog "SIDECAR_START_FAIL name=$Name port=$ListenPort err=$($_.Exception.Message)" 'WARN'
        }
        return $false
    }
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
        if (Test-CursorProxySidecarListening -Port $ListenPort) { break }
        Start-Sleep -Milliseconds 150
    }
    $ok = Test-CursorProxySidecarListening -Port $ListenPort
    if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
        Write-GitModeLog ("SIDECAR_START name={0} listen={1} backend={2} ok={3}" -f $Name, $ListenPort, $BackendPort, [int]$ok) 'INFO'
    }
    return $ok
}

function Get-CursorProxySettingsPath {
    $profileDir = if (Get-Command Get-CursorRemoteProfileDir -ErrorAction SilentlyContinue) {
        Get-CursorRemoteProfileDir
    } else {
        Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    }
    return (Join-Path (Join-Path $profileDir 'User') 'settings.json')
}

function Repair-CursorProxySettingsToSidecar {
    # Force settings.json onto sticky HTTP front (18998). Safe with windows open (no soft-stop).
    # ONLY call when 18998 is actually listening - otherwise Cursor chat dies with
    # "Failed to establish a socket connection to proxies: PROXY 127.0.0.1:18998".
    if (-not (Test-CursorProxySidecarListening -Port 18998)) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'CURSOR_PROXY_REPAIR skip reason=18998_not_listening' 'WARN'
        }
        return $false
    }
    $settingsPath = Get-CursorProxySettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $false }
    try {
        $obj = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return $false }
    if (-not $obj) { return $false }
    $want = 'http://127.0.0.1:18998'
    $changed = $false
    foreach ($pair in @(@{N='http.proxy';V=$want}, @{N='https.proxy';V=$want})) {
        $prop = $obj.PSObject.Properties[$pair.N]
        if (-not $prop) { $obj | Add-Member -NotePropertyName $pair.N -NotePropertyValue $pair.V -Force; $changed = $true }
        elseif ("$($prop.Value)" -ne $pair.V) { $prop.Value = $pair.V; $changed = $true }
    }
    $support = $obj.PSObject.Properties['http.proxySupport']
    if (-not $support) { $obj | Add-Member -NotePropertyName 'http.proxySupport' -NotePropertyValue 'override' -Force; $changed = $true }
    elseif ("$($support.Value)" -ne 'override') { $support.Value = 'override'; $changed = $true }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'CURSOR_PROXY_REPAIR settings->18998' 'INFO'
        }
    }
    return $changed
}

function Clear-CursorProxySettingsSidecar {
    # Remove sticky 18998 proxy when sidecar/backend is down so Cursor can talk direct
    # instead of hard-failing every agent turn on a dead loopback proxy.
    # NEVER clear settings while server-profile Cursor windows are open - repair sidecar only
    # (CLEAR_SKIP). Clearing under an open window freezes chat/proxy mid-session.
    $nOpen = 0
    try {
        if (Get-Command Get-CursorProfileProcesses -ErrorAction SilentlyContinue) {
            $nOpen = @(Get-CursorProfileProcesses -ForceRefresh).Count
        }
    } catch { $nOpen = 0 }
    if ($nOpen -gt 0) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("CURSOR_PROXY_CLEAR_SKIP: reason=windows_open action=repair_sidecar_only profile_count={0}" -f $nOpen) 'WARN'
        }
        if (Get-Command Repair-CursorProxySettingsToSidecar -ErrorAction SilentlyContinue) {
            try { [void](Repair-CursorProxySettingsToSidecar) } catch {}
        }
        return $false
    }
    $settingsPath = Get-CursorProxySettingsPath
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $false }
    try {
        $obj = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return $false }
    if (-not $obj) { return $false }
    $changed = $false
    foreach ($name in @('http.proxy', 'https.proxy')) {
        $prop = $obj.PSObject.Properties[$name]
        if ($prop -and ("$($prop.Value)" -like "*127.0.0.1:18998*")) {
            $obj.PSObject.Properties.Remove($name)
            $changed = $true
        }
    }
    $support = $obj.PSObject.Properties['http.proxySupport']
    if ($support -and ("$($support.Value)" -eq 'override')) {
        $support.Value = 'off'
        $changed = $true
    }
    $mode = $obj.PSObject.Properties['cursor.general.proxyMode']
    if ($mode -and ("$($mode.Value)" -eq 'custom')) {
        $mode.Value = 'system'
        $changed = $true
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'CURSOR_PROXY_CLEAR removed_18998_dead_proxy' 'WARN'
        }
    }
    return $changed
}

function Start-CursorProxySidecar {
    $socksBack = 19080
    $httpBack = 19180
    if ($script:SocksProxyPort) { $socksBack = [int]$script:SocksProxyPort }
    if ($script:HttpProxyPort) { $httpBack = [int]$script:HttpProxyPort }
    $script:CursorSocksFrontPort = 18999
    $script:CursorHttpFrontPort = 18998
    $a = Start-TcpPortRelay -ListenPort 18999 -BackendPort $socksBack -Name 'socks'
    $b = Start-TcpPortRelay -ListenPort 18998 -BackendPort $httpBack -Name 'http'
    try { Start-LegacyCursorProxyRelays | Out-Null } catch {}
    $ok = ($a -and $b -and (Test-CursorProxySidecarListening -Port 18998))
    if ($ok) {
        try { Repair-CursorProxySettingsToSidecar | Out-Null } catch {}
        try { Start-CursorProxySidecarWatchdog | Out-Null } catch {}
    } else {
        # Never leave Cursor pointed at a dead 18998 front door.
        try { Clear-CursorProxySettingsSidecar | Out-Null } catch {}
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SIDECAR_START ok=0 socks={0} http={1}" -f [int]$a, [int]$b) 'WARN'
        }
    }
    return $ok
}

function Test-CursorProxyBackendOpen {
    $httpBack = 19180
    $socksBack = 19080
    if ($script:HttpProxyPort) { $httpBack = [int]$script:HttpProxyPort }
    if ($script:SocksProxyPort) { $socksBack = [int]$script:SocksProxyPort }
    $httpOk = Test-CursorProxySidecarListening -Port $httpBack
    $socksOk = Test-CursorProxySidecarListening -Port $socksBack
    return ($httpOk -and $socksOk)
}

function Ensure-CursorProxySidecar {
    # Cheap heal for open Cursor sessions: if sticky front is down, restart relays.
    # Only write settings->18998 when front AND backend -L ports are up (else Clear).
    if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
        Write-GitModeLog 'SIDECAR_ENSURE begin' 'DEBUG'
    }
    $frontOk = ((Test-CursorProxySidecarListening -Port 18998) -and (Test-CursorProxySidecarListening -Port 18999))
    if (-not $frontOk) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_ENSURE restarting_front_doors' 'WARN'
        }
        $frontOk = [bool](Start-CursorProxySidecar)
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("SIDECAR_ENSURE start_done ok={0}" -f [int]$frontOk) 'DEBUG'
        }
    }
    if (-not $frontOk) {
        try { Clear-CursorProxySettingsSidecar | Out-Null } catch {}
        return $false
    }
    if (-not (Test-CursorProxyBackendOpen)) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_ENSURE front_up backend_down clearing_settings' 'WARN'
        }
        try { Clear-CursorProxySettingsSidecar | Out-Null } catch {}
        return $false
    }
    try { Repair-CursorProxySettingsToSidecar | Out-Null } catch {}
    Start-CursorProxySidecarWatchdog | Out-Null
    return $true
}

function Start-CursorProxySidecarWatchdog {
    # Mid-session heal: Cursor stays open for hours; sidecar powershell can die and leave
    # settings pointed at a dead 18998. One watchdog per machine, enforced by an OS mutex
    # that this Connect process actually WAITS ON (WaitOne) and HOLDS for its own lifetime -
    # not just a "does the named object exist" check - so Stop-CursorProxySidecarWatchdog
    # can deterministically release it on clean disconnect and let the next Connect (or a
    # relaunch) start a fresh watchdog immediately instead of racing/blocking on a stale one.
    if ($script:CursorProxyWatchdogStarted) { return $true }
    $mutexName = 'Local\ClaudeConnectSidecarWatchdog'
    $created = $false
    $m = $null
    try { $m = New-Object System.Threading.Mutex($false, $mutexName, [ref]$created) } catch { return $false }
    if (-not $created) {
        # another owner holds it
        try { if ($m) { $m.Dispose() } } catch {}
        return $false
    }
    try {
        $got = $m.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] { $got = $true }
    if (-not $got) { try { $m.Dispose() } catch {}; return $false }
    $script:CursorProxyWatchdogMutex = $m
    $wd = Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.ps1'
    @'
$ErrorActionPreference = "Continue"
while ($true) {
    Start-Sleep -Seconds 20
    foreach ($pair in @(@{L=18998;B=19180}, @{L=18999;B=19080})) {
        $up = $false
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $iar = $c.BeginConnect([System.Net.IPAddress]::Loopback, $pair.L, $null, $null)
            $up = $iar.AsyncWaitHandle.WaitOne(250)
            if ($up) { try { $c.EndConnect($iar) } catch { $up = $false } }
            $c.Close()
        } catch { $up = $false }
        if ($up) { continue }
        # Front down: restart relay if backend still exists
        $backUp = $false
        try {
            $c2 = New-Object System.Net.Sockets.TcpClient
            $iar2 = $c2.BeginConnect([System.Net.IPAddress]::Loopback, $pair.B, $null, $null)
            $backUp = $iar2.AsyncWaitHandle.WaitOne(250)
            if ($backUp) { try { $c2.EndConnect($iar2) } catch { $backUp = $false } }
            $c2.Close()
        } catch { $backUp = $false }
        if (-not $backUp) { continue }
        $cs = Join-Path $env:TEMP "claude-connect-relay-type.cs"
        $ps1 = Join-Path $env:TEMP ("claude-connect-sidecar-{0}.ps1" -f $pair.L)
        if (-not (Test-Path -LiteralPath $ps1)) { continue }
        try {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ps1
            ) | Out-Null
        } catch {}
    }
}
'@ | Set-Content -LiteralPath $wd -Encoding UTF8
    try {
        $pWd = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wd
        )
        if ($pWd -and (Get-Command Add-CursorProxySidecarJobProcess -ErrorAction SilentlyContinue)) {
            Add-CursorProxySidecarJobProcess -Process $pWd
        }
        $script:CursorProxyWatchdogStarted = $true
        try {
            $lease = Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.lease'
            ("{0}|{1}" -f $PID, (Get-Date -Format o)) | Set-Content -LiteralPath $lease -Encoding ASCII
        } catch {}
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_WATCHDOG started' 'INFO'
        }
        return $true
    } catch {
        try { if ($script:CursorProxyWatchdogMutex) { $script:CursorProxyWatchdogMutex.ReleaseMutex() } } catch {}
        try { if ($script:CursorProxyWatchdogMutex) { $script:CursorProxyWatchdogMutex.Dispose() } } catch {}
        $script:CursorProxyWatchdogMutex = $null
        return $false
    }
}

function Stop-CursorProxySidecarWatchdog {
    # Clean disconnect only (wired from connect.ps1's finally, never-keepTunnelForEditor
    # branch). Releases the machine-wide watchdog mutex this process actually holds
    # (acquired via WaitOne in Start-CursorProxySidecarWatchdog), kills the detached
    # watchdog powershell.exe (matched by its TEMP script path in CommandLine - never a
    # blind powershell.exe kill), and removes its TEMP script + lease file so a future
    # Connect can start a fresh watchdog without waiting on a stale mutex or process.
    try {
        if ($script:CursorProxyWatchdogMutex) {
            try { $script:CursorProxyWatchdogMutex.ReleaseMutex() } catch {}
            try { $script:CursorProxyWatchdogMutex.Dispose() } catch {}
        }
    } catch {}
    $script:CursorProxyWatchdogMutex = $null
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [regex]::Escape('claude-connect-sidecar-watchdog.ps1') })
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
                    Write-GitModeLog ("SIDECAR_WATCHDOG_STOP pid={0}" -f $p.ProcessId) 'INFO'
                }
            } catch {}
        }
    } catch {}
    foreach ($f in @(
        (Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.ps1'),
        (Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.lease')
    )) {
        try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } catch {}
    }
    if (Get-Command Stop-CursorProxySidecarJob -ErrorAction SilentlyContinue) { try { Stop-CursorProxySidecarJob } catch {} }
    $script:CursorProxyWatchdogStarted = $false
    if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
        Write-GitModeLog 'SIDECAR_WATCHDOG_STOPPED' 'INFO'
    }
    return $true
}

function Stop-CursorProxySidecarRelays {
    # Clean disconnect only (wired from connect.ps1's finally, never-keepTunnelForEditor
    # branch). Kills ONLY the two sticky front-door relay powershell.exe processes,
    # matched by their TEMP script path in CommandLine (claude-connect-sidecar-18998.ps1 /
    # claude-connect-sidecar-18999.ps1) - never a blind "kill all powershell". Disposes the
    # port mutexes this process holds (opened, not owned - Dispose only, no ReleaseMutex)
    # and removes the matching TEMP relay scripts.
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -match [regex]::Escape('claude-connect-sidecar-18998.ps1') -or
                $_.CommandLine -match [regex]::Escape('claude-connect-sidecar-18999.ps1')
            })
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
                    Write-GitModeLog ("SIDECAR_RELAY_STOP pid={0}" -f $p.ProcessId) 'INFO'
                }
            } catch {}
        }
    } catch {}
    if ($script:CursorProxySidecarPortMutexes) {
        foreach ($key in @($script:CursorProxySidecarPortMutexes.Keys)) {
            $mx = $script:CursorProxySidecarPortMutexes[$key]
            # These handles were opened with initiallyOwned=$false and never WaitOne'd -
            # this process does not own them, so only Dispose (ReleaseMutex would throw).
            try { if ($mx) { $mx.Dispose() } } catch {}
        }
        $script:CursorProxySidecarPortMutexes = @{}
    }
    foreach ($f in @(
        (Join-Path $env:TEMP 'claude-connect-sidecar-18998.ps1'),
        (Join-Path $env:TEMP 'claude-connect-sidecar-18999.ps1')
    )) {
        try { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } } catch {}
    }
    if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
        Write-GitModeLog 'SIDECAR_RELAYS_STOPPED' 'INFO'
    }
    return $true
}

function Invoke-CursorProxySidecarBootReap {
    # Optional nice-to-have: if a previous Connect process crashed/was killed without
    # reaching the clean-disconnect Stop-CursorProxySidecarWatchdog call, its lease file
    # points at a Connect host PID that's no longer running. Reap just that orphaned
    # watchdog (mutex release + cmdline-scoped process kill + TEMP cleanup) once at boot,
    # before Ensure-CursorProxySidecar, so this Connect doesn't inherit a stale watchdog.
    # Never touches Mac; never kills anything not matched by the watchdog TEMP script path.
    $lease = Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.lease'
    if (-not (Test-Path -LiteralPath $lease)) { return $false }
    $leasePid = 0
    try {
        $raw = (Get-Content -LiteralPath $lease -Raw -ErrorAction Stop).Trim()
        $parts = $raw -split '\|', 2
        if ($parts.Length -ge 1) { [void][int]::TryParse($parts[0], [ref]$leasePid) }
    } catch { return $false }
    if ($leasePid -le 0 -or $leasePid -eq $PID) { return $false }
    $stillRunning = $false
    try { $stillRunning = [bool](Get-Process -Id $leasePid -ErrorAction SilentlyContinue) } catch { $stillRunning = $false }
    if ($stillRunning) { return $false }
    if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
        Write-GitModeLog ("SIDECAR_BOOT_REAP orphan_lease_pid={0}" -f $leasePid) 'WARN'
    }
    if (Get-Command Stop-CursorProxySidecarWatchdog -ErrorAction SilentlyContinue) {
        try { Stop-CursorProxySidecarWatchdog } catch {}
    }
    return $true
}

function Start-LegacyCursorProxyRelays {
    # If running Cursor still has --proxy-server on an old per-slot port, listen there and forward to 19080.
    # CIM process enumeration can hang for tens of seconds under load - bound it so
    # Ensure-CursorProxySidecar cannot freeze Connect after SIDECAR_ENSURE.
    $prof = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    $ports = @()
    try {
        $job = Start-Job -ScriptBlock {
            param($ProfNeedle)
            $found = @()
            Get-CimInstance Win32_Process -Filter "Name = 'Cursor.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
                $cmd = [string]$_.CommandLine
                if ($cmd -match [regex]::Escape($ProfNeedle) -and $cmd -match '--proxy-server=socks5://127\.0\.0\.1:(\d+)') {
                    $found += [int]$Matches[1]
                }
            }
            return $found
        } -ArgumentList $prof
        if (Wait-Job -Job $job -Timeout 2) {
            $ports = @((Receive-Job -Job $job) | Where-Object { $_ })
        } else {
            if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
                Write-GitModeLog 'SIDECAR_LEGACY skip reason=cim_timeout' 'WARN'
            }
            Stop-Job -Job $job -ErrorAction SilentlyContinue
        }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    } catch {}
    foreach ($p in ($ports | Select-Object -Unique)) {
        if ($p -eq 18999 -or $p -eq 19080) { continue }
        Start-TcpPortRelay -ListenPort $p -BackendPort 19080 -Name ("legacy_socks_$p") | Out-Null
        $http = $p + 100
        if ($http -ne 18998 -and $http -ne 19180) {
            Start-TcpPortRelay -ListenPort $http -BackendPort 19180 -Name ("legacy_http_$http") | Out-Null
        }
    }
}
