$ErrorActionPreference='Continue'
$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'

Write-Output '==== ALL tunnel drop / TUNNEL_DOWN / ENSURE_TUNNEL / TUNNEL_STOP around drops ===='
# Get line numbers of drops, then context
$drops = Select-String -Path $log -Pattern 'TUNNEL: connection dropped|TUNNEL_DOWN|ENSURE_TUNNEL|TUNNEL_STOP|TUNNEL_WAIT fail|ssh_died|TUNNEL_DROP|bg_alive_forward_dead|Starting SSH tunnel failed|STALE_FORWARD'
$drops | ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line }

Write-Output ''
Write-Output '==== Context 8 lines before each connection dropped ===='
$dropLines = Select-String -Path $log -Pattern 'TUNNEL: connection dropped' | ForEach-Object LineNumber
$all = Get-Content $log
foreach ($ln in $dropLines) {
  Write-Output ("----- drop at line {0} -----" -f $ln)
  $start = [Math]::Max(0, $ln-12)
  $end = [Math]::Min($all.Count-1, $ln+5)
  for ($i=$start; $i -le $end; $i++) {
    Write-Output ("{0}|{1}" -f ($i+1), $all[$i])
  }
}

Write-Output ''
Write-Output '==== How is tunnel-down decided? (false positive clues) ===='
Select-String -Path $log -Pattern 'TUNNEL_UP port=.*up=False|banner=.*up=False|up=False banner=SSH|VERDICT_CODE=TUNNEL_DOWN' |
  Select-Object -Last 30 |
  ForEach-Object { $_.Line }

Write-Output ''
Write-Output '==== Concurrent with our kill/deploy? timestamps of fuser/pkill on 21003 ===='
Select-String -Path $log -Pattern 'fuser -k 21003|TUNNEL_STOP: killing|orphan ssh|ssh_died' |
  Select-Object -Last 40 |
  ForEach-Object { $_.Line }
