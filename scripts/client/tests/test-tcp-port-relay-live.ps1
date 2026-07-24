# test-tcp-port-relay-live.ps1 - LIVE: proves the real Start-TcpPortRelay function
# (scripts/client/windows/cursor-proxy-sidecar.ps1, lines 179-274) actually relays real TCP
# bytes end-to-end between a real listen port and a real backend port - not just that
# Test-CursorProxySidecarListening reports the front port as "listening".
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== TCP port relay real end-to-end byte relay (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw

# Add-CursorProxySidecarJobProcess / Write-GitModeLog are true soft deps that Start-TcpPortRelay
# only calls via `Get-Command ... -ErrorAction SilentlyContinue` (same soft-dep pattern the
# sibling test-sidecar-listening-live.ps1 documents for Test-LocalPortOpen). Stub them as
# no-ops BEFORE extracting/dot-sourcing Start-TcpPortRelay so it runs standalone here without
# pulling in the real Job Object machinery or git-mode.ps1's logger - neither is loaded in this
# isolated scriptblock, so without a stub these would just stay undefined (also harmless), but
# defining explicit no-op stubs makes the soft-dep call path deterministic and self-documenting.
function Add-CursorProxySidecarJobProcess { param($Process) }
function Write-GitModeLog { param($Message, $Level) }

foreach ($n in @('Test-CursorProxySidecarListening', 'Start-TcpPortRelay')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Safety confirmation: Start-TcpPortRelay's single-flight mutex is port-scoped
# (Local\ClaudeConnectSidecar-<ListenPort>), not a fixed machine-wide name, so a random
# ephemeral port picked below can never collide with the real sidecar's own mutexes for
# 18998/18999 - confirmed here against the actual source text, not assumed.
$mutexLine = '$mutexName = "Local\ClaudeConnectSidecar-$ListenPort"'
Assert ($content.Contains($mutexLine)) "Start-TcpPortRelay mutex name is port-scoped (found '$mutexLine' in source) - safe to exercise with a random ephemeral port"

# Never reuse real production ports on this machine (18998/18999 sidecar front, 19080/19180
# backends, 20022 SSH tunnel) - pick two distinct random ephemeral ports instead so this test
# cannot collide with or interfere with a live session. Freshly randomized per run is enough to
# avoid colliding with any sibling LIVE test's own freshly-randomized picks in the same run.
$excludedPorts = @(18998, 18999, 19080, 19180, 20022)
function New-RandomEphemeralPort([int[]]$Avoid) {
    $p = 0
    do {
        $p = Get-Random -Minimum 49152 -Maximum 65535
    } while (($Avoid + $excludedPorts) -contains $p)
    return $p
}
$listenPort = New-RandomEphemeralPort -Avoid @()
$backendPort = New-RandomEphemeralPort -Avoid @($listenPort)
Write-Host "  using random ephemeral listen port $listenPort, backend port $backendPort" -ForegroundColor DarkGray

$backendListener = $null
$client = $null
$clientWriter = $null
$clientReader = $null
$backendSideClient = $null
$tempPs1 = Join-Path $env:TEMP ("claude-connect-sidecar-{0}.ps1" -f $listenPort)

try {
    # Tiny real backend: a real TcpListener. Test-CursorProxySidecarListening's own real
    # connect-and-close health probe (called both internally by Start-TcpPortRelay while it
    # polls for readiness, and once more explicitly below) also gets accepted by the relay and
    # forwarded through to this same backend port as an empty, no-data connection - so this
    # backend must accept-and-filter across a few connections rather than assume the very first
    # one it sees is the real data-carrying one from our test client.
    $backendListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $backendPort)
    $backendListener.Start()

    $started = Start-TcpPortRelay -ListenPort $listenPort -BackendPort $backendPort -Name 'live-test-relay'
    Assert $started 'Start-TcpPortRelay reported success starting the relay'
    Assert (Test-CursorProxySidecarListening -Port $listenPort) "listen port $listenPort reports listening after Start-TcpPortRelay returns"

    $client = [System.Net.Sockets.TcpClient]::new()
    $client.Connect([System.Net.IPAddress]::Loopback, $listenPort)
    $client.ReceiveTimeout = 5000
    $client.SendTimeout = 5000
    $clientStream = $client.GetStream()
    $clientWriter = New-Object System.IO.StreamWriter($clientStream)
    $clientWriter.AutoFlush = $true
    $clientReader = New-Object System.IO.StreamReader($clientStream)

    $probeLine = "live-relay-probe-$listenPort-$backendPort"
    $clientWriter.WriteLine($probeLine)

    # Accept connections on the backend one at a time (each own Begin/EndAcceptTcpClient pair,
    # never overlapping) until one of them actually delivers our real probe line, discarding any
    # empty health-probe connections along the way. A handful of attempts is generous headroom
    # over the 1-2 health probes Start-TcpPortRelay/our own Assert above can generate.
    $backendReader = $null
    $backendWriter = $null
    $receivedAtBackend = $null
    $discarded = 0
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $iar = $backendListener.BeginAcceptTcpClient($null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(4000)) { break }
        $candidate = $backendListener.EndAcceptTcpClient($iar)
        $candidate.ReceiveTimeout = 2000
        $candidate.SendTimeout = 2000
        $candReader = New-Object System.IO.StreamReader($candidate.GetStream())
        $line = $null
        try { $line = $candReader.ReadLine() } catch { $line = $null }
        if ($line -eq $probeLine) {
            $backendSideClient = $candidate
            $backendReader = $candReader
            $backendWriter = New-Object System.IO.StreamWriter($candidate.GetStream())
            $backendWriter.AutoFlush = $true
            $receivedAtBackend = $line
            break
        } else {
            $discarded++
            try { $candReader.Dispose() } catch {}
            try { $candidate.Close() } catch {}
        }
    }
    if ($discarded -gt 0) {
        Write-Host "  (discarded $discarded empty health-probe connection(s) relayed to the backend before finding the real one)" -ForegroundColor DarkGray
    }

    Assert ($null -ne $backendSideClient) 'backend TcpListener actually received the real inbound connection relayed from the listen port (not just an empty health-probe connection)'
    Assert ($receivedAtBackend -eq $probeLine) "backend received the exact bytes the client sent through the relay (sent '$probeLine', backend saw '$receivedAtBackend')"

    if ($backendWriter) {
        $responseLine = "live-relay-echo-$backendPort-$listenPort"
        $backendWriter.WriteLine($responseLine)

        $receivedAtClient = $clientReader.ReadLine()
        Assert ($receivedAtClient -eq $responseLine) "client received the exact bytes the backend sent back through the relay (backend sent '$responseLine', client saw '$receivedAtClient')"
    } else {
        Assert $false 'client received the backend response through the relay (skipped - no real backend connection was found to respond from)'
    }
} finally {
    if ($clientWriter) { try { $clientWriter.Dispose() } catch {} }
    if ($clientReader) { try { $clientReader.Dispose() } catch {} }
    if ($client) { try { $client.Close() } catch {} }
    if ($backendSideClient) { try { $backendSideClient.Close() } catch {} }
    if ($backendListener) { try { $backendListener.Stop() } catch {} }

    # Kill only the relay powershell.exe process this test's Start-TcpPortRelay call spawned,
    # matched by its per-port TEMP script path in CommandLine - the same targeted-kill idiom
    # the real Stop-CursorProxySidecarRelays function uses, never a blind "kill all powershell".
    try {
        $relayProcs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [regex]::Escape("claude-connect-sidecar-$listenPort.ps1") })
        foreach ($p in $relayProcs) {
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
    } catch {}

    # Dispose (never Release - this process created the mutex but never called WaitOne on it,
    # so it does not own it) the port-scoped mutex handle Start-TcpPortRelay stashed in its own
    # script scope, mirroring how the real Stop-CursorProxySidecarRelays cleans up.
    if ($script:CursorProxySidecarPortMutexes -and $script:CursorProxySidecarPortMutexes.ContainsKey($listenPort)) {
        try { $script:CursorProxySidecarPortMutexes[$listenPort].Dispose() } catch {}
    }

    # Remove the per-port TEMP relay script this test's call created. The shared
    # claude-connect-relay-type.cs is intentionally left alone: it is not per-port, and a real
    # sidecar's watchdog may still need it to restart the 18998/18999 relays later.
    if (Test-Path -LiteralPath $tempPs1) {
        try { Remove-Item -LiteralPath $tempPs1 -Force -ErrorAction SilentlyContinue } catch {}
    }
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
