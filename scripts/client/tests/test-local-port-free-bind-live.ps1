# test-local-port-free-bind-live.ps1 - LIVE: Test-LocalPortFree must correctly detect a REAL
# bound TCP port vs a REAL free one using an actual System.Net.Sockets.TcpListener - not just
# a source-text/regex check on the function body.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Test-LocalPortFree real TCP bind (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$src = Get-FunctionSource -Content $content -Name 'Test-LocalPortFree'
if (-not $src) {
    Write-Host '  FAIL  could not extract Test-LocalPortFree - live test cannot run (source drifted)' -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($src))

$avoidPorts = @(18998, 18999, 19080, 19180, 20022)
$rng = New-Object System.Random
$port = 0
do {
    $port = $rng.Next(49152, 65536)
} while ($avoidPorts -contains $port)

$listener = $null
try {
    $beforeBind = Test-LocalPortFree -PortNum $port
    Assert $beforeBind "port $port reported free (`$true) before anything is bound"

    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, $port)
    $listener.Start()

    $whileBound = Test-LocalPortFree -PortNum $port
    Assert (-not $whileBound) "port $port reported NOT free (`$false) while a real TcpListener is bound to it"

    $listener.Stop()
    $listener = $null

    $deadline = (Get-Date).AddSeconds(5)
    $afterFree = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-LocalPortFree -PortNum $port) { $afterFree = $true; break }
        Start-Sleep -Milliseconds 100
    }
    Assert $afterFree "port $port reported free (`$true) again after the listener was stopped"
} finally {
    if ($listener) { try { $listener.Stop() } catch { } }
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
