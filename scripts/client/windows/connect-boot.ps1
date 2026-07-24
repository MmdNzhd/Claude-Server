#Requires -Version 5.1
# connect-boot.ps1 - acquire one of Global\ClaudeConnect#0..#9 THEN run connect.ps1.
# Up to 10 Connect UIs per PC. Abandoned mutex frees a dead slot automatically.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$maxUi = 10

function Test-AcquireConnectUiSlot {
    param([int]$Max = 10)
    for ($i = 0; $i -lt $Max; $i++) {
        $name = "Global\ClaudeConnect#$i"
        $created = $false
        $cand = $null
        try {
            $cand = New-Object System.Threading.Mutex($false, $name, [ref]$created)
        } catch {
            continue
        }
        $got = $false
        try {
            try { $got = $cand.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        } catch {
            try { $cand.Dispose() } catch { }
            continue
        }
        if ($got) {
            return @{ Mutex = $cand; Slot = $i; Name = $name }
        }
        try { $cand.Dispose() } catch { }
    }
    return $null
}

$acq = Test-AcquireConnectUiSlot -Max $maxUi
if (-not $acq) {
    Write-Host ''
    Write-Host '  [i] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

$m = $acq.Mutex
$slot = [int]$acq.Slot
$global:ClaudeConnectBootMutex = $m
$env:CLAUDE_CONNECT_BOOT_MUTEX = '1'
$env:CLAUDE_CONNECT_UI_SLOT = [string]$slot

$connectPs1 = Join-Path $here 'connect.ps1'
if (-not (Test-Path -LiteralPath $connectPs1)) {
    try { $m.ReleaseMutex() } catch { }
    try { $m.Dispose() } catch { }
    Write-Host ''
    Write-Host '  [X] connect.ps1 missing next to connect-boot.ps1.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# #region agent log H7_boot_mutex_cost boot_before_invoke
try { [System.IO.File]::AppendAllText('D:\Smart\Claude-Code-Server\debug-c46ba1.log', ((@{sessionId='c46ba1';hypothesisId='H7_boot_mutex_cost';location='connect-boot.ps1:59';message='boot_before_invoke';data=@{now=(Get-Date).ToString('HH:mm:ss.fff');pid=$PID;slot=$slot};timestamp=[long]([DateTimeOffset](Get-Date)).ToUnixTimeMilliseconds()} | ConvertTo-Json -Compress -Depth 3) + "`n")) } catch {}
# #endregion
try {
    & $connectPs1 @args
    $ec = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
} catch {
    $ec = 1
    Write-Host ("  [X] connect.ps1 failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($global:ClaudeConnectBootMutex) {
        try { $global:ClaudeConnectBootMutex.ReleaseMutex() } catch { }
        try { $global:ClaudeConnectBootMutex.Dispose() } catch { }
        $global:ClaudeConnectBootMutex = $null
    }
    $env:CLAUDE_CONNECT_BOOT_MUTEX = $null
}
exit $ec