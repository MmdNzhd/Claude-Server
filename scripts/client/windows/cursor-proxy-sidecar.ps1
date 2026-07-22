# cursor-proxy-sidecar.ps1 - sticky local front door for Cursor CLI/settings
# Listens 127.0.0.1:18999 (SOCKS) -> backend 19080; 18998 (HTTP) -> 19180.
# Dot-sourced by connect.ps1. Mutex ensures one sidecar per machine.

$script:CursorSocksFrontPort = 18999
$script:CursorHttpFrontPort = 18998

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
    $mutexName = "Local\ClaudeConnectSidecar-$ListenPort"
    $created = $false
    try {
        $null = New-Object System.Threading.Mutex($false, $mutexName, [ref]$created)
    } catch { $created = $true }
    if (-not $created) {
        Start-Sleep -Milliseconds 500
        return (Test-CursorProxySidecarListening -Port $ListenPort)
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
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1
        ) | Out-Null
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
    $frontOk = ((Test-CursorProxySidecarListening -Port 18998) -and (Test-CursorProxySidecarListening -Port 18999))
    if (-not $frontOk) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_ENSURE restarting_front_doors' 'WARN'
        }
        $frontOk = [bool](Start-CursorProxySidecar)
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
    # settings pointed at a dead 18998. One watchdog per machine (mutex).
    $mutexName = 'Local\ClaudeConnectSidecarWatchdog'
    $created = $false
    try {
        $null = New-Object System.Threading.Mutex($false, $mutexName, [ref]$created)
    } catch { $created = $false }
    if (-not $created) { return $false }
    if ($script:CursorProxyWatchdogStarted) { return $true }
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
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wd
        ) | Out-Null
        $script:CursorProxyWatchdogStarted = $true
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'SIDECAR_WATCHDOG started' 'INFO'
        }
        return $true
    } catch {
        return $false
    }
}

function Start-LegacyCursorProxyRelays {
    # If running Cursor still has --proxy-server on an old per-slot port, listen there and forward to 19080.
    $prof = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    $ports = @()
    try {
        Get-CimInstance Win32_Process -Filter "Name = 'Cursor.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
            $cmd = [string]$_.CommandLine
            if ($cmd -match [regex]::Escape($prof) -and $cmd -match '--proxy-server=socks5://127\.0\.0\.1:(\d+)') {
                $ports += [int]$Matches[1]
            }
        }
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
