# test-sidecar-listening-live.ps1 - LIVE: proves the real Test-CursorProxySidecarListening
# function (scripts/client/windows/cursor-proxy-sidecar.ps1, lines 162-177) correctly detects
# whether a REAL local TCP port is listening, using an actual TcpListener/TcpClient - not a
# source-text check.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Cursor proxy sidecar port listening probe (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
$src = Get-FunctionSource -Content $content -Name 'Test-CursorProxySidecarListening'
if (-not $src) {
    Write-Host "  FAIL  could not extract Test-CursorProxySidecarListening - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($src))

# Test-LocalPortOpen (defined in git-mode.ps1) is a soft dependency the real function checks
# for via Get-Command before falling back to its own TcpClient probe. Get-FunctionSource above
# extracts ONLY this one function body - git-mode.ps1 is never dot-sourced here - so
# Test-LocalPortOpen stays undefined in this isolated scriptblock and the pure TcpClient
# fallback path (the function's own BeginConnect/EndConnect probe, lines 167-176) is what
# actually runs below. Assert that up front so the exercised code path is explicit and
# self-verifying rather than assumed.
Assert (-not (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue)) 'Test-LocalPortOpen soft-dep not loaded here - this run exercises the TcpClient fallback path, not the soft-dep delegate'

# Never reuse real production ports on this machine (18998/18999 sidecar front, 19080/19180
# backends, 20022 SSH tunnel) - pick a random ephemeral port instead so this test cannot collide
# with or interfere with a live session.
$excludedPorts = @(18998, 18999, 19080, 19180, 20022)
$port = 0
do {
    $port = Get-Random -Minimum 49152 -Maximum 65535
} while ($excludedPorts -contains $port)
Write-Host "  using random ephemeral port $port" -ForegroundColor DarkGray

$listener = $null
try {
    Assert (-not (Test-CursorProxySidecarListening -Port $port)) "port $port reports NOT listening before anything binds"

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    $listener.Start()

    Assert (Test-CursorProxySidecarListening -Port $port) "port $port reports listening once a real TcpListener is bound and started"
} finally {
    if ($listener) {
        try { $listener.Stop() } catch {}
    }
}

Assert (-not (Test-CursorProxySidecarListening -Port $port)) "port $port reports NOT listening again after the listener was stopped"

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
