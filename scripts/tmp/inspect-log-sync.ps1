Set-Location 'D:\Smart\Claude-Code-Server'
Select-String -Path scripts\client\connect-ui.ps1 -Pattern 'appendOk|Write-ConnectLogSyncWatermark|Sync-ConnectLogToServer -Force|Level -eq' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }

Write-Output '--- bytes around ERROR WARN ---'
$lines=Get-Content scripts\client\connect-ui.ps1
460..475 | ForEach-Object { '{0}|{1}' -f $_, $lines[$_-1] }

Write-Output '--- appendOk region ---'
Select-String -Path scripts\client\connect-ui.ps1 -Pattern 'appendOk' -Context 5,15 | ForEach-Object {
  "MATCH L$($_.LineNumber)"
  $_.Context.PreContext
  $_.Line
  $_.Context.PostContext
}
