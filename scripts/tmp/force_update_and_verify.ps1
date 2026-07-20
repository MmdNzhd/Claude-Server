$ErrorActionPreference = 'Continue'
$dir = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Set-Location $dir
Write-Host "cwd=$dir"
Write-Host "before=$(Get-Content .\connect-version.txt -Raw)".Trim()

# Run update script the same way connect.bat does
$upd = Join-Path $dir 'connect-update.ps1'
if (-not (Test-Path $upd)) { throw "missing $upd" }
powershell -NoProfile -ExecutionPolicy Bypass -File $upd
Write-Host "after_update=$(Get-Content .\connect-version.txt -Raw)".Trim()

# Markers in updated connect-ui
$ui = Join-Path $dir 'connect-ui.ps1'
Write-Host '=== markers in desktop connect-ui ==='
Select-String -Path $ui -Pattern 'LastConnectLogSyncOk|ConnectLogLinesSinceSync -ge 25|Level -eq ''TRACE''|LOG_SYNC_FAIL' |
  ForEach-Object { '{0}:{1}' -f $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(100,$_.Line.Trim().Length)) }

# Also check newer publish folder version
$p19 = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows\connect-version.txt'
if (Test-Path $p19) { Write-Host "publish_20260719_ver=$((Get-Content $p19 -Raw).Trim())" }

# Live sync with UPDATED desktop ui
. .\connect-ui.ps1
$t = Join-Path $env:TEMP 'postupdate-sync.log'
Remove-Item $t,($t+'.sync-offset') -Force -EA SilentlyContinue
$tag = "POSTUPD_$(Get-Date -Format HHmmssfff)"
$script:Alias = 'smart@192.168.250.70'
$script:ConnectLogPath = $t
$script:ConnectSessionId = 'postupd'
$script:ConnectLogSyncOffset = 0
$script:ConnectLogSyncFailLogged = $false
$script:ConnectLogWriter = [IO.StreamWriter]::new($t, $false, [Text.UTF8Encoding]::new($false))
$script:ConnectLogWriter.AutoFlush = $true
1..30 | ForEach-Object { Write-ConnectLog "$tag line=$_" 'INFO' }
Write-ConnectLog "$tag TRACE" 'TRACE'
Write-ConnectLog "$tag WARN" 'WARN'
$script:ConnectLogWriter.Close(); $script:ConnectLogWriter = $null
$leak = 0
1..2 | ForEach-Object {
  $script:ConnectLogSyncOffset = 0
  if ((Sync-ConnectLogToServer | Out-String).Trim()) { $leak++ }
}
$cnt = (ssh -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log").Trim()
Write-Host "sync LastOk=$($script:LastConnectLogSyncOk) leaks=$leak server_count=$cnt"
Remove-Item $t,($t+'.sync-offset') -Force -EA SilentlyContinue

# server size now
ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 'wc -c ~/.claude/logs/connect-20260719.log; grep -c POSTUPD_ ~/.claude/logs/connect-20260719.log; tail -n 3 ~/.claude/logs/connect-20260719.log'
Write-Host DONE
