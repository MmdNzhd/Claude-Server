$ErrorActionPreference='Continue'
$dir='C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Write-Host "ver=$((Get-Content (Join-Path $dir 'connect-version.txt') -Raw).Trim())"
$ui=Join-Path $dir 'connect-ui.ps1'
Write-Host "has_LastOk=$((Select-String -Path $ui -SimpleMatch 'LastConnectLogSyncOk' -Quiet))"
Write-Host "has_ge25=$((Select-String -Path $ui -SimpleMatch 'ConnectLogLinesSinceSync -ge 25' -Quiet))"
Write-Host "has_TRACE=$((Select-String -Path $ui -SimpleMatch \"Level -eq 'TRACE'\" -Quiet))"
Set-Location $dir
. .\connect-ui.ps1
$t=Join-Path $env:TEMP 'qsync.log'
$tag="QSYNC_$(Get-Date -Format HHmmss)"
$script:Alias='smart@192.168.250.70'
$script:ConnectLogPath=$t
$script:ConnectSessionId='q'
$script:ConnectLogSyncOffset=0
$script:ConnectLogWriter=[IO.StreamWriter]::new($t,$false,[Text.UTF8Encoding]::new($false))
$script:ConnectLogWriter.AutoFlush=$true
1..25|%{Write-ConnectLog "$tag $_" INFO}
Write-ConnectLog "$tag W" WARN
$script:ConnectLogWriter.Close(); $script:ConnectLogWriter=$null
$pipe=(Sync-ConnectLogToServer|Out-String).Trim()
Write-Host "LastOk=$($script:LastConnectLogSyncOk) pipe=[$pipe]"
$c=ssh -o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=no smart@192.168.250.70 "grep -c $tag ~/.claude/logs/connect-20260719.log; wc -c ~/.claude/logs/connect-20260719.log"
Write-Host "server=$c"
Remove-Item $t,($t+'.sync-offset') -Force -EA SilentlyContinue
