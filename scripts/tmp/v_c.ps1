$ErrorActionPreference='Continue'
. .\scripts\client\connect-ui.ps1

$local = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260719.log'
$probe = "VERIFY_PROBE3_{0}_{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $PID
$line = "[{0}] [INFO] [verify3] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $probe
Add-Content -LiteralPath $local -Value $line -Encoding utf8

$script:Alias = 'smart@192.168.250.70'
$script:ConnectLogPath = $local
$script:ConnectLogWriter = $null
$script:ConnectSessionId = 'verify3'
$wm = $local + '.sync-offset'
if (Test-Path $wm) {
  $script:ConnectLogSyncOffset = [int]((Get-Content $wm -Raw).Trim())
} else {
  $script:ConnectLogSyncOffset = [Math]::Max(0, (Get-Item $local).Length - 8192)
}
Write-Host ("offset={0} size={1} probe={2}" -f $script:ConnectLogSyncOffset, (Get-Item $local).Length, $probe)

$captured = New-Object System.Collections.Generic.List[string]
$oldOut = $null
# capture pipeline
$result = Sync-ConnectLogToServer 2>&1 | ForEach-Object { $captured.Add([string]$_); $_ }
$joined = ($captured -join '|')
Write-Host ("pipeline=[{0}]" -f $joined)
Write-Host ("LastConnectLogSyncOk={0}" -f $script:LastConnectLogSyncOk)
Write-Host ("new_offset={0}" -f $script:ConnectLogSyncOffset)

$found = ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -F '$probe' ~/.claude/logs/connect-20260719.log | tail -1"
Write-Host ("server_found=[{0}]" -f $found)

if ([string]::IsNullOrWhiteSpace($joined) -and $script:LastConnectLogSyncOk -and ($found -like "*$probe*")) {
  Write-Host '==== LIVE SYNC PASS ===='
  exit 0
} else {
  Write-Host '==== LIVE SYNC FAIL ===='
  # show last LOG_SYNC if any
  Select-String -Path $local -Pattern 'LOG_SYNC' | Select-Object -Last 5 | ForEach-Object { $_.Line }
  exit 1
}
