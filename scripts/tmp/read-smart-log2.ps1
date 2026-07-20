$log = 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260715\windows\connect.log'
Write-Host '---- session starts/ends / ORPHAN / fail / Cursor ----'
Select-String -Path $log -Pattern 'session start|session end|ORPHAN|STALE_FORWARD|ssh_died|TUNNEL_WAIT fail|Closing|Cursor|kill|editor|clear_session|WARN' |
  ForEach-Object { $_.Line }
Write-Host ''
Write-Host '---- full line count ----'
(Get-Content $log).Count
