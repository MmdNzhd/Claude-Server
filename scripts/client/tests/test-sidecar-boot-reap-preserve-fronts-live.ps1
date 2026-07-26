#Requires -Version 5.1
# LIVE: with sticky fronts already listening, dead Connect lease + BootReap must NOT
# drop 18998/18999 (the multi-Connect adopt thrash that blackholed MCP).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
function Test-Port([int]$Port) {
    $c = $null
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect([System.Net.IPAddress]::Loopback, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(400)
        if (-not $ok) { return $false }
        try { $c.EndConnect($iar) } catch { return $false }
        return [bool]$c.Connected
    } catch { return $false }
    finally { if ($c) { try { $c.Close() } catch {} } }
}

Write-Host ''
Write-Host '=== Sidecar BootReap preserve fronts (LIVE) ===' -ForegroundColor Cyan

$frontOk = (Test-Port 18998) -and (Test-Port 18999)
if (-not $frontOk) {
    Write-Host '  SKIP  sticky fronts 18998/18999 not listening - start Connect first' -ForegroundColor Yellow
    exit 0
}
Assert $frontOk 'precondition: 18998 and 18999 listening'

$leasePath = Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.lease'
$leaseExistedBefore = Test-Path -LiteralPath $leasePath
$leaseBackupPath = $null
if ($leaseExistedBefore) {
    $leaseBackupPath = "$leasePath.bak-preserve-$(Get-Date -Format yyyyMMddHHmmssfff)"
    Copy-Item -LiteralPath $leasePath -Destination $leaseBackupPath -Force
}

$script:StopWatchdogCallCount = 0
function Stop-CursorProxySidecarWatchdog {
    $script:StopWatchdogCallCount++
}

try {
    $content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
    $funcSrc = Get-FunctionSource -Content $content -Name 'Invoke-CursorProxySidecarBootReap'
    Assert ($null -ne $funcSrc -and $funcSrc.Length -gt 50) 'extracted Invoke-CursorProxySidecarBootReap'
    . ([scriptblock]::Create($funcSrc))

    # Real dead PID + real listening fronts (no stub on Test-CursorProxySidecarListening:
    # load just enough helpers from sidecar for the port check used by BootReap).
    $listenSrc = Get-FunctionSource -Content $content -Name 'Test-CursorProxySidecarListening'
    if ($listenSrc) { . ([scriptblock]::Create($listenSrc)) }

    $decoy = Start-Process powershell -ArgumentList '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 30' -WindowStyle Hidden -PassThru
    $decoyPid = $decoy.Id
    Stop-Process -Id $decoyPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
    ("{0}|{1}" -f $decoyPid, (Get-Date -Format o)) | Set-Content -LiteralPath $leasePath -Encoding ASCII

    $result = Invoke-CursorProxySidecarBootReap
    Assert (-not $result) 'BootReap returns false when fronts already up (preserve)'
    Assert ($script:StopWatchdogCallCount -eq 0) 'BootReap did not call Stop-CursorProxySidecarWatchdog'
    Assert ((Test-Port 18998) -and (Test-Port 18999)) '18998/18999 still listening after BootReap'
} finally {
    if ($leaseExistedBefore -and $leaseBackupPath -and (Test-Path -LiteralPath $leaseBackupPath)) {
        Copy-Item -LiteralPath $leaseBackupPath -Destination $leasePath -Force
        Remove-Item -LiteralPath $leaseBackupPath -Force -ErrorAction SilentlyContinue
    } elseif (-not $leaseExistedBefore -and (Test-Path -LiteralPath $leasePath)) {
        Remove-Item -LiteralPath $leasePath -Force -ErrorAction SilentlyContinue
    }
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
