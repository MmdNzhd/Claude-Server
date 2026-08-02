# test-log-sync-delivery-nonerror.ps1 - P0.5: routine (non-ERROR) log sync must actually
# deliver. Proves:
#   1) stall/Force escape runs BEFORE -NoInline returns
#   2) Invoke-ConnectLogAsyncPump advances the watermark + emits LOG_SYNC_OK without ERROR
#   3) nullref guards + TEMP fallback remain intact
#   4) connect.ps1 session loop calls the pump (ReadKey workaround)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Log-sync delivery under non-ERROR session (P0.5) ===' -ForegroundColor Cyan

$uiPath = Get-ClientFile 'connect-ui.ps1'
$winPath = Get-ClientFile 'windows/connect.ps1'
$ui = Get-Content -LiteralPath $uiPath -Raw
$win = Get-Content -LiteralPath $winPath -Raw

# --- static contracts -------------------------------------------------------
$req = Get-FunctionSource -Content $ui -Name 'Request-ConnectLogSync'
$pump = Get-FunctionSource -Content $ui -Name 'Invoke-ConnectLogAsyncPump'
$sync = Get-FunctionSource -Content $ui -Name 'Sync-ConnectLogToServer'
Assert (-not [string]::IsNullOrWhiteSpace($req)) 'Request-ConnectLogSync extractable'
Assert (-not [string]::IsNullOrWhiteSpace($pump)) 'Invoke-ConnectLogAsyncPump extractable'
Assert (-not [string]::IsNullOrWhiteSpace($sync)) 'Sync-ConnectLogToServer extractable'

