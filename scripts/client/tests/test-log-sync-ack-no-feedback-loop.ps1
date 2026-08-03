# test-log-sync-ack-no-feedback-loop.ps1 - 2026-08-03 fleet incident (hamed.kh): every
# successful Sync-ConnectLogToServer wrote its own LOG_SYNC_OK ack line into the day log
# AFTER persisting the watermark, so that ack line was immediately "new unsynced content" -
# the next sync tick shipped it, wrote another ack line, and repeated forever (~15
# syncs/min, hundreds of SSH legs/hour, live-observed starving a real deferred Server-setup
# SSH call of connection capacity). Proves the fix: after a successful sync, the watermark
# is folded forward to the file's real current length (covering the ack line itself), so a
# second sync tick with no new real content does NOT invoke any SSH/SCP legs.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Log-sync ack line must not re-trigger itself (feedback-loop fix) ===' -ForegroundColor Cyan

$uiPath = Get-ClientFile 'connect-ui.ps1'
$ui = Get-Content -LiteralPath $uiPath -Raw

# --- static contract ---------------------------------------------------------
Assert ($ui -match 'function Sync-ConnectLogAckWatermarkAdvance') 'Sync-ConnectLogAckWatermarkAdvance helper exists'
$appendSite = $ui.IndexOf('LOG_SYNC_OK off=$newOff take=$take force=$([int][bool]$Force) mode=append')
$advanceAfterAppend = $ui.IndexOf('Sync-ConnectLogAckWatermarkAdvance', $appendSite)
Assert (($appendSite -ge 0) -and ($advanceAfterAppend -gt $appendSite) -and ($advanceAfterAppend - $appendSite) -lt 400) `
    'watermark-advance call sits immediately after the append-mode LOG_SYNC_OK write'

# --- live: stubbed remote legs, real watermark math, count SSH/SCP legs across repeats ----
$live = Join-Path $env:TEMP ("logsync-ackloop-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $live | Out-Null
$driver = Join-Path $live 'driver.ps1'
$driverBody = @'
param($UiPath, $Home2)
$ErrorActionPreference = 'Continue'
$env:USERPROFILE = $Home2
. $UiPath
Initialize-ConnectLog -ScriptDir $Home2 -Version 'ackloop-test'
$log = $script:ConnectLogPath

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
    $joined = ($ArgumentList -join ' ')
    if ($Exe -eq 'ssh' -and $joined -match 'cat "\$HOME/') {
        try {
            $off = [int64](Read-ConnectLogSyncWatermark -LogPath $script:ConnectLogPath)
            $len = [int64]([System.IO.FileInfo]::new($script:ConnectLogPath)).Length
            $take = [Math]::Min([int64]524288, ($len - $off))
            if ($take -gt 0) { $script:FakeRemoteSize = $script:FakeRemoteSize + $take }
        } catch { }
    }
    return @{ Ok = $true; TimedOut = $false; ExitCode = 0; StdOut = ''; StdErr = '' }
}

# Seed real content once, then sync it for real (this first sync is EXPECTED to invoke procs).
1..5 | ForEach-Object { Write-ConnectLog ("seed line $_") 'INFO' }
try { $script:ConnectLogWriter.Flush() } catch { }

$callsBeforeFirst = $script:ProcCalls
Sync-ConnectLogToServer -Force | Out-Null
try { $script:ConnectLogWriter.Flush() } catch { }
$callsAfterFirst = $script:ProcCalls
$offAfterFirst = [int64](Read-ConnectLogSyncWatermark -LogPath $log)
$lenAfterFirst = [int64]([System.IO.FileInfo]::new($log)).Length

# The whole point of the fix: watermark must already cover the LOG_SYNC_OK line this very
# call just wrote - i.e. offset == real file length, not file-length-minus-one-ack-line.
$watermarkCoversAckLine = ($offAfterFirst -eq $lenAfterFirst)

# Now call sync AGAIN, several times, with NO new real content written in between. Before
# the fix, each of these would find its predecessor's LOG_SYNC_OK line as "new" and ship
# it (procCalls > 0 every time, forever). After the fix, there is nothing left to sync.
$repeatProcDeltas = @()
for ($i = 0; $i -lt 4; $i++) {
    $before = $script:ProcCalls
    Sync-ConnectLogToServer -Force | Out-Null
    try { $script:ConnectLogWriter.Flush() } catch { }
    $repeatProcDeltas += ($script:ProcCalls - $before)
}
$offFinal = [int64](Read-ConnectLogSyncWatermark -LogPath $log)
$lenFinal = [int64]([System.IO.FileInfo]::new($log)).Length

Write-Output ("CALLS_FIRST_SYNC=" + ($callsAfterFirst - $callsBeforeFirst))
Write-Output ("OFF_AFTER_FIRST=$offAfterFirst")
Write-Output ("LEN_AFTER_FIRST=$lenAfterFirst")
Write-Output ("WATERMARK_COVERS_ACK=" + [int]$watermarkCoversAckLine)
Write-Output ("REPEAT_PROC_DELTAS=" + ($repeatProcDeltas -join ','))
Write-Output ("REPEAT_PROC_TOTAL=" + (($repeatProcDeltas | Measure-Object -Sum).Sum))
Write-Output ("OFF_FINAL=$offFinal")
Write-Output ("LEN_FINAL=$lenFinal")
'@
Set-Content -LiteralPath $driver -Value $driverBody -Encoding ASCII

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $driver -UiPath $uiPath -Home2 $live 2>&1
$outText = ($out | Out-String)
Write-Host '--- driver output ---'
Write-Host $outText.Trim()
Write-Host '---------------------'

function Get-Flag([string]$Name) {
    $m = [regex]::Match($outText, "(?m)^$Name=(-?[\d,]*)\s*$")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

Assert ([int](Get-Flag 'CALLS_FIRST_SYNC') -gt 0) 'first real sync (seeded content) does invoke SSH/SCP legs, as expected'
Assert ([int](Get-Flag 'WATERMARK_COVERS_ACK') -eq 1) `
    'watermark after one sync == real file length (LOG_SYNC_OK ack line folded in immediately, not left dangling)'
Assert ((Get-Flag 'REPEAT_PROC_TOTAL') -eq '0') `
    'four repeat sync calls with no new content invoke ZERO SSH/SCP legs (feedback loop broken)'
Assert ((Get-Flag 'OFF_FINAL') -eq (Get-Flag 'LEN_FINAL')) 'watermark still matches file length after repeats (no drift)'

try { Remove-Item -LiteralPath $live -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): LOG_SYNC_OK ack line no longer re-triggers its own sync.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
