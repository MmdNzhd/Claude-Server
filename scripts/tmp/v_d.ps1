$ErrorActionPreference='Continue'
. .\scripts\client\connect-ui.ps1

$dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$test = Join-Path $dir 'verify-sync-test.log'
$probe = "VERIFY_PROBE4_{0}_{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $PID
@(
  "[{0}] [INFO] [verify4] BOOTSTRAP synthetic" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')
  "[{0}] [INFO] [verify4] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $probe
) | Set-Content -LiteralPath $test -Encoding utf8

$script:Alias = 'smart@192.168.250.70'
$script:ConnectLogPath = $test
$script:ConnectLogWriter = $null
$script:ConnectSessionId = 'verify4'
$script:ConnectLogSyncOffset = 0
$script:ConnectLogSyncFailLogged = $false

# Temporarily point day path logic: Sync uses ConnectLogPath for local, but remote day file is connect-YYYYMMDD.log
# That's fine - probe goes into today's server log.

$pipe = @(Sync-ConnectLogToServer | ForEach-Object { $_ }) -join '|'
Write-Host ("pipeline=[{0}] LastOk={1} offset={2}" -f $pipe, $script:LastConnectLogSyncOk, $script:ConnectLogSyncOffset)

$found = ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -F '$probe' ~/.claude/logs/connect-20260719.log | tail -1"
Write-Host ("server_found=[{0}]" -f $found)

# Also verify no False from function when called in Write-ConnectLog style
$script:ConnectLogWriter = [System.IO.StreamWriter]::new($test, $true, [System.Text.UTF8Encoding]::new($false))
$script:ConnectLogWriter.AutoFlush = $true
$script:ConnectLogLinesSinceSync = 24
Write-ConnectLog "INFO_BATCH_TRIGGER $probe" 'INFO'
$script:ConnectLogWriter.Close()
$script:ConnectLogWriter = $null

$found2 = ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -F 'INFO_BATCH_TRIGGER $probe' ~/.claude/logs/connect-20260719.log | tail -1"
Write-Host ("batch_found=[{0}] LastOk={1}" -f $found2, $script:LastConnectLogSyncOk)

Remove-Item $test -Force -ErrorAction SilentlyContinue
Remove-Item ($test + '.sync-offset') -Force -ErrorAction SilentlyContinue

$ok = ($script:LastConnectLogSyncOk -eq $true) -and ($found -like "*$probe*") -and ($found2 -like "*INFO_BATCH_TRIGGER*") -and [string]::IsNullOrWhiteSpace($pipe)
if ($ok) { Write-Host '==== LIVE SYNC PASS ===='; exit 0 }
Write-Host '==== LIVE SYNC FAIL ===='; exit 1