# Stall Force must appear before the NoInline early-return in source order.
$stallIdx = $req.IndexOf('Sync-ConnectLogToServer -Force')
$noInlineIdx = $req.IndexOf('if ($NoInline)')
Assert (($stallIdx -ge 0) -and ($noInlineIdx -ge 0) -and ($stallIdx -lt $noInlineIdx)) `
    'stall/Force escape runs BEFORE if ($NoInline) early-return'

Assert ($sync -match 'LOG_SYNC_OK') 'Sync-ConnectLogToServer emits LOG_SYNC_OK on success'
Assert ($sync -match '\$null -eq \$chunk') 'nullref guard before WriteAllBytes(chunk) intact'
Assert ($sync -match '\$null -eq \$chunk2') 'nullref guard before WriteAllBytes(chunk2) intact'
Assert ($sync -match 'GetTempPath\(\)') 'chunk TEMP path has GetTempPath fallback'
Assert ($ui -match 'detail=exception type=\{1\} at=\{2\}') 'typed exception breadcrumb intact'
Assert ($ui -match 'detail=chunk_read_fail') 'chunk-read fail-soft breadcrumb present (parsa NRE residual)'
Assert ($win -match 'Invoke-ConnectLogAsyncPump') 'connect.ps1 session loop calls Invoke-ConnectLogAsyncPump'

# --- live: stubbed remote legs, real watermark + LOG_SYNC_OK via pump ----------
$live = Join-Path $env:TEMP ("logsync-delivery-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null
$driver = Join-Path $live 'driver.ps1'
$driverBody = @'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
$Alias = 'claude-server'
Initialize-ConnectLog -ScriptDir $Home2 -Version 'delivery-test'
$log = $script:ConnectLogPath

# Fake a reachable sync target so Sync-ConnectLogToServer does not early-return.
function Get-ConnectLogSyncTarget { return 'claude-server' }
function Get-ConnectRemoteLogByteSize {
    param($Target, $Day, $SshOpts, $TimeoutMs)
    return [int64]$script:FakeRemoteSize
}
function Test-ConnectLogChunkAlreadyRemote { param($Target, $Day, $Chunk, $Take, $SshOpts, $TimeoutMs) return $false }
function Test-ConnectRemoteLogNeedsRebuild { param($LocalSize, $RemoteSize, $Offset) return $false }

$script:FakeRemoteSize = [int64]0
$script:ProcCalls = 0
function Invoke-ConnectLogProcTimed {
    param($Exe, $ArgumentList, $TimeoutMs)
    $script:ProcCalls++
    # mkdir / scp / cat all succeed. After a successful cat, grow the fake remote size
    # so size-verify / watermark math stays consistent.
    $joined = ($ArgumentList -join ' ')
    if ($Exe -eq 'scp' -or $joined -match 'cat "\$HOME/') {
        try {
            $fi = [System.IO.FileInfo]::new($script:ConnectLogPath)
            # Approximate: each successful append ships one chunk from offset; track via watermark later.
            if ($Exe -eq 'ssh' -and $joined -match 'cat "\$HOME/') {
                $off = [int64](Read-ConnectLogSyncWatermark -LogPath $script:ConnectLogPath)
                $len = [int64]$fi.Length
                $take = [Math]::Min([int64]524288, ($len - $off))
                if ($take -gt 0) { $script:FakeRemoteSize = $script:FakeRemoteSize + $take }
            }
        } catch { }
    }
    return @{ Ok = $true; TimedOut = $false; ExitCode = 0; StdOut = ''; StdErr = '' }
}

# Seed local day log with enough INFO lines to trip the every-25-lines NoInline path,
# without ever writing ERROR (which would Force-drain and mask the delivery bug).
1..30 | ForEach-Object { Write-ConnectLog ("delivery-probe line $_") 'INFO' }
try { $script:ConnectLogWriter.Flush() } catch { }
$beforeOff = [int64](Read-ConnectLogSyncWatermark -LogPath $log)
$fileLen = [int64]([System.IO.FileInfo]::new($log).Length)

# Fresh NoInline must stay fire-and-forget (no Sync yet) when stall window has not elapsed.
$script:ConnectLogAsyncStallSince = $null
$script:ConnectLogAsyncLastPumpAt = $null
$callsBefore = $script:ProcCalls
Request-ConnectLogSync -NoInline
$callsAfterNoInline = $script:ProcCalls

# Menu-loop pump must deliver without ERROR Force.
Invoke-ConnectLogAsyncPump -IgnoreRateLimit
try { $script:ConnectLogWriter.Flush() } catch { }
$afterOff = [int64](Read-ConnectLogSyncWatermark -LogPath $log)
$body = Get-Content -LiteralPath $log -Raw
$hasOk = [int]($body -match 'LOG_SYNC_OK')
$hasFail = [int]($body -match 'LOG_SYNC_FAIL')
$hasErrForce = [int]($body -match '\[ERROR\]')

# Stall-before-NoInline: aged StallSince + backlog > 8KB must Force inside NoInline.
# (u <= 8192 clears StallSince before the escape check - pad past that gate.)
$script:FakeRemoteSize = $afterOff
$pad = ('X' * 9000)
Write-ConnectLog ("stall-probe $pad") 'INFO'
try { $script:ConnectLogWriter.Flush() } catch { }
$script:ConnectLogAsyncStallSince = (Get-Date).AddSeconds(-61)
$script:ConnectLogSyncNeeded = $true
$forceCallsBefore = $script:ProcCalls
Request-ConnectLogSync -NoInline
$forceCallsAfter = $script:ProcCalls
$stallOff = [int64](Read-ConnectLogSyncWatermark -LogPath $log)
try { $script:ConnectLogWriter.Flush() } catch { }
$body2 = Get-Content -LiteralPath $log -Raw

Write-Output ("FILE_LEN=$fileLen")
Write-Output ("BEFORE_OFF=$beforeOff")
Write-Output ("AFTER_NOINLINE_PROCS=$callsAfterNoInline")
Write-Output ("AFTER_PUMP_OFF=$afterOff")
Write-Output ("HAS_OK=$hasOk")
Write-Output ("HAS_FAIL=$hasFail")
Write-Output ("HAS_ERROR=$hasErrForce")
Write-Output ("STALL_PROCS_DELTA=" + ($forceCallsAfter - $forceCallsBefore))
Write-Output ("STALL_OFF=$stallOff")
Write-Output ("STALL_OK=" + [int]($body2 -match 'LOG_SYNC_OK'))
'@
Set-Content -LiteralPath $driver -Value $driverBody -Encoding ASCII

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver -UiPath $uiPath -Home2 $live 2>&1
$outText = ($out | Out-String)
Write-Host '--- driver output ---'
Write-Host $outText.Trim()
Write-Host '---------------------'

function Get-Flag([string]$Name) {
    $m = [regex]::Match($outText, "(?m)^$Name=(-?\d+)\s*$")
    if ($m.Success) { return [int64]$m.Groups[1].Value }
    return -1
}

Assert ((Get-Flag 'BEFORE_OFF') -eq 0) 'watermark starts at 0 before pump delivery'
Assert ((Get-Flag 'AFTER_NOINLINE_PROCS') -eq 0) 'fresh -NoInline does not invoke SSH/SCP (still fire-and-forget)'
Assert ((Get-Flag 'AFTER_PUMP_OFF') -gt 0) ('pump advanced watermark to ' + (Get-Flag 'AFTER_PUMP_OFF') + ' (delivery completed without ERROR)')
Assert ((Get-Flag 'HAS_OK') -eq 1) 'LOG_SYNC_OK present after successful pump delivery'
Assert ((Get-Flag 'HAS_FAIL') -eq 0) 'no LOG_SYNC_FAIL during stubbed successful delivery'
Assert ((Get-Flag 'HAS_ERROR') -eq 0) 'delivery path did not require ERROR Force flush'
Assert ((Get-Flag 'STALL_PROCS_DELTA') -gt 0) 'aged stall + -NoInline invokes Sync -Force before return'
Assert ((Get-Flag 'STALL_OFF') -gt (Get-Flag 'AFTER_PUMP_OFF')) 'stall Force before NoInline further advanced watermark'

try { Remove-Item -LiteralPath $live -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): non-ERROR delivery works via pump + stall-before-NoInline.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
